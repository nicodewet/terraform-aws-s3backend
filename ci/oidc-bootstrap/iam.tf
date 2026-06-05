locals {
  account_id = data.aws_caller_identity.current.account_id

  # Full sub claims: repo prefix + each allowed ref. Anything not matching
  # (e.g. a fork PR's branch) is rejected by STS before the role is assumed.
  allowed_sub_claims = [
    for s in var.allowed_subs : "repo:${var.github_org}/${var.github_repo}:${s}"
  ]

  # ARN patterns for the resources the module provisions. Names carry a random
  # suffix (module local.namespace), so we scope by the stable name suffix with
  # a wildcard in the middle rather than by exact ARN.
  module_role_arns   = ["arn:aws:iam::${local.account_id}:role/*-tf-assume-role"]
  module_policy_arns = ["arn:aws:iam::${local.account_id}:policy/*-tf-policy"]
  module_bucket_arns = ["arn:aws:s3:::*-state-bucket"]
  module_object_arns = ["arn:aws:s3:::*-state-bucket/*"]
  module_ddb_arns    = ["arn:aws:dynamodb:*:${local.account_id}:table/*-state-lock"]
  module_rg_arns     = ["arn:aws:resource-groups:*:${local.account_id}:group/*-terraform-group"]
}

# ---------------------------------------------------------------------------
# Trust policy — who may assume the CI role, and under what OIDC claims.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ci_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # aud: the token must be minted for AWS STS specifically.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # sub: only the repo + allowed refs (main, tags). NOT a bare
    # `repo:<org>/<repo>:*` — that would admit fork-PR branches.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.allowed_sub_claims
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = var.ci_role_name
  assume_role_policy   = data.aws_iam_policy_document.ci_trust.json
  max_session_duration = 3600

  tags = {
    ManagedBy = "ci/oidc-bootstrap"
    Purpose   = "github-actions-ci"
  }
}

# ---------------------------------------------------------------------------
# Permissions policy — least privilege, scoped to exactly the services the
# module provisions. No *:*, no AdministratorAccess. Forward-looking for the
# Phase 2 e2e run (the Phase 1 smoke test only calls sts:GetCallerIdentity);
# Phase 2 will empirically confirm/refine the action sets.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ci_permissions" {
  # Identity + assuming the role the MODULE creates (the Phase 2 consume step
  # assumes *-tf-assume-role to write state through it).
  statement {
    sid       = "Identity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
  statement {
    sid       = "AssumeModuleStateRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = local.module_role_arns
  }

  # KMS — the state bucket's SSE-KMS key. CreateKey cannot be ARN-scoped, so
  # this statement is account-wide on Resource "*", but the action set is
  # limited to exactly what create/refresh/destroy of one key needs.
  statement {
    sid    = "KmsStateKey"
    effect = "Allow"
    actions = [
      "kms:CreateKey",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ListResourceTags",
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:PutKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:EnableKeyRotation",
      "kms:DisableKeyRotation",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]
    resources = ["*"]
  }

  # S3 — the state bucket and its objects. Scoped to the *-state-bucket name
  # pattern. `s3:*` (rather than enumerating ~20 GetBucket* refresh reads) is a
  # deliberate, resource-bounded wildcard: the Terraform AWS provider reads many
  # bucket sub-resources on every refresh, and the blast radius is one bucket
  # name pattern, not the account. Action-level tightening is a future refinement.
  statement {
    sid       = "S3StateBucket"
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = concat(local.module_bucket_arns, local.module_object_arns)
  }

  # DynamoDB — the state lock table, scoped to the *-state-lock name pattern.
  # dynamodb:GetItem lets the Phase 2 e2e read back the persistent digest item
  # (THEN-2: LockID = <bucket>/team1/my-cool-project-md5) to prove the consumer
  # wrote state. Read-only and table-scoped.
  statement {
    sid    = "DynamoDbLockTable"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:DescribeTable",
      "dynamodb:UpdateTable",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:DescribeTableReplicaAutoScaling",
      "dynamodb:ListTagsOfResource",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:GetItem",
    ]
    resources = local.module_ddb_arns
  }

  # IAM — the assume-role + policy the module creates. Deliberately the
  # tightest statement (IAM is the privilege-escalation surface): scoped to the
  # *-tf-assume-role / *-tf-policy name patterns, not account-wide.
  statement {
    sid    = "ModuleIamRole"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = local.module_role_arns
  }
  statement {
    sid    = "ModuleIamPolicy"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
    ]
    resources = local.module_policy_arns
  }

  # Resource Groups Tagging API — the Phase 2 e2e leak check enumerates
  # resources still carrying the module's ResourceGroup tag after teardown.
  # tag:GetResources is a read-only, account-wide query that does not support
  # resource-level scoping, so Resource must be "*"; the single action keeps the
  # blast radius to read-only discovery.
  statement {
    sid       = "LeakCheckTagging"
    effect    = "Allow"
    actions   = ["tag:GetResources"]
    resources = ["*"]
  }

  # Resource Groups — the query-based group the module creates, scoped to the
  # *-terraform-group name pattern.
  statement {
    sid    = "ModuleResourceGroup"
    effect = "Allow"
    actions = [
      "resource-groups:CreateGroup",
      "resource-groups:DeleteGroup",
      "resource-groups:GetGroup",
      "resource-groups:GetGroupQuery",
      "resource-groups:UpdateGroup",
      "resource-groups:UpdateGroupQuery",
      "resource-groups:GetTags",
      "resource-groups:Tag",
      "resource-groups:Untag",
    ]
    resources = local.module_rg_arns
  }
}

resource "aws_iam_policy" "ci_permissions" {
  name   = "${var.ci_role_name}-permissions"
  policy = data.aws_iam_policy_document.ci_permissions.json
  tags = {
    ManagedBy = "ci/oidc-bootstrap"
  }
}

resource "aws_iam_role_policy_attachment" "ci_permissions" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.ci_permissions.arn
}
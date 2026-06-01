# Plan — Phase 1: Secure GitHub Actions ↔ AWS (OIDC)

Numbered task groups; each intended to land as a single logical change on
the implementation branch (a separate branch/PR after this spec merges).
Refer to [[requirements]] for scope and [[validation]] for done-criteria.

## 1. Write the OIDC bootstrap Terraform (`ci/oidc-bootstrap/`)

1.1. New directory `ci/oidc-bootstrap/` with its own `provider "aws"` block
(region `ap-southeast-2`, no profile hard-coded — same lesson as the Phase 0
module fix). Local backend; state gitignored.

1.2. `aws_iam_openid_connect_provider` for GitHub:
- `url = "https://token.actions.githubusercontent.com"`
- `client_id_list = ["sts.amazonaws.com"]`
- thumbprint: rely on the provider's modern handling (AWS now trusts GitHub's
  OIDC via the library of trusted root CAs; pin the documented thumbprint only
  if the provider still requires it).

1.3. The CI IAM role (`s3backend-ci`) with a trust policy that:
- federates the OIDC provider from 1.2,
- `StringEquals` on `aud` = `sts.amazonaws.com`,
- `StringLike` on `sub` = `repo:nicodewet/terraform-aws-s3backend:ref:refs/heads/main`
  and `repo:nicodewet/terraform-aws-s3backend:ref:refs/tags/*`
  (two-value list — NOT a bare `repo:...:*`, which would let any fork PR in).

1.4. The least-privilege permissions policy attached to the role, covering
exactly the services the module provisions (verified against `main.tf` /
`iam.tf`): KMS, S3 (bucket + versioning + encryption + public-access-block),
DynamoDB, IAM (role/policy/attachment + the PassRole the module needs),
Resource Groups, and `sts:GetCallerIdentity`. Start from the action list the
module's own resources imply; tighten resources where create-time ARNs allow.

1.5. Variables for `github_org`, `github_repo`, and allowed refs so the trust
policy isn't hard-coded to one repo string in three places.

## 2. Apply the bootstrap once (manual, SSO admin)

2.1. With the Phase 0 SSO session active
(`aws sso login --profile s3backend-poc`; `export AWS_PROFILE=s3backend-poc`),
run `terraform init && terraform apply` in `ci/oidc-bootstrap/`.

2.2. Capture the created role ARN. Record it (sanitized — account ID redacted)
in `oidc-setup.md`. The full ARN goes into the workflow as a non-secret repo
variable or inline `role-to-assume` (it is not sensitive, but we redact it in
committed docs per the Phase 0 convention).

2.3. Confirm `terraform destroy` of the bootstrap is clean too (so teardown is
known-good), then re-apply — this is account infra that should persist.

## 3. Add the smoke-test workflow

3.1. `.github/workflows/oidc-smoke-test.yml`:
- triggers: `push` on `main` and tags, plus `workflow_dispatch`. **No
  `pull_request` trigger for the AWS job** (fork-PR isolation, [[requirements]]
  going-in decision 3).
- top-level `permissions: { id-token: write, contents: read }`.
- one job: `aws-actions/configure-aws-credentials@v4` with `role-to-assume`,
  `aws-region: ap-southeast-2`, then `run: aws sts get-caller-identity`.

3.2. Assert in the job that the resolved account is the disposable one and the
ARN is the `s3backend-ci` role (a `grep` on the identity output), so a
misconfigured role fails loudly rather than silently authenticating as
something else.

## 4. Documentation

4.1. `oidc-setup.md` in this spec dir: what the bootstrap creates, the
one-time apply command, where the role ARN goes, the fork-PR security note,
and how to rotate/revoke (delete the provider/role; there is nothing to
rotate by design).

4.2. Top-of-file comment in the bootstrap `.tf` pointing back to this spec.

## 5. Repo hygiene

5.1. Gitignore `ci/oidc-bootstrap/` local state (extend the existing
`*.tfstate*` / `.terraform/` rules if the path needs it).

5.2. Run `./ci/tf-checks.sh` — it `fmt`/`validate`s recursively, so the new
bootstrap config must be clean. (Note: `tf-checks` runs `init -backend=false`
at the repo root; confirm the new subdir doesn't break that assumption, or
scope fmt/validate appropriately.)

## 6. Verify and record the decision

6.1. Trigger the smoke-test workflow (push to `main` via the PR merge, or
`workflow_dispatch` on the branch) and confirm it authenticates with no
secrets and prints the expected caller identity.

6.2. Update [[tech-stack]] §Gaps item 2: open → done, pointer to this dir.

6.3. Walk [[validation]] top to bottom; every item must pass.

6.4. Open PR back to `main`. PR description links this spec dir and shows the
green smoke-test run.

## Open questions to resolve during implementation

- **OIDC thumbprint:** verify whether `hashicorp/aws ~> 5.64` still needs an
  explicit `thumbprint_list` or accepts the provider without one. Pin only if
  required, and note why.
- **`tf-checks` scope:** the existing script validates from the repo root; the
  bootstrap is a separate root module. Decide whether to add it to the same
  check, a separate check, or exclude it (it is not the published module).
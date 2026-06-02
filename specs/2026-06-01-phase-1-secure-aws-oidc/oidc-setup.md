# OIDC Setup — Phase 1

One-time setup that gives GitHub Actions keyless, repo-scoped access to the
disposable CI account. After this, the `oidc-smoke-test` workflow authenticates
with no long-lived secret anywhere. Aligned with [[requirements]] §Constraints.

**Who runs this:** the maintainer, once, with the Phase 0 **SSO admin** session
— *not* CI. CI only ever assumes the role created here.

## What the bootstrap creates (`ci/oidc-bootstrap/`)

- An IAM **OIDC identity provider** for `token.actions.githubusercontent.com`
  (client ID `sts.amazonaws.com`).
- An IAM role **`s3backend-ci`** whose trust policy admits only this repo on
  `refs/heads/main` and `refs/tags/*` — **fork PRs are excluded by design**
  (see [[requirements]] going-in decision 3).
- A **least-privilege** permissions policy scoped to exactly the services the
  module provisions (KMS / S3 / DynamoDB / IAM role+policy / Resource Groups /
  STS). No `AdministratorAccess`, no `*:*`.

## Step 1 — apply the bootstrap (one time)

```bash
aws sso login --profile s3backend-poc
export AWS_PROFILE=s3backend-poc
export AWS_REGION=ap-southeast-2

cd ci/oidc-bootstrap
terraform init
terraform apply        # review the plan; it creates the provider + role + policy
```

State is local and **gitignored** — nothing sensitive is committed. This is
account infrastructure that should persist; do not destroy it between CI runs.

## Step 2 — wire the role ARN into GitHub

`terraform apply` prints `ci_role_arn`. Set it as a **repository variable** (not
a secret — it isn't sensitive, but a variable keeps the account ID out of the
repo, per the Phase 0 redaction convention):

```bash
# requires the gh CLI, authenticated to the repo
gh variable set CI_ROLE_ARN --body "$(terraform output -raw ci_role_arn)"
```

The `oidc-smoke-test.yml` workflow reads `${{ vars.CI_ROLE_ARN }}`.

## Step 3 — verify

Trigger the workflow (push to `main`, or **Actions → OIDC Smoke Test → Run
workflow**). A green run that prints an `assumed-role/s3backend-ci/...` identity
confirms keyless auth works. The job fails loudly if it authenticates as
anything else.

## Rotation / revocation

There is nothing to rotate — OIDC tokens are minted per run and expire. To
revoke CI access entirely, `terraform destroy` in `ci/oidc-bootstrap/` (or
delete the role). To change which refs may assume the role, edit
`allowed_subs` and re-apply.

## Recorded values (sanitized)

- CI role ARN: `arn:aws:iam::<ACCOUNT_ID>:role/s3backend-ci`
  *(fill in after apply; redact the account ID in this committed doc — the real
  value lives in the `CI_ROLE_ARN` repo variable).*
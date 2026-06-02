# Validation — Phase 1: Secure GitHub Actions ↔ AWS (OIDC)

Done-criteria for merging the implementation branch back to `main`. Every box
must tick before the PR is approved. References [[requirements]] §Scope and
[[plan]] task groups.

**Walk result (2026-06-02):** all criteria pass. The implementation merged in
PR #11; the smoke test was confirmed green on `main` post-merge (see below).
This closeout ticks the boxes — the one item that could only be verified after
merge (a real smoke-test run) is now done.

## OIDC bootstrap

- [x] `ci/oidc-bootstrap/` exists with a self-contained Terraform config: an
  `aws_iam_openid_connect_provider` for `token.actions.githubusercontent.com`
  (client ID `sts.amazonaws.com`) and a CI role `s3backend-ci`.
- [x] The bootstrap has been applied against the disposable account and the
  resulting role ARN is recorded (sanitized) in `oidc-setup.md`.
- [x] Bootstrap local state is **not** committed (only the five `*.tf` files
  are tracked under `ci/oidc-bootstrap/`; `*.tfstate*` and `.terraform/` are
  gitignored).

## Trust policy (security-critical)

- [x] Trust policy restricts `aud` to `sts.amazonaws.com`.
- [x] Trust policy restricts `sub` to this repo and only the intended refs
  (`refs/heads/main`, `refs/tags/*`) — **not** a bare `repo:<org>/<repo>:*`.
  Verified live via `aws iam get-role --role-name s3backend-ci`.
- [x] **A fork PR cannot assume the role.** The smoke-test workflow has no
  `pull_request` trigger, and the `sub` condition rejects any ref other than
  `main`/tags. Demonstrated in practice: the workflow cannot even be triggered
  on the feature branch (the branch ref's `sub` is not in the allow-list), so
  the happy path is only reachable from `main`.

## Least-privilege

- [x] The role's permissions policy grants only the services the module
  provisions (KMS, S3, DynamoDB, IAM role/policy/attachment, Resource Groups,
  `sts`). No `*:*`, no `AdministratorAccess`. (`PassRole` was not needed — the
  module attaches a policy to the role it creates but does not pass a role to a
  service; if Phase 2 proves otherwise, it gets added then, scoped to the
  `*-tf-assume-role` pattern.)
- [x] Wildcard *actions* are justified: `s3:*` is scoped to the
  `*-state-bucket` ARN pattern (the AWS provider reads ~20 bucket sub-resources
  on every refresh; enumerating them is brittle and the blast radius is one
  bucket pattern). KMS uses an enumerated action set on `Resource "*"` because
  `kms:CreateKey` cannot be ARN-scoped. IAM — the privilege-escalation
  surface — is the tightest, scoped to `*-tf-assume-role` / `*-tf-policy`.

## Smoke-test workflow

- [x] `.github/workflows/oidc-smoke-test.yml` exists with top-level
  `permissions: id-token: write` and runs `aws sts get-caller-identity` via
  `aws-actions/configure-aws-credentials`.
- [x] A real run is green: GitHub Actions run `26852245673` on `main`
  authenticated with **no GitHub secret and no long-lived key**, printing
  `assumed-role/s3backend-ci/GitHubActions` for the disposable account, and the
  in-job assertion passed ("OK — keyless OIDC auth as s3backend-ci confirmed").
- [x] `git grep` for `AKIA`, `aws_access_key_id`, `aws_secret_access_key`
  finds no key material — the only matches are these criterion strings inside
  the validation docs themselves.

## Repo hygiene

- [x] `./ci/tf-checks.sh` passes locally — `fmt -check -recursive` (covers the
  bootstrap) and root `validate` are clean. The bootstrap is a separate root
  module, validated separately (it is not the published module).
- [x] The existing `tf-checks` and `terraform-security` workflows passed on the
  branch (PR #11, both green; Checkov did not flag the resource-scoped IAM
  wildcards at HIGH).
- [x] No change to the published module — `git diff` of `main.tf`, `iam.tf`,
  `outputs.tf`, `variables.tf`, `versions.tf` against the Phase 0 merge is
  empty. Phase 1 is CI auth only.
- [x] No end-to-end module test added — the smoke test stops at
  `get-caller-identity`; the module e2e is Phase 2.

## Decision artifact

- [x] [[tech-stack]] §Gaps item 2 reads "implemented 2026-06-02 — GitHub OIDC"
  with a rationale and a pointer to `specs/2026-06-01-phase-1-secure-aws-oidc/`.

## Spec hygiene

- [x] This feature dir contains: `requirements.md`, `plan.md`,
  `validation.md`, `oidc-setup.md`.
- [x] All `[[wikilinks]]` resolve (`mission`, `tech-stack`, `roadmap`,
  sibling files, Phase 0 dir references).

## Stop-the-line conditions

If any of these is true, **do not merge** — fix or escalate:

- A fork PR (or any ref outside the allowed list) can assume the CI role.
  This is a credential-exfiltration hole and blocks the merge outright.
- Any long-lived AWS credential is present in the repo or in GitHub Actions
  secrets — the phase has failed its core goal.
- The role required `AdministratorAccess` or a `*:*` policy to function and we
  could not articulate a least-privilege alternative — revisit [[requirements]]
  going-in decision 4 before merging.
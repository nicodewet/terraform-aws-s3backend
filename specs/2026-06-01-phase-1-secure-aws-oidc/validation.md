# Validation — Phase 1: Secure GitHub Actions ↔ AWS (OIDC)

Done-criteria for merging the implementation branch back to `main`. Every box
must tick before the PR is approved. References [[requirements]] §Scope and
[[plan]] task groups.

## OIDC bootstrap

- [ ] `ci/oidc-bootstrap/` exists with a self-contained Terraform config: an
  `aws_iam_openid_connect_provider` for `token.actions.githubusercontent.com`
  (client ID `sts.amazonaws.com`) and a CI role `s3backend-ci`.
- [ ] The bootstrap has been applied against the disposable account and the
  resulting role ARN is recorded (sanitized) in `oidc-setup.md`.
- [ ] Bootstrap local state is **not** committed (`git status` clean of
  `*.tfstate*`; `.terraform/` ignored).

## Trust policy (security-critical)

- [ ] Trust policy restricts `aud` to `sts.amazonaws.com`.
- [ ] Trust policy restricts `sub` to this repo and only the intended refs
  (`refs/heads/main`, `refs/tags/*`) — **not** a bare `repo:<org>/<repo>:*`.
- [ ] **A fork PR cannot assume the role.** The smoke-test workflow's
  AWS-touching job does not run on `pull_request` from forks (no
  `pull_request` trigger on that job), and the `sub` condition would reject it
  even if it did. Confirm by reasoning through the workflow triggers + trust
  conditions in the PR description.

## Least-privilege

- [ ] The role's permissions policy grants only the services the module
  provisions (KMS, S3, DynamoDB, IAM role/policy/attachment + PassRole,
  Resource Groups, `sts`). No `*:*`, no `AdministratorAccess`.
- [ ] Any wildcard *action* (e.g. `s3:*`) is justified in the PR against a
  specific module resource that needs it.

## Smoke-test workflow

- [ ] `.github/workflows/oidc-smoke-test.yml` exists with top-level
  `permissions: id-token: write` and runs `aws sts get-caller-identity` via
  `aws-actions/configure-aws-credentials`.
- [ ] A real run is green: the job authenticated with **no GitHub secret and
  no long-lived key**, and the printed identity is the disposable account +
  the `s3backend-ci` role. Link the run in the PR.
- [ ] `git grep` for `AKIA`, `aws_access_key_id`, and
  `aws_secret_access_key` returns zero matches across the repo (no keys snuck
  into the workflow or anywhere else).

## Repo hygiene

- [ ] `./ci/tf-checks.sh` passes locally (the new bootstrap config is
  `fmt`-clean and `validate`-clean, however it is scoped into the check).
- [ ] The existing `tf-checks` and `terraform-security` workflows pass on the
  branch (visible on the PR).
- [ ] No change to the published module (`main.tf`, `iam.tf`, `outputs.tf`,
  `variables.tf`, `versions.tf`) — Phase 1 is CI auth only. (If a module
  change is needed, stop and justify it, as Phase 0 had to.)
- [ ] No end-to-end module test added — that is Phase 2.

## Decision artifact

- [ ] [[tech-stack]] §Gaps item 2 reads done (not open), with a one-line
  rationale and a pointer to `specs/2026-06-01-phase-1-secure-aws-oidc/`.

## Spec hygiene

- [ ] This feature dir contains: `requirements.md`, `plan.md`,
  `validation.md`, `oidc-setup.md`.
- [ ] All `[[wikilinks]]` resolve (`mission`, `tech-stack`, `roadmap`,
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
# Validation — Phase 2: End-to-end "GIVEN / WHEN / THEN" test

Done-criteria for merging the implementation branch back to `main`. Every box
must tick before the PR is approved. References [[requirements]] §Scope and
[[plan]] task groups.

## Harness + fixtures

- [ ] `test/` contains a Terratest module (`go.mod`) with one e2e test, plus
  `test/fixtures/{deploy,consumer}` configs that use **this repo's** module
  (`source = "../../../"`), not the `exercises/`.
- [ ] The consumer fixture uses a partial S3 backend with `assume_role`
  supplied at init (no top-level `role_arn`, no `var.*` in the backend block).

## End-to-end behaviour

- [ ] The test applies the deploy fixture, then the consumer fixture against
  the resulting backend (assume-role), with the consumer init wrapped in a
  retry to absorb IAM eventual consistency.
- [ ] **THEN-1:** asserts the state object exists at `team1/my-cool-project`
  in the bucket (SDK `HeadObject`/list).
- [ ] **THEN-2:** asserts the DynamoDB state table holds the Terraform digest
  item for that state (`LockID = <bucket>/team1/my-cool-project-md5`).
- [ ] Both fixtures are destroyed via `defer` (consumer before deploy) — and
  destroy runs even when an assertion fails.
- [ ] A leak check asserts zero module-tagged resources survive, excluding KMS
  keys in `PendingDeletion` (Phase 0 lesson). The account is empty after.

## CI integration

- [ ] `.github/workflows/e2e-test.yml` authenticates via the Phase 1 OIDC role
  (`vars.CI_ROLE_ARN`, `id-token: write`, no long-lived secret), sets up Go,
  and runs `go test ./test/`.
- [ ] Trigger matches the decision settled in [[requirements]] (default: push
  to `main`); **no fork-PR can run the AWS-touching job.**
- [ ] A real CI run is green end-to-end; the run is linked in the PR.
- [ ] `git grep` for `AKIA` / `aws_access_key_id` / `aws_secret_access_key`
  returns no key material.

## CI-role least-privilege

- [ ] Any addition to `ci/oidc-bootstrap/iam.tf` made to get the e2e passing is
  least-privilege (scoped action + resource pattern), justified in the PR, and
  the bootstrap was re-applied. Still no `*:*` / `AdministratorAccess`.

## Repo hygiene

- [ ] `./ci/tf-checks.sh` passes locally (`fmt`/`validate` clean, including the
  new fixtures).
- [ ] `tf-checks` and `terraform-security` workflows pass on the branch.
- [ ] No change to the published module (`main.tf`, `iam.tf`, `outputs.tf`,
  `variables.tf`, `versions.tf`) — unless a real defect surfaced, justified as
  Phase 0 did.
- [ ] The fate of the Phase 0 PoC (`ci/poc-decide-ci-substrate.sh` +
  `ci/poc-fixture/`) is decided and stated (kept as a local tool, or retired).
- [ ] No `schedule:` trigger and no README badge added — those are Phases 3/4.

## Decision artifact

- [ ] [[tech-stack]] §Gaps item 3 reads done (not open), names Terratest as the
  chosen harness with a one-line rationale, and points to
  `specs/2026-06-03-phase-2-e2e-test/`.

## Spec hygiene

- [ ] This feature dir contains: `requirements.md`, `plan.md`, `validation.md`
  (+ any `HOW_TO_RUN`/notes added during implementation).
- [ ] All `[[wikilinks]]` resolve (`mission`, `tech-stack`, `roadmap`, sibling
  files, Phase 0 / Phase 1 dir references).

## Stop-the-line conditions

If any of these is true, **do not merge** — fix or escalate:

- The e2e leaked any resource and a clean run could not be reproduced.
- Cleanup needed multiple manual retries to converge — that is the reliability
  signal Phase 0 warned would undermine the real-AWS case; revisit before merge.
- The CI role required `AdministratorAccess` / `*:*` to pass — revisit
  [[requirements]] (Phase 1 least-privilege intent) before merging.
- A fork PR can trigger the AWS-touching job — credential-exfiltration hole.
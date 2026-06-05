# Validation — Phase 2: End-to-end "GIVEN / WHEN / THEN" test

Done-criteria for merging the implementation branch back to `main`. Every box
must tick before the PR is approved. References [[requirements]] §Scope and
[[plan]] task groups.

## Outcome (2026-06-06)

**All criteria met.** Implementation landed via PRs #14 (harness + workflow),
#15 (CI-role `GetGroupConfiguration` + cleanup helper), #16 (consumer retry
fix). Green end-to-end run via keyless OIDC:
<https://github.com/nicodewet/terraform-aws-s3backend/actions/runs/27039601222>
(`--- PASS: TestS3BackendEndToEnd`, leak check clean). Disposable account
verified clean afterward — the only surviving tagged resources are KMS keys in
`PendingDeletion` (expected, not leaks). See [[HOW_TO_RUN]] for the iteration
notes (two CI-role gaps and one test-retry bug found and fixed along the way).

## Harness + fixtures

- [x] `test/` contains a Terratest module (`go.mod`) with one e2e test
  (`s3backend_e2e_test.go`), plus `test/fixtures/{deploy,consumer}` configs that
  use **this repo's** module (`source = "../../../"`), not the `exercises/`.
- [x] The consumer fixture uses a partial S3 backend with `assume_role`
  supplied at init (no top-level `role_arn`, no `var.*` in the backend block).

## End-to-end behaviour

- [x] The test applies the deploy fixture, then the consumer fixture against
  the resulting backend (assume-role). The consumer init/apply retries to
  absorb IAM eventual consistency — expressed via Terratest command options
  (`MaxRetries` / `RetryableTerraformErrors`), since an outer `retry.DoWithRetry`
  around `InitAndApplyE` does not retry (Terratest wraps the failure in a
  `FatalError`). Confirmed in the green run: a `HeadObject` 403 was caught as
  *"expected … warrants a retry"* and succeeded on the next attempt.
- [x] **THEN-1:** asserts the state object exists at `team1/my-cool-project`
  in the bucket (SDK `HeadObject`).
- [x] **THEN-2:** asserts the DynamoDB state table holds the Terraform digest
  item for that state (`LockID = <bucket>/team1/my-cool-project-md5`).
- [x] Both fixtures are destroyed via `defer` (consumer before deploy, LIFO) —
  and destroy runs even when an assertion fails. The same retry options make
  teardown resilient to the propagation window too.
- [x] A leak check (`t.Cleanup`, runs after both destroys) asserts zero
  module-tagged resources survive, excluding KMS keys in `PendingDeletion`
  (Phase 0 lesson). Green run logged `clean — no unexpected resource carries
  tag …`; account spot-swept clean afterward.

## CI integration

- [x] `.github/workflows/e2e-test.yml` authenticates via the Phase 1 OIDC role
  (`vars.CI_ROLE_ARN`, `id-token: write`, no long-lived secret), sets up Go
  (from `test/go.mod`), and runs `go test ./test/`.
- [x] Trigger matches the settled decision (Option A: push to `main` +
  `workflow_dispatch`); there is no `pull_request` trigger, so **no fork-PR can
  run the AWS-touching job** (the OIDC trust policy is the defence-in-depth
  backstop).
- [x] A real CI run is green end-to-end; linked above (run 27039601222) and in
  PR #16.
- [x] `git grep` for `AKIA` / `aws_access_key_id` / `aws_secret_access_key`
  returns no key material.

## CI-role least-privilege

- [x] The additions to `ci/oidc-bootstrap/iam.tf` made to get the e2e passing
  are least-privilege (scoped action + resource pattern), justified in PRs
  #14/#15, and the bootstrap was re-applied by the maintainer (SSO admin).
  Additions: `dynamodb:GetItem` + `tag:GetResources` (assertions, PR #14) and
  `resource-groups:GetGroupConfiguration` (provider group read, PR #15). Still
  no `*:*` / `AdministratorAccess`.

## Repo hygiene

- [x] `./ci/tf-checks.sh` passes locally (`fmt`/`validate` clean, including the
  new fixtures).
- [x] `tf-checks` and `terraform-security` workflows pass on the branch
  (PRs #14/#15/#16).
- [x] No change to the published module (`main.tf`, `iam.tf`, `outputs.tf`,
  `variables.tf`, `versions.tf`) — `git diff` against the pre-Phase-2 base is
  empty for all five. Only `ci/oidc-bootstrap/iam.tf` (the CI-role policy)
  changed.
- [x] The fate of the Phase 0 PoC is decided and stated in [[HOW_TO_RUN]]:
  `ci/poc-decide-ci-substrate.sh` + `ci/poc-fixture/` are **kept as a
  dependency-free local quick-check** (no Go toolchain needed); retiring them is
  a future tidy-up, not a blocker.
- [x] No `schedule:` trigger (only a comment noting it is Phase 3) and no README
  badge added — those are Phases 3/4.

## Decision artifact

- [x] [[tech-stack]] §Gaps item 3 reads done (not open), names Terratest as the
  chosen harness with a one-line rationale, and points to
  `specs/2026-06-03-phase-2-e2e-test/`. The CI/CD table also lists
  `e2e-test.yml` and `oidc-smoke-test.yml`.

## Spec hygiene

- [x] This feature dir contains: `requirements.md`, `plan.md`, `validation.md`,
  and `HOW_TO_RUN.md` (notes added during implementation).
- [x] All `[[wikilinks]]` resolve (`mission`, `tech-stack`, `roadmap`, sibling
  files, Phase 0 / Phase 1 dir references).

## Stop-the-line conditions

If any of these is true, **do not merge** — fix or escalate:

- ~~The e2e leaked any resource and a clean run could not be reproduced.~~
  Not triggered — the green run self-cleaned; account verified empty.
- ~~Cleanup needed multiple manual retries to converge.~~ Not triggered — the
  green run's teardown converged on the first attempt with no manual help. (The
  manual `cleanup-orphan-namespace.sh` sweep was for an orphan left by an
  *earlier, failed* iteration run, and it converged in a single pass.)
- ~~The CI role required `AdministratorAccess` / `*:*` to pass.~~ Not triggered
  — all additions are scoped, least-privilege.
- ~~A fork PR can trigger the AWS-touching job.~~ Not triggered — no
  `pull_request` trigger; trust policy excludes forks.
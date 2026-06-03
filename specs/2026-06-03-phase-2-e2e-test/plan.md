# Plan — Phase 2: End-to-end "GIVEN / WHEN / THEN" test

Numbered task groups; each intended to land as a single logical change on the
implementation branch (a separate branch/PR after this spec merges). Refer to
[[requirements]] for scope and [[validation]] for done-criteria.

## 1. Test fixtures (`test/fixtures/`)

1.1. `test/fixtures/deploy/` — instantiates **this repo's** module
(`source = "../../../"`), provider with no hard-coded profile, exposes the
`s3backend_config` map output. (Promoted from `ci/poc-fixture/deploy`.)

1.2. `test/fixtures/consumer/` — partial S3 backend (`key`, `encrypt` static;
`bucket`/`region`/`dynamodb_table`/`assume_role` supplied at init) plus a
`null_resource` whose apply forces a real state write. (Promoted from
`ci/poc-fixture/test`.)

## 2. Terratest module (`test/`)

2.1. `test/go.mod` pinning `terratest`, `aws-sdk-go-v2`, and a Go version. Keep
the dependency set minimal.

2.2. `test/s3backend_e2e_test.go` — one test, GIVEN/WHEN/THEN shaped:
- **WHEN-1:** `terraform.InitAndApply` on `fixtures/deploy`; read the
  `s3backend_config` output (bucket / dynamodb_table / region / role_arn).
  `defer terraform.Destroy` immediately after apply.
- **WHEN-2:** `terraform.InitAndApply` on `fixtures/consumer` with
  `-backend-config` for bucket/region/dynamodb_table and
  `assume_role={role_arn=…}`. Wrap init in `retry.DoWithRetry` to absorb IAM
  eventual consistency (Phase 0 403). `defer terraform.Destroy` for it too.
- **THEN-1:** via AWS SDK, `HeadObject` (or list) confirms the state object
  exists at `team1/my-cool-project` in the bucket.
- **THEN-2:** `GetItem`/`Scan` confirms the DynamoDB state table holds the
  Terraform digest item (`LockID = <bucket>/team1/my-cool-project-md5`). Note:
  the *active lock* is transient; the persistent **digest** item is the stable
  thing to assert.
- **Teardown:** the two `defer`s destroy consumer then deploy. After both,
  assert the leak check (Resource Groups Tagging API for the module's
  `ResourceGroup` tag) returns nothing except KMS keys in `PendingDeletion`.

2.3. Destroy ordering + reliability: deferred LIFO gives consumer-before-deploy.
`force_destroy = true` on the bucket means deploy-destroy cleans up even if the
consumer destroy is flaky (Phase 0 lesson).

## 3. CI workflow (`.github/workflows/e2e-test.yml`)

3.1. Trigger per the [[requirements]] open decision (default: push to `main`;
authored so a `schedule:` drops in for Phase 3). **No fork-PR path.**

3.2. Job: `permissions: id-token: write`; `aws-actions/configure-aws-credentials`
with `role-to-assume: ${{ vars.CI_ROLE_ARN }}` (Phase 1); `actions/setup-go`;
`go test ./test/ -timeout 30m -v`.

3.3. The job must surface a leak as a failure even if `go test` cleanup ran —
the in-test leak assertion covers this; no separate step needed.

## 4. Make the CI role sufficient (expected iteration)

4.1. First CI run will likely reveal a missing least-privilege action in
`ci/oidc-bootstrap/iam.tf` (Phase 0 found the KMS gap this way). Add only what
the run proves is needed, keep it scoped, re-apply the bootstrap (maintainer,
SSO admin), and note each addition in the PR.

4.2. Sanity: the module's created role trusts the *caller* (default
`principal_arns`); confirm `s3backend-ci`'s session ARN is accepted as the
trust principal when the consumer step assumes `*-tf-assume-role` (Phase 0
showed the SSO session-ARN form works; verify it holds for the CI role).

## 5. Local runnability

5.1. Document running `go test ./test/` locally with the Phase 0 SSO session
(`aws sso login --profile s3backend-poc`; export creds). The test must not
depend on CI-only env.

## 6. Verify, record, hygiene

6.1. Green CI run via OIDC; link it. Confirm the disposable account is empty
afterward (leak assertion + a spot sweep, as Phase 0).

6.2. `./ci/tf-checks.sh` still passes (fixtures are `fmt`/`validate` clean).

6.3. Update [[tech-stack]] §Gaps item 3 → done, pointer to this dir. Decide the
fate of the Phase 0 PoC script (keep as local tool vs retire) and note it.

6.4. Walk [[validation]] top to bottom; open PR to `main` linking this spec and
the green run.

## Open questions to resolve during implementation

- **Go version + Terratest version pinning** and whether to commit
  `go.sum`/vendor (CI reproducibility vs noise).
- **Digest item key format** — confirm the exact `LockID` the S3 backend writes
  for this bucket/key so THEN-2 asserts the right item.
- **Test timeout** — KMS + S3 + DynamoDB + IAM create/destroy twice; size the
  `-timeout` accordingly (Phase 0 runs were ~3–5 min).
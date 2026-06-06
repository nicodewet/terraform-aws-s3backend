# How to run the Phase 2 e2e test (and implementation notes)

Companion to [[requirements]] / [[plan]] / [[validation]]. Covers running the
Terratest harness locally and in CI, plus the decisions taken during
implementation.

## What it does

`test/s3backend_e2e_test.go` (`TestS3BackendEndToEnd`):

1. **WHEN-1** — applies `test/fixtures/deploy` (this repo's module,
   `source = "../../../"`), reads the `s3backend_config` output.
2. **WHEN-2** — applies `test/fixtures/consumer` against the resulting S3
   backend, supplying `bucket`/`region`/`dynamodb_table`/`assume_role` at init
   as partial-backend config. The init+apply is wrapped in `retry.DoWithRetry`
   to absorb IAM eventual consistency (Phase 0 saw a 403 <1s after role create).
3. **THEN-1** — `s3:HeadObject` confirms the state object exists at
   `team1/my-cool-project`.
4. **THEN-2** — `dynamodb:GetItem` confirms the persistent digest item
   `LockID = <bucket>/team1/my-cool-project-md5` exists (the *active lock* is
   transient; the digest is the stable record to assert).
5. **Teardown** — two `defer terraform.Destroy` calls (consumer before deploy,
   LIFO) run even when an assertion fails. `force_destroy = true` on the bucket
   means the deploy destroy cleans up even if the consumer destroy is flaky.
6. **Leak check** — registered with `t.Cleanup` so it runs *after* both
   destroys; fails if any resource still carries the module's `ResourceGroup`
   tag, excluding KMS keys in `PendingDeletion` (expected, not a leak).

## Run it locally

The test reads **ambient** AWS credentials — it never embeds keys. Use the
Phase 0 disposable-account SSO session:

```bash
aws sso login --profile s3backend-poc
export AWS_PROFILE=s3backend-poc
export AWS_REGION=ap-southeast-2

cd test
go test ./... -timeout 30m -v
```

If Terraform's AWS SDK fails to refresh the SSO token (InvalidGrantException)
even though the CLI is happy, materialise short-lived env credentials first
(same trick as the Phase 0 PoC script):

```bash
eval "$(aws configure export-credentials --profile s3backend-poc --format env)"
unset AWS_PROFILE
```

Requires: Go (version per `test/go.mod`), Terraform `1.14.5` on PATH.

## Run it in CI

`.github/workflows/e2e-test.yml` runs on **push to `main`** and
`workflow_dispatch`. It authenticates with the Phase 1 OIDC role
(`vars.CI_ROLE_ARN`, `id-token: write`, no long-lived secret), sets up Go from
`test/go.mod`, sets up Terraform `1.14.5` (`terraform_wrapper: false` so
Terratest can parse output), and runs `go test ./... -timeout 30m -v`.

There is **no `pull_request` trigger** — the AWS-touching job must never run on a
fork PR. The OIDC trust policy (admits only `refs/heads/main` + `refs/tags/*`)
is the defence-in-depth backstop.

## Decisions taken during implementation

- **Trigger — Option A (push to `main`).** Per the [[requirements]] open
  decision and its recommendation. Fork-safe, zero trust-policy change. A
  `schedule:` trigger for daily drift detection is **Phase 3** and is
  intentionally not added; the workflow is shaped so it drops in cleanly.
- **CI-role least-privilege additions.** Two read-only actions were added to
  `ci/oidc-bootstrap/iam.tf` because the assertions run as the CI role itself:
  - `dynamodb:GetItem` (table-scoped) — THEN-2 reads the digest item.
  - `tag:GetResources` (Resource `*`; the API has no resource-level scoping) —
    the leak check enumerates tagged resources.
  Both are read-only. **The maintainer must re-apply `ci/oidc-bootstrap` with
  SSO admin** for the first green run — CI never applies the bootstrap. The KMS
  `DescribeKey` the leak check uses is already covered by the existing
  `KmsStateKey` statement. The first CI run confirms whether anything else is
  missing (Phase 0 precedent).
- **Go floor = `go.mod`'s `go` directive.** `go mod tidy` set it to the version
  a transitive dependency requires; CI uses `go-version-file: test/go.mod` so
  CI == local. `go.sum` **is committed** for reproducible builds (Go is the
  axis that most needs pinning — Terratest is pinned to `v0.56.0`).
- **Fixture `.terraform.lock.hcl` not committed.** The repo `.gitignore`
  excludes provider lock files (reusable-module convention), and the Phase 0
  `ci/poc-fixture/` — which these fixtures are promoted from — does the same.
  Provider drift within the module's `~>` constraints is acceptable and is part
  of what a future daily run is meant to catch.
- **Phase 0 PoC kept as a local quick-check** *(superseded — retired in
  Phase 6, 2026-06-06).* `ci/poc-decide-ci-substrate.sh` + `ci/poc-fixture/`
  were a dependency-free local smoke test, kept "for now" at Phase 2; once
  Terratest proved it runs locally too (above), they were removed as the
  promised tidy-up. Git history preserves them.
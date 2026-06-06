# Tech Stack

The pinned reality of how this module is built, tested, and shipped today,
plus the gaps we've explicitly decided to close. See [[mission]] for why.

## Module Code (in-repo, current)

| Layer                 | Choice                              | Notes |
|-----------------------|-------------------------------------|-------|
| IaC language          | Terraform `>= 0.15` (CI uses 1.14.5) | `versions.tf`. CI version is the contract; the floor stays low for consumers. |
| AWS provider          | `hashicorp/aws ~> 5.64.0`           | Bumped from the Manning book defaults. |
| Random provider       | `hashicorp/random ~> 3.6.2`         | For ResourceGroup suffixing. |
| Module shape          | Flat module                         | No nested sub-modules — small surface, no inter-module linking. |
| State storage         | S3 bucket, KMS-encrypted at rest    | One bucket per namespace deployment. |
| State locking         | DynamoDB table                      | Per-namespace. |
| Access control        | Least-privileged IAM assume-role    | Defaults to caller-identity ARN if `principal_arns` is unset. |
| Resource tagging      | `ResourceGroup` + `Name`            | ResourceGroup uses a randomized suffix so multiple deployments coexist. |

## Local Developer Loop

- `ci/tf-checks.sh` — runs `terraform fmt -check -recursive`,
  `terraform init -backend=false`, and `terraform validate`. This is the
  same script CI runs, so local == CI.
- `tflint` with AWS ruleset (`.tflint.hcl`, pinned to `v0.61.0` in CI).
- Checkov via Docker is documented in the README for ad-hoc local scans.

## CI / CD (GitHub Actions, current)

| Workflow                  | Trigger                                  | What it does |
|---------------------------|------------------------------------------|--------------|
| `tf-checks.yml`           | push + PR on all branches                | fmt, init (no backend), validate, tflint. |
| `terraform-security.yml`  | `workflow_run` after `tf-checks` succeeds | Checkov scan, `hard_fail_on: HIGH`, `skip_path: exercises/`. |
| `oidc-smoke-test.yml`     | push to `main` + tags + dispatch          | Proves keyless OIDC auth (`sts get-caller-identity`). |
| `e2e-test.yml`            | push to `main` + daily schedule + dispatch | Terratest end-to-end via OIDC; deploy → consume → assert → destroy → leak-check. Daily `cron` is the Phase 3 drift check. No fork-PR path. |

The `tf-checks`, `terraform-security`, and `e2e-test` ("module works") status
badges are rendered on the README badge row. Permissions are per-workflow,
least-privilege: `tf-checks`/`terraform-security` are `read-all`;
`oidc-smoke-test`/`e2e-test` grant only the `id-token: write` + `contents: read`
needed for keyless OIDC, and `e2e-test`'s scheduled drift-issue job adds a
scoped `issues: write` (on that job alone, not the AWS-touching job).

## Registry & Release

- Published as `nicodewet/s3backend/aws` on the Terraform Registry.
- Versioning: semantic version git tags trigger Registry publication
  automatically — the tag IS the release.
- No release automation yet (manual tag-and-push by the maintainer).

## Gaps (highest priority first)

These are the deliberate "not done yet" pieces. Order matches [[roadmap]].

1. **CI substrate decision: LocalStack vs disposable AWS account.**
   *Status: decided 2026-05-23 — disposable AWS account* (confirmed
   end-to-end by PoC, 2026-06-01). Fidelity is the dominant reason: the
   resources this module exercises hardest — KMS key policies/grants, IAM
   assume-role trust, DynamoDB conditional writes for locking, and S3
   `force_destroy` of versioned, KMS-encrypted objects — are exactly the ones
   LocalStack imitates imperfectly, so a green simulator run would not prove the
   module is production-ready. A throwaway PoC ran the full
   create → consume → destroy → leak-check lifecycle against the disposable
   account and, in doing so, caught real KMS-permission and provider-config
   defects in the module that a simulator would likely have masked. See
   `specs/2026-05-23-phase-0-decide-ci-substrate/` for the full reasoning, the
   PoC script, and the run log.
   Decision blocks everything below.

2. **Secure GitHub Actions ↔ AWS integration (OIDC, no long-lived keys).**
   *Status: implemented 2026-06-02 — GitHub OIDC.* `ci/oidc-bootstrap/`
   (Terraform, applied once by the maintainer with SSO admin — never by CI)
   provisions the GitHub OIDC provider and a least-privilege `s3backend-ci`
   role. The trust policy is scoped to this repo on `refs/heads/main` +
   `refs/tags/*`, so fork PRs cannot assume it. The `oidc-smoke-test` workflow
   proves keyless auth (`sts get-caller-identity`, no long-lived secret); by
   design it runs on push to `main`, so it is confirmed once Phase 1 lands.
   See `specs/2026-06-01-phase-1-secure-aws-oidc/`.

3. **End-to-end "GIVEN/WHEN/THEN" test harness.**
   *Status: implemented 2026-06-04 — Terratest (Go).* `test/` holds a single
   GIVEN/WHEN/THEN test (`s3backend_e2e_test.go`) plus dedicated
   `test/fixtures/{deploy,consumer}` configs that exercise **this repo's**
   module (`source = "../../../"`) — not the `exercises/`. It deploys the
   backend, consumes it via the module's assume-role (consumer init retried to
   absorb IAM eventual consistency), asserts the state object and the DynamoDB
   digest item exist, then `defer`-destroys both (consumer before deploy) and
   leak-checks that zero module-tagged resources survive (KMS keys in
   `PendingDeletion` excepted). Terratest was chosen over native
   `terraform test` / a shell harness because the assertions poke AWS with the
   SDK and `defer terraform.Destroy` + `retry.DoWithRetry` give reliable
   teardown and propagation handling — and it is what consumers of a public
   module expect to see. The `e2e-test.yml` workflow runs it on push to `main`
   via the Phase 1 OIDC role (no fork-PR path). See
   `specs/2026-06-03-phase-2-e2e-test/`.

4. **Daily scheduled CI run.**
   *Status: implemented 2026-06-06 — Phase 3 pending observation.* `e2e-test.yml`
   has a daily `schedule:` (`cron: "19 6 * * *"`) so drift against provider/AWS
   updates is caught without a commit, plus a `drift-issue` job that opens (or
   comments on) a `drift`-labelled GitHub issue when a *scheduled* run fails —
   so an unattended failure is not lost. Scheduled runs execute on `main`, which
   the OIDC trust already admits — no trust change; `issues: write` is scoped to
   that job only, off the AWS-touching job. Remaining before [[roadmap]] Phase 3
   reads done: observe a week of green daily runs (an observation window, not a
   code change).

5. **"Module works" public badge in README.**
   *Status: done 2026-06-06.* The native `e2e-test.yml` workflow badge
   (`?branch=main`) sits on the README badge row beside the fmt/validate and
   Checkov badges, with a short paragraph stating what it proves (lifecycle +
   no-leak against a real disposable account via OIDC, push + daily) and its
   honest limit. It is the live workflow badge, so it cannot show green unless a
   real run was green. See `specs/2026-06-06-phase-4-module-works-badge/`.

6. **Release automation.**
   Once the above is green, automate tag → changelog → Registry signal.
   Lowest priority — manual tagging is fine for now.

## Things We've Explicitly Decided NOT to Adopt (yet)

- Nested modules. Flat module is the chosen shape.
- A non-AWS backend variant.
- Terraform Cloud / TFE — the module is for self-hosted S3 state.
- Pre-commit hook framework — the `ci/tf-checks.sh` script covers the
  same ground without an extra dependency.
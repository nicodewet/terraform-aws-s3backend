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

Both workflow status badges are rendered in the README. Permissions are
locked to `read-all` at the workflow level.

## Registry & Release

- Published as `nicodewet/s3backend/aws` on the Terraform Registry.
- Versioning: semantic version git tags trigger Registry publication
  automatically — the tag IS the release.
- No release automation yet (manual tag-and-push by the maintainer).

## Gaps (highest priority first)

These are the deliberate "not done yet" pieces. Order matches [[roadmap]].

1. **CI substrate decision: LocalStack vs disposable AWS account.**
   *Status: open.* TODO.md flags this as the first decision to make.
   Constraints to weigh:
   - Fidelity: real AWS catches IAM, KMS key-policy, and DynamoDB nuances
     LocalStack imitates imperfectly (especially KMS grants and
     `force_destroy` semantics).
   - Cost & cleanup: the AWS account is created via AWS Organizations and
     treated as disposable — every CI run must leave it empty.
   - Speed: LocalStack is faster and free, which makes daily scheduled
     runs trivial.
   - Trust signal: the public "module works" badge is more credible if it
     reflects a real AWS apply.
   Decision blocks everything below.

2. **Secure GitHub Actions ↔ AWS integration (OIDC, no long-lived keys).**
   Only relevant if (1) chooses real AWS. Use OIDC federation, scope the
   trust policy to this repo + a CI-only role, never persist access keys.

3. **End-to-end "GIVEN/WHEN/THEN" test harness.**
   Provision the module, run a small consumer (the existing
   `exercises/s3backend_test`) against it, then destroy everything. Tool
   choice (Terratest in Go, native `terraform test`, or a shell harness)
   is part of this phase, not predetermined.

4. **Daily scheduled CI run.**
   The README already calls this out as a goal. A `schedule:` trigger on
   the end-to-end workflow gives us drift detection against provider
   updates even without commits.

5. **"Module works" public badge in README.**
   Surface the e2e workflow status badge alongside the existing
   fmt/validate and Checkov badges.

6. **Release automation.**
   Once the above is green, automate tag → changelog → Registry signal.
   Lowest priority — manual tagging is fine for now.

## Things We've Explicitly Decided NOT to Adopt (yet)

- Nested modules. Flat module is the chosen shape.
- A non-AWS backend variant.
- Terraform Cloud / TFE — the module is for self-hosted S3 state.
- Pre-commit hook framework — the `ci/tf-checks.sh` script covers the
  same ground without an extra dependency.
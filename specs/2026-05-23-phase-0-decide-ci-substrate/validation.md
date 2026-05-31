# Validation — Phase 0: Decide the CI substrate

Done-criteria for merging this branch back to `main`. Every box must
tick before the PR is approved. References [[requirements]] §Scope and
[[plan]] task groups.

## Decision artifact

- [x] `specs/tech-stack.md` §Gaps item 1 reads
  "decided 2026-05-23 — disposable AWS account" (not "open").
- [x] The rationale paragraph in `tech-stack.md` mentions fidelity
  (KMS / IAM / DynamoDB / `force_destroy`) as the dominant reason.
- [x] `tech-stack.md` points to
  `specs/2026-05-23-phase-0-decide-ci-substrate/` for the full
  reasoning.
- [x] No new top-level directory has been introduced (no
  `specs/decisions/` — that was rejected per [[requirements]]).

## PoC script

- [x] `ci/poc-decide-ci-substrate.sh` exists and is executable
  (`ls -l` shows the `x` bits).
- [x] Script begins with `set -euo pipefail` and registers a cleanup
  trap that fires on any exit code.
- [x] Script has no hardcoded AWS account ID, no hardcoded ARN, no
  hardcoded access key. `git grep` for `AKIA`, `arn:aws:iam::[0-9]`,
  and the account ID returns zero matches in the script.
- [~] Script length: **170 lines** (110 code; the other 60 are the
  header doc block + inline comments documenting the four module/tooling
  defects the PoC surfaced). Over the ~150 soft ceiling by design — the
  logic itself is well under it, so the script is not "doing too much".

## End-to-end run

- [x] The script has been run end-to-end against the disposable
  AWS account, with output captured at
  `specs/2026-05-23-phase-0-decide-ci-substrate/poc-run.log` (sanitized:
  account ID and SSO role suffix redacted, per the same no-identifiers-on-
  the-public-repo rule that gitignores `tmp.md`).
- [x] The log shows `Apply complete` for both `ci/poc-fixture/deploy`
  and `ci/poc-fixture/test`. **(Deviation from the original plan, which
  named `exercises/s3backend_deploy` / `exercises/s3backend_test`.** Those
  were unusable: the deploy exercise pins the *published* registry module
  rather than this repo's code, and the test exercise's backend block
  referenced `var.*`, which Terraform forbids. A self-contained fixture
  under `ci/poc-fixture/` exercises the **local** module — see
  [[requirements]] §Scope.)
- [x] The log shows all three assertions (bucket head, DDB describe,
  state-object ls) returning success.
- [x] The log shows `Destroy complete` for both fixtures.
- [x] The post-cleanup leak check ran and reported zero unexpected
  module-tagged resources. (KMS keys in `PendingDeletion` are excluded:
  `terraform destroy` schedules KMS deletion rather than deleting, so the
  tagged key lingers through its window — expected, not a leak.)
- [x] Post-run spot-check confirmed no surviving module-tagged S3 buckets,
  DynamoDB tables, or IAM roles in the disposable account. Done
  **programmatically** (CLI sweep) rather than via the console, and noted in
  the log — the console step was a manual stand-in for exactly this check.

## Repo hygiene

- [x] `./ci/tf-checks.sh` passes locally — `terraform fmt -check` and
  `terraform validate` both succeed. (A fresh provider download can trip
  Terraform's plugin-start timeout on the first exec locally; re-running
  after the binary is warm passes. Environmental, not a code issue.)
- [ ] The existing `tf-checks` and `terraform-security` GitHub Actions
  workflows pass on this branch — **verify on the PR** (pending push).
- [~] Module changed: `main.tf` and `iam.tf` were edited. **This deviates
  from the original "decision + PoC only" intent, and is justified** — the
  PoC could not complete without them, and both are genuine defect fixes the
  PoC surfaced:
  - `main.tf`: removed an embedded `provider "aws" { profile = "default" }`
    that overrode the consumer's credentials and contradicted `versions.tf`.
  - `iam.tf`: granted the assume-role principal `kms:Decrypt` /
    `GenerateDataKey` / `DescribeKey` on the state key, without which the
    role can't read/write the SSE-KMS state bucket (403).
  `outputs.tf`, `variables.tf`, `versions.tf` are untouched. The change to
  the published module's IAM contract needs a version bump + changelog when
  released (called out in the commit and the PR).
- [x] No new long-running CI workflow added — that's Phase 2.
- [x] No README badge changes — that's Phase 4.

## Spec hygiene

- [x] This feature dir contains: `requirements.md`, `plan.md`,
  `validation.md`, `poc-run.log`, plus `auth-setup.md` (the one-time local
  SSO setup the PoC depends on; added on this branch and linked from
  `plan.md`). `tmp.md` (scratch capture of account/SSO identifiers) is
  present locally but **gitignored** — never committed. The script's header
  doc block made a separate `HOW_TO_RUN.md` unnecessary.
- [x] All `[[wikilinks]]` in this dir resolve to real files
  (`mission`, `tech-stack`, `roadmap`, `auth-setup`, sibling spec files).

## Stop-the-line conditions

If any of these is true, **do not merge** — fix or escalate:

- The PoC leaked any resource and we couldn't reproduce a clean run.
- Cleanup took multiple manual retries to converge — that's a
  reliability signal that destroys the case for real AWS; revisit
  [[requirements]] §Rationale before merging.
- Cost from a single run exceeded a few cents — investigate before
  enabling daily runs in Phase 3.

# Validation — Phase 0: Decide the CI substrate

Done-criteria for merging this branch back to `main`. Every box must
tick before the PR is approved. References [[requirements]] §Scope and
[[plan]] task groups.

## Decision artifact

- [ ] `specs/tech-stack.md` §Gaps item 1 reads
  "decided 2026-05-23 — disposable AWS account" (not "open").
- [ ] The rationale paragraph in `tech-stack.md` mentions fidelity
  (KMS / IAM / DynamoDB / `force_destroy`) as the dominant reason.
- [ ] `tech-stack.md` points to
  `specs/2026-05-23-phase-0-decide-ci-substrate/` for the full
  reasoning.
- [ ] No new top-level directory has been introduced (no
  `specs/decisions/` — that was rejected per [[requirements]]).

## PoC script

- [ ] `ci/poc-decide-ci-substrate.sh` exists and is executable
  (`ls -l` shows the `x` bits).
- [ ] Script begins with `set -euo pipefail` and registers a cleanup
  trap that fires on any exit code.
- [ ] Script has no hardcoded AWS account ID, no hardcoded ARN, no
  hardcoded access key. `git grep` for `AKIA`, `arn:aws:iam::[0-9]`,
  and the account ID returns zero matches in the script.
- [ ] Script is under ~150 lines.

## End-to-end run

- [ ] The script has been run at least once against the disposable
  AWS account, with output captured at
  `specs/2026-05-23-phase-0-decide-ci-substrate/poc-run.log`.
- [ ] The log shows `apply complete` for both
  `exercises/s3backend_deploy` and `exercises/s3backend_test`.
- [ ] The log shows all three assertions (bucket head, DDB describe,
  state-object ls) returning success.
- [ ] The log shows `destroy complete` for both modules.
- [ ] The post-cleanup leak check ran and reported zero
  module-tagged resources remaining.
- [ ] Manual AWS console spot-check confirmed: no S3 buckets, no
  DynamoDB tables, no IAM roles, no KMS keys with the module's tags
  survive in the disposable account. The console check is noted in
  the log.

## Repo hygiene

- [ ] `./ci/tf-checks.sh` passes locally.
- [ ] The existing `tf-checks` and `terraform-security` GitHub Actions
  workflows pass on this branch (visible on the PR).
- [ ] No changes to `iam.tf`, `main.tf`, `outputs.tf`, `variables.tf`,
  or `versions.tf` — Phase 0 is decision + PoC only, not module
  changes. (If a module change snuck in, justify it in the PR or
  pull it out.)
- [ ] No new long-running CI workflow added — that's Phase 2.
- [ ] No README badge changes — that's Phase 4.

## Spec hygiene

- [ ] This feature dir contains exactly: `requirements.md`, `plan.md`,
  `validation.md`, `poc-run.log` (after the run).
  Optional: `HOW_TO_RUN.md` if the script's comment block proved
  insufficient.
- [ ] All `[[wikilinks]]` in this dir resolve to real files
  (`mission`, `tech-stack`, `roadmap`, sibling spec files).

## Stop-the-line conditions

If any of these is true, **do not merge** — fix or escalate:

- The PoC leaked any resource and we couldn't reproduce a clean run.
- Cleanup took multiple manual retries to converge — that's a
  reliability signal that destroys the case for real AWS; revisit
  [[requirements]] §Rationale before merging.
- Cost from a single run exceeded a few cents — investigate before
  enabling daily runs in Phase 3.

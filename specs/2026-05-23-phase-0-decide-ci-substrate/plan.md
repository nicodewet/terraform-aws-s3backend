# Plan — Phase 0: Decide the CI substrate

Numbered task groups. Each group is intended to land as a single logical
change. Refer to [[requirements]] for scope and [[validation]] for the
done-criteria.

## 1. Record the decision in tech-stack.md

1.1. Edit `specs/tech-stack.md` §Gaps item 1 ("CI substrate decision")
in place:
- Change the status line from "open" to
  "decided 2026-05-23 — disposable AWS account".
- Replace the constraints list with a 2–3 sentence rationale summarizing
  the fidelity argument from [[requirements]] §Rationale.
- Add a pointer line: "See `specs/2026-05-23-phase-0-decide-ci-substrate/`."

1.2. Sanity-check that no other section of `tech-stack.md` still implies
the question is open.

## 2. Set up local AWS auth to the disposable account

2.1. Follow [[auth-setup]] end to end. Decisions already baked in there:
IAM Identity Center (SSO) federating into the Org sub-account, profile
name `s3backend-poc`, region `ap-southeast-2`.

2.2. Verify with
`aws sts get-caller-identity --profile s3backend-poc`. The `Account`
field must match the disposable sub-account; the `Arn` must include
`AWSReservedSSO_*`. Do not proceed until this passes.

## 3. Build the minimal PoC script

3.1. Add `ci/poc-decide-ci-substrate.sh` (chosen name reflects it is a
single-purpose phase-0 artifact, not the long-term test harness).

3.2. Script behavior, in order:
- `set -euo pipefail` and a trap that runs cleanup on any exit.
- Preflight: assert `terraform`, `aws`, `jq` are on PATH; assert
  `AWS_REGION` is set; assert `aws sts get-caller-identity` succeeds.
- Step A: `cd exercises/s3backend_deploy && terraform init &&
  terraform apply -auto-approve`. Capture the four outputs
  (`bucket`, `dynamodb_table`, `region`, `role_arn`) via
  `terraform output -json`.
- Step B: `cd exercises/s3backend_test && terraform init` with the
  four `-backend-config` flags populated from Step A, then
  `terraform apply -auto-approve`.
- Assertion 1: `aws s3api head-bucket --bucket $BUCKET` returns 0.
- Assertion 2: `aws dynamodb describe-table --table-name $DDB_TABLE`
  returns 0.
- Assertion 3: `aws s3 ls s3://$BUCKET/team1/my-cool-project` shows the
  state object exists.
- Cleanup (also runs on failure via the trap):
  - `cd exercises/s3backend_test && terraform destroy -auto-approve`
  - `cd exercises/s3backend_deploy && terraform destroy -auto-approve`
- Post-cleanup leak check: query Resource Groups Tagging API for any
  resource tagged with the module's `ResourceGroup` key. Non-empty
  result → exit non-zero with a clear message naming the leaked ARNs.

3.3. `chmod +x ci/poc-decide-ci-substrate.sh`.

3.4. Hard ceiling: ~150 lines. If we hit it, simplify rather than split.

## 4. Document how to run the PoC

4.1. Add a top-of-script comment block: purpose, prereqs (terraform/aws/jq
versions), required env vars (`AWS_REGION`, plus whatever auth the
operator uses), single-command run instruction, expected duration.

4.2. Add a short section to `requirements.md` §Context (or a sibling
`HOW_TO_RUN.md` if the comment block grows) so the spec dir is
self-explanatory without opening the script.

## 5. Run the PoC end-to-end

5.1. Execute the script against the disposable account. Tee output to
`specs/2026-05-23-phase-0-decide-ci-substrate/poc-run.log`.

5.2. After completion, open the AWS console for the disposable account
and visually confirm: no S3 buckets, no DynamoDB tables, no IAM roles,
no KMS keys remain that carry the module's tags. Note the check in the
log file.

5.3. If anything leaks, stop. Diagnose, fix the script, re-run from a
clean account. Do not move on until the leak check passes.

## 6. Verify and commit

6.1. Run `./ci/tf-checks.sh` locally; confirm no regressions.

6.2. Walk [[validation]] top to bottom; every item must pass.

6.3. Commit with the existing repo style (terse, lowercase) — one
commit for the decision/tech-stack edit, one for the PoC script and
its log, or a single squashed commit. Maintainer's call.

6.4. Open PR back to `main`. PR description links this spec dir.
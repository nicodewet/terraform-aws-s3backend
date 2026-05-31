# Requirements — Phase 0: Decide the CI substrate

Resolves the open gap "CI substrate decision: LocalStack vs disposable AWS
account" in [[tech-stack]] §Gaps. Aligned with [[mission]] (ordered goals
mastery → production-ready → teaching) and [[roadmap]] Phase 0.

## Going-in decision

**Use the disposable AWS account (provisioned via AWS Organizations) as
the CI substrate. LocalStack is rejected for this module.**

This decision is the going-in position for this branch; the PoC exists to
confirm it works end-to-end, not to re-litigate it.

### Rationale

1. **Fidelity is the dominant criterion** (per stakeholder tiebreaker).
   The four resources this module exercises hardest are exactly the ones
   LocalStack imitates imperfectly:
   - KMS key policies and grants (S3 SSE-KMS uses grants in subtle ways).
   - IAM assume-role with cross-principal trust policies.
   - DynamoDB conditional writes (the basis for state locking).
   - S3 `force_destroy` semantics with versioned, KMS-encrypted objects.
   A green LocalStack run would not tell us the module is production-ready.
2. **Mission ordering reinforces this.** Goal #1 is personal mastery of
   the real guardrails — running against a simulator dilutes the learning.
   Goal #2 (production-ready public module) is undermined if the
   "module works" badge reflects a simulator, not AWS.
3. **The disposable account already exists.** TODO.md confirms an AWS
   Organizations sub-account was created specifically for this purpose.
   Choosing LocalStack means that account becomes dead weight.
4. **Cost is bounded.** Per-run cost is dominated by KMS key creation
   and a tiny amount of DynamoDB/S3 — order of cents per run if cleanup
   is reliable. Cleanup reliability is a hard requirement (see below).

### What we accept by choosing real AWS

- CI runs take minutes, not seconds. Daily-scheduled runs (Phase 3) are
  still feasible.
- Cleanup leaks cost money. The PoC must prove the destroy path is
  reliable before we wire CI to it (Phase 2).
- Auth must be solved. Out of scope here; addressed in Phase 1 (OIDC).

## Scope

In scope for this branch:

1. Update [[tech-stack]] §Gaps entry #1 in place — change from "open" to
   the decision above with a short rationale and a pointer to this dir.
2. Build a minimal proof-of-concept script that, against the disposable
   AWS account using locally-available credentials, performs:
   - `terraform init && terraform apply` of a deploy fixture that sources
     **this repo's** module
   - `terraform init && terraform apply` of a consumer fixture using the
     backend outputs from the previous step
   - `terraform destroy` of both, in reverse order
   - A post-cleanup check that the disposable account has no
     module-tagged resources remaining

   *Implementation note (added after the PoC run):* the fixtures live under
   `ci/poc-fixture/{deploy,test}` rather than reusing
   `exercises/s3backend_{deploy,test}`. The deploy exercise pins the
   *published* registry module (so it would not gate this repo's code), and
   the test exercise's backend block referenced `var.*`, which Terraform
   forbids. The fixture sources the local module and supplies the backend
   `assume_role` at init time. Running it also surfaced two real module
   defects (an embedded `provider` block overriding consumer credentials, and
   a missing KMS grant on the assume-role policy); both were fixed in
   `main.tf` / `iam.tf` on this branch and need a version bump when released.
3. Run the PoC end-to-end at least once against the disposable account.
   Capture the output in a log file under this feature dir.
4. Document how to run the PoC (prereqs, env vars, expected output).

## Out of scope

- **OIDC / GitHub Actions auth.** Phase 1. The PoC runs locally with
  whatever credentials the operator already has (env vars or
  `~/.aws/credentials`). No CI workflow is added in this branch.
- **Test framework choice** (Terratest vs native `terraform test` vs
  shell). Phase 2. The PoC is a thin bash script — deliberately not the
  long-term test harness.
- **Assertions beyond "resources exist".** Deep semantic assertions
  belong in Phase 2.
- **Scheduled runs.** Phase 3.
- **README badge updates.** Phase 4.

## Constraints

- **No long-lived credentials in the repo.** The PoC reads creds from
  the environment; nothing is committed.
- **Cleanup is mandatory, not optional.** The PoC must run `destroy`
  even if `apply` fails partway, and must report (non-zero exit) if any
  module-tagged resource survives.
- **No new top-level convention.** The decision lives inline in
  `specs/tech-stack.md` per stakeholder preference — no `specs/decisions/`
  directory is introduced.
- **PoC stays minimal.** A single bash script in `ci/` or `scripts/`,
  not a new framework. If it grows past ~150 lines, it is doing too much
  and should be deferred to Phase 2.

## Context

- Source TODO entry: `TODO.md` §Now bullet 1 (disposable account for CI)
  and bullet 4 (LocalStack vs AWS question).
- Mission ordering: [[mission]] §Ordered Goals.
- Current gap entry being resolved: [[tech-stack]] §Gaps item 1.
- PoC fixtures: `ci/poc-fixture/{deploy,test}` (self-contained; source the
  local module). Modelled on `exercises/s3backend_{deploy,test}`, which
  proved unusable as-is — see §Scope item 2.
# Roadmap

A high-level implementation order derived from `TODO.md` and aligned with
[[mission]] and [[tech-stack]]. Phases are intentionally small — each one
should land as a focused PR (or a tight series). Order matters: later
phases assume earlier ones are green.

## Phase 0 — Decide the CI substrate

**Status: ✅ Done (2026-06-01).** Decision recorded in [[tech-stack]] §Gaps
item 1; PoC ran green against the disposable account.

**Goal.** Pick LocalStack vs a disposable AWS account for end-to-end CI,
record the decision, and prove the chosen substrate end-to-end with a
minimal proof-of-concept.

Detailed plan and rationale live in
`specs/2026-05-23-phase-0-decide-ci-substrate/`. The going-in decision
is **disposable AWS account** (fidelity-led — KMS grants, IAM
assume-role, DynamoDB conditional writes, and `force_destroy` semantics
are the things LocalStack imitates imperfectly and the things this
module exercises hardest).

- Reason through the choice and record it in [[tech-stack]] §Gaps in
  place (no `specs/decisions/` directory — explicitly rejected).
- Build a minimal bash PoC that `apply`s `exercises/s3backend_deploy`,
  `apply`s `exercises/s3backend_test` against it, asserts resources
  exist, then `destroy`s in reverse order. Cleanup is mandatory.
- Run the PoC end-to-end against the disposable AWS account. Capture
  the log in the feature dir. Post-cleanup leak check must report zero
  module-tagged resources.

**Done when.** The decision is recorded in `tech-stack.md`, the PoC
script lives in `ci/`, it has run cleanly at least once against the
disposable account, and `roadmap.md` has been re-read in light of the
decision.

## Phase 1 — Secure GitHub Actions ↔ AWS integration

**Status: ✅ Done (2026-06-02).** GitHub OIDC + least-privilege `s3backend-ci`
role; keyless auth confirmed. See `specs/2026-06-01-phase-1-secure-aws-oidc/`.

**Goal.** Keyless, repo-scoped access to the CI AWS account.

- Configure GitHub's OIDC provider in the CI AWS account.
- Create a CI-only IAM role with a trust policy scoped to this repo and
  branch/tag patterns; attach the minimum permissions the module needs
  to create and destroy its own resources.
- Wire `aws-actions/configure-aws-credentials` into a new workflow stub
  that just runs `aws sts get-caller-identity` as a smoke test.

**Done when.** A CI job authenticates to the disposable account with no
long-lived secrets in the repo.

## Phase 2 — End-to-end "GIVEN / WHEN / THEN" workflow

**Status: ✅ Done (2026-06-06).** Terratest harness, green via OIDC. See
`specs/2026-06-03-phase-2-e2e-test/`.

**Goal.** Prove the module actually deploys and tears down.

- Choose the harness (Terratest, native `terraform test`, or shell) and
  document why.
- GIVEN: a clean disposable AWS account.
- WHEN: `terraform apply` on `exercises/s3backend_deploy`, then
  `terraform apply` on `exercises/s3backend_test` using the backend
  outputs.
- THEN: assert the state object exists in the bucket and the lock entry
  exists in DynamoDB.
- Always run `terraform destroy` (success or failure) so the account
  comes back to empty. Idempotent cleanup on retry.

**Done when.** A single workflow runs end-to-end on every push and PR,
and the disposable account is empty after each run.

**As built (deviations, see the spec).** Harness = **Terratest (Go)**. The
fixtures are dedicated `test/fixtures/{deploy,consumer}` using **this repo's**
module (`source = "../../../"`), **not** the `exercises/` — Phase 0 found the
exercises unusable (deploy pins the published registry module; the test
exercise's backend used `var.*`). THEN also asserts the persistent DynamoDB
**digest** item, not a transient lock. Trigger is **push to `main`** (Option A),
not "every push and PR" — Phase 1's fork-isolation constraint excludes fork PRs
from the AWS-touching job.

## Phase 3 — Daily scheduled drift check

**Status: ✅ Implemented (2026-06-06); observation pending.** Daily `schedule:`
(`cron: "19 6 * * *"`) + a `drift`-labelled-issue job on scheduled failure.
"Done when" below still needs a week of green daily runs to elapse.

**Goal.** Catch provider/AWS regressions without waiting for a commit.

- Add a `schedule:` trigger (daily) to the Phase 2 workflow.
- On failure: open a GitHub issue automatically (label `drift`).

**Done when.** A daily run has been green for at least a week without
manual intervention.

## Phase 4 — Public "module works" badge

**Status: ✅ Done (2026-06-06).** Live `e2e-test.yml` badge (`?branch=main`) on
the README badge row + an honest paragraph on what it proves. See
`specs/2026-06-06-phase-4-module-works-badge/`.

**Goal.** Give Terraform Registry consumers a visible trust signal.

- Add the Phase 2/3 workflow status badge to README, alongside the
  existing fmt/validate and Checkov badges.
- Short README paragraph explaining what the badge actually proves
  (apply + assertions + destroy against the disposable AWS account).

**Done when.** The badge is live in README and links to the latest run.

## Phase 5 — Release automation (lowest priority)

**Goal.** Make cutting a Registry version low-friction.

- Generate a changelog from commit/PR titles between tags.
- A workflow that, on a new semver tag, posts release notes and verifies
  the Registry picked the tag up.

**Done when.** Tagging `vX.Y.Z` requires no manual steps beyond `git tag`
and `git push --tags`.

## Out of Scope (for this roadmap)

- Multi-region or multi-account topologies inside the module itself.
- Migrating away from the flat-module shape.
- Adding non-AWS backend variants.

Anything not listed here is implicitly "later" — re-open this file before
starting work that doesn't fit a phase.

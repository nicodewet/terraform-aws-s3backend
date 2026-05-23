# Roadmap

A high-level implementation order derived from `TODO.md` and aligned with
[[mission]] and [[tech-stack]]. Phases are intentionally small — each one
should land as a focused PR (or a tight series). Order matters: later
phases assume earlier ones are green.

## Phase 0 — Decide the CI substrate

**Goal.** Pick LocalStack vs a disposable AWS account for end-to-end CI,
and write the decision down so we don't re-litigate it.

- Spike: stand up the module against LocalStack; record what fails or
  diverges (KMS grants, IAM assume-role, DynamoDB locking semantics).
- Spike: confirm the disposable AWS Organizations account can be reached
  from GitHub Actions (auth method TBD in Phase 1).
- Decision recorded in `specs/decisions/` (new file, ADR-style) or as an
  update to `tech-stack.md` §Gaps.

**Done when.** A written decision exists and the rest of this roadmap is
re-read in light of it.

## Phase 1 — Secure GitHub Actions ↔ AWS integration

*Only if Phase 0 picks real AWS. If LocalStack wins, skip to Phase 2.*

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

**Goal.** Prove the module actually deploys and tears down.

- Choose the harness (Terratest, native `terraform test`, or shell) and
  document why.
- GIVEN: a clean account/LocalStack.
- WHEN: `terraform apply` on `exercises/s3backend_deploy`, then
  `terraform apply` on `exercises/s3backend_test` using the backend
  outputs.
- THEN: assert the state object exists in the bucket and the lock entry
  exists in DynamoDB.
- Always run `terraform destroy` (success or failure) so the account
  comes back to empty. Idempotent cleanup on retry.

**Done when.** A single workflow runs end-to-end on every push and PR,
and the disposable account is empty after each run.

## Phase 3 — Daily scheduled drift check

**Goal.** Catch provider/AWS regressions without waiting for a commit.

- Add a `schedule:` trigger (daily) to the Phase 2 workflow.
- On failure: open a GitHub issue automatically (label `drift`).

**Done when.** A daily run has been green for at least a week without
manual intervention.

## Phase 4 — Public "module works" badge

**Goal.** Give Terraform Registry consumers a visible trust signal.

- Add the Phase 2/3 workflow status badge to README, alongside the
  existing fmt/validate and Checkov badges.
- Short README paragraph explaining what the badge actually proves
  (apply + assertions + destroy against real AWS or LocalStack).

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

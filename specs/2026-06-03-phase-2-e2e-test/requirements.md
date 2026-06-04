# Requirements — Phase 2: End-to-end "GIVEN / WHEN / THEN" test

Resolves the gap "End-to-end GIVEN/WHEN/THEN test harness" in [[tech-stack]]
§Gaps item 3. Aligned with [[mission]] (Goal #1 mastery of CI/CD for IaC;
Goal #2 a public module strangers can trust; Goal #3 a teaching artifact) and
[[roadmap]] Phase 2. Builds on Phase 0 (the disposable-account substrate +
lifecycle PoC) and Phase 1 (keyless OIDC; the `s3backend-ci` role).

## Going-in decisions

These are the positions this branch starts from. The spec PR is the place to
confirm or challenge them; nothing is implemented until the spec merges.

1. **Harness: Terratest (Go).** The roadmap left the tool open; we pick
   Terratest.
   - *Why:* it is the industry-standard for Terraform module end-to-end tests,
     and it fits these specific assertions best — checking that the **S3 state
     object** and the **DynamoDB lock/digest item** exist means poking AWS with
     the SDK, which Terratest does idiomatically. `defer terraform.Destroy`
     gives reliable teardown even when an assertion fails, and `retry.DoWithRetry`
     directly addresses the IAM eventual-consistency race Phase 0 hit.
   - *Cost we accept:* a Go toolchain enters the repo. That serves Goal #1
     (mastery) and Goal #3 (Terratest is what consumers of a public module
     expect to see), so the cost is aligned with the mission, not against it.

2. **Reuse the local module via dedicated test fixtures — not the
   `exercises/`.** Phase 0 already established the `exercises/` are unusable
   (the deploy exercise pins the *published* registry module; the test
   exercise's backend block used `var.*`). Phase 2 tests **this repo's**
   module. The fixtures live under `test/fixtures/` (Terratest convention),
   promoted from the proven Phase 0 `ci/poc-fixture/` shapes.

3. **The Phase 0 PoC is superseded for CI, not deleted yet.**
   `ci/poc-decide-ci-substrate.sh` + `ci/poc-fixture/` were explicitly a
   throwaway local proof. Terratest becomes the long-term harness. We keep the
   PoC script as a local quick-check for now; retiring it is a tidy-up, not a
   blocker (call it out in the PR).

4. **The `s3backend-ci` least-privilege policy will be exercised for real for
   the first time, and may need additions.** Phase 1's policy was
   forward-looking; Phase 2 is the first time CI actually runs the module under
   it. Exactly as Phase 0 discovered the missing KMS grant, this run may reveal
   a missing action. Tightening/adding to `ci/oidc-bootstrap/iam.tf` to make
   the e2e pass is **in scope** (and re-applied via the bootstrap), provided
   each addition stays least-privilege and is justified.

## Open decision — to settle in spec review

**How is the e2e workflow triggered, given Phase 1's trust policy admits only
`main` + tags (fork PRs excluded)?**

- **Option A — push to `main` + (later) schedule.** e2e runs on push to
  `main`; PRs keep the current fmt/validate/Checkov. Fork-safe, zero
  trust-policy change. Trade-off: no full e2e signal on a PR before merge.
- **Option B — also same-repo PRs.** Additionally run e2e on PRs from branches
  in this repo (never forks). Requires widening the OIDC trust `sub` to a
  same-repo pull-request claim and gating fork PRs out in the workflow. More
  pre-merge signal, larger security surface.

*Recommendation:* start with **A** (B can be layered on later if pre-merge e2e
proves worth the trust-policy surface). The roadmap's "on every push and PR"
predates the Phase 1 fork-isolation constraint, so this is a deliberate, noted
deviation either way.

## Scope

In scope for this branch (spec only) and the implementation branch that
follows:

1. A Terratest module under `test/` (`go.mod`, one e2e test) that:
   - **GIVEN** a clean disposable account,
   - **WHEN** it applies the deploy fixture (this repo's module), then applies
     the consumer fixture against the resulting backend (assume-role),
   - **THEN** asserts the **state object** exists at `team1/my-cool-project`
     in the bucket and the **DynamoDB state table holds the digest item**,
   - **always** destroys both (reverse order) via `defer`, and leak-checks
     that zero module-tagged resources survive.
2. `test/fixtures/{deploy,consumer}` Terraform configs (local-module based).
3. A new GitHub Actions workflow that authenticates via the Phase 1 OIDC role,
   sets up Go, and runs `go test`. Trigger per the open decision above.
4. Run it green at least once (in CI, via OIDC). Capture/link the run.
5. Update [[tech-stack]] §Gaps item 3 to done, with a pointer to this dir.

## Out of scope

- **Daily scheduled run.** Phase 3 (the workflow is authored so a `schedule:`
  trigger drops in cleanly).
- **README "module works" badge.** Phase 4.
- **Deep semantic assertions** beyond "the state object and lock/digest exist".
  Phase 2 proves the lifecycle works, not every module property.
- **Changing the published module** (`main.tf`, `iam.tf`, …) — unless a real
  defect surfaces (Phase 0 precedent); the `ci/oidc-bootstrap` CI-role policy
  is the one thing expected to need adjustment.

## Constraints

- **Always destroy; idempotent on retry; zero leaks.** `defer terraform.Destroy`
  plus a post-run leak check (Resource Groups Tagging API, as Phase 0). KMS
  keys in `PendingDeletion` are not leaks (Phase 0 lesson).
- **No long-lived credentials.** CI uses the OIDC role; local runs use the
  Phase 0 SSO session. The test reads ambient creds — never embeds keys.
- **IAM eventual consistency is handled, not ignored** — retry the assume-role
  consume step (Phase 0 saw a 403 when assuming <1s after role creation).
- **Cost bounded** — per [[requirements]] of Phase 0, a run is cents; the leak
  check is the guardrail.
- **Runnable locally**, not only in CI, so the maintainer can iterate.

## Context

- Resolves: [[tech-stack]] §Gaps item 3.
- Predecessors: `specs/2026-05-23-phase-0-decide-ci-substrate/` (substrate,
  lifecycle PoC, the fixture shapes, the KMS/IAM-propagation lessons) and
  `specs/2026-06-01-phase-1-secure-aws-oidc/` (the `s3backend-ci` OIDC role
  this workflow assumes).
- Mission ordering: [[mission]] §Ordered Goals.
- Reference: Terratest — `https://terratest.gruntwork.io/`.
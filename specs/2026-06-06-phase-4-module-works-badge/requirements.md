# Requirements — Phase 4: Public "module works" badge

Resolves the gap "'Module works' public badge in README" in [[tech-stack]]
§Gaps item 5 and [[roadmap]] Phase 4. Serves [[mission]] Goal #2 (a
production-ready public module strangers can trust — "a visible signal that the
module actually deploys end-to-end") and Goal #3 (teaching artifact: the README
should explain what the signal means). Builds on Phase 2 (the e2e workflow) and
Phase 3 (the daily scheduled drift run).

## Going-in decisions

Positions this branch starts from. The spec PR is the place to confirm or
challenge them; nothing is implemented until the spec merges.

1. **Native GitHub Actions workflow badge, not shields.io.** Use the built-in
   `actions/workflows/e2e-test.yml/badge.svg` (the same mechanism the existing
   `tf-checks` / `terraform-security` badges use), linking to the workflow page.
   - *Why:* zero new dependency or endpoint, consistent with the two badges
     already in the README, and it reflects real run status — it cannot show
     green unless a real run was green. A custom shields.io endpoint would add a
     moving part for no gain here.

2. **The badge sits alongside the existing two, on the README's badge line.**
   One coherent badge row at the top: `tf-checks`, `terraform-security`, then the
   new e2e ("module works") badge. No new section above the fold.

3. **An honest one-paragraph explanation accompanies it.** Per [[mission]]
   Goal #3 and the [[roadmap]] Phase 4 bullet, a short paragraph states exactly
   what the badge proves — apply + assertions + destroy against a *real
   disposable AWS account* via keyless OIDC, on push to `main` and daily — and,
   just as importantly, what it does **not** prove (it is a lifecycle/no-leak
   signal, not a guarantee of every module property). No overclaiming.

## Open decision — to settle in spec review

**What run state should the badge track?** The native badge supports an
optional query (`?branch=` / `?event=`):

- **Option A — default (last run on the default branch).** `…/badge.svg` with
  no query. Simplest; reflects the most recent `main` run (push or schedule).
  Already green today.
- **Option B — `?branch=main`.** Explicitly pin to the default branch. Same
  practical result as A right now, but robust if non-`main` runs ever appear.
- **Option C — `?event=schedule`.** Track the *daily drift* run specifically —
  arguably the truest "still works against live AWS" signal. Trade-off: it shows
  **no status** until the first scheduled run completes (next 06:19 UTC after
  merge), and a transient AWS/propagation blip on one nightly run would redden
  the public badge until the next night.

*Recommendation:* **Option B (`?branch=main`)** — immediately green (we have
green push runs), stable, and not hostage to a single nightly blip. The daily
drift run still gates quality via the Phase 3 `drift`-issue automation; the
public badge does not need to be the drift alarm.

## Scope

In scope for this branch (spec only) and the implementation branch that follows:

1. Add the `e2e-test.yml` status badge to the README badge line, linking to the
   workflow, with an accessible alt text (e.g. "Module Works (e2e)").
2. A short README paragraph explaining what the badge proves and its honest
   limits (lifecycle + no-leak against a real disposable account, not every
   property), and that it also runs daily (drift).
3. Settle the open decision (badge query) and apply it.
4. Update [[tech-stack]] §Gaps item 5 → done, and the CI/CD note that currently
   reads "the e2e 'module works' badge is Phase 4".

## Out of scope

- **Any change to the e2e workflow or the module.** Phase 4 is README + docs.
- **A coverage/version/registry badge.** Only the e2e "module works" signal.
- **Release automation** — Phase 5.
- **Waiting out Phase 3's week-of-green observation.** That is a separate
  done-criterion for Phase 3; the badge does not depend on it (it reflects
  whatever the latest tracked run was).

## Constraints

- **Real status only.** The badge must be the live workflow badge — never a
  static/hand-set "passing" image. (A green badge that can lie violates
  [[mission]] Goal #2's "signal strangers can trust".)
- **Honest copy.** The explanatory paragraph must not overclaim; it states the
  lifecycle/no-leak scope and the daily cadence, and links the badge to the run
  history.
- **No markdown regressions.** The existing two badges and the rest of the
  README render unchanged; the badge row stays a single line.

## Context

- Resolves: [[tech-stack]] §Gaps item 5; [[roadmap]] Phase 4.
- Predecessors: `specs/2026-06-03-phase-2-e2e-test/` (the workflow the badge
  reflects) and Phase 3 (daily schedule + `drift` issue automation, added to
  that workflow).
- Reference: GitHub Actions workflow status badges —
  `https://docs.github.com/actions/monitoring-and-troubleshooting-workflows/adding-a-workflow-status-badge`.
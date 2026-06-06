# Requirements — Phase 5: Release automation

Resolves [[tech-stack]] §Gaps item 6 and [[roadmap]] Phase 5. Serves [[mission]]
Goal #2 (a production-ready public module — low-friction, trustworthy releases)
and the mission's "semantic versioning is the contract". Lowest-priority phase;
builds on the now-green CI (Phases 2–4).

## Where we are today

- Published as `nicodewet/s3backend/aws` on the Terraform Registry.
- The **git tag IS the release**: pushing a semver tag (`v0.1.0` … `v0.6.0`
  today) triggers the Registry's webhook and it publishes automatically. The
  Registry reports the version without the `v` (`0.6.0`).
- No GitHub Releases, no changelog, no release workflow — tag-and-push is a bare
  manual step and leaves no human-readable release notes behind.

## Going-in decisions

Positions this branch starts from. The spec PR is the place to confirm or
challenge them; nothing is implemented until the spec merges.

1. **React to the tag; don't replace it.** The maintainer still runs
   `git tag vX.Y.Z && git push --tags` — that stays the single source of truth
   and the [[roadmap]] "Done when". A new `release.yml` triggers
   `on: push: tags` (matching `v[0-9]+.[0-9]+.[0-9]+`) and does the rest.

2. **Auto-generated GitHub Release notes, no committed `CHANGELOG.md`.** Use
   `gh release create --generate-notes` (notes built from merged PR titles since
   the previous tag), optionally shaped by a `.github/release.yml` category
   config.
   - *Why:* the repo's history is PR-titled and clean (that is the raw
     material), and a committed changelog would force the workflow to commit
     back to the repo — extra surface and a second source of truth. The GitHub
     Release is the human-readable artifact; the tag stays canonical.

3. **Verify Registry ingestion against the public API.** After creating the
   Release, poll `https://registry.terraform.io/v1/modules/nicodewet/s3backend/aws/versions`
   until the new version (tag minus the `v`) appears, with a bounded
   timeout/backoff (ingestion is async/webhook-driven, usually minutes).
   - *Why:* [[mission]] Goal #2 — don't *claim* a release shipped to consumers
     without checking it actually landed.

4. **Least privilege.** `release.yml` needs only `contents: write` (create the
   Release + read tags). **No AWS, no OIDC, no `id-token`** — releasing touches
   GitHub + the public Registry API, not the disposable account.

## Open decisions — to settle in spec review

1. **Gate the release on a green e2e for the tagged commit?** e2e currently runs
   on push-to-`main` + schedule, **not** on tags.
   - *A — no gate.* Trust that the maintainer tags a known-good `main` commit
     (whose last push already ran a green e2e). Simplest.
   - *B — gate.* Before creating the Release, require the e2e Check for that SHA
     to be green (commit-status/Checks API), or re-run e2e on the tag (needs a
     tag trigger + OIDC on the e2e workflow — more surface).
   - *Recommendation:* **A** now (the tag comes off green `main`); note B as a
     future hardening once tagging cadence justifies it.

2. **Hard-fail vs soft-warn if the Registry version doesn't appear in time.**
   Ingestion delay is outside our control.
   - *Recommendation:* poll ~10 min; **fail** the job if not seen (a visible
     signal that the webhook/Registry didn't pick it up), but make clear in the
     log that the Release itself succeeded and this is the external-dependency
     step.

3. **How to validate the workflow without polluting the public Registry.** Any
   matching tag publishes for real.
   - *Recommendation:* dry-run the notes + verify logic via `workflow_dispatch`
     (no Release created) first, then prove it end-to-end on the **next genuine
     version bump** (e.g. `v0.7.0`) rather than a throwaway tag.

## Scope

In scope for this branch (spec only) and the implementation branch that follows:

1. `.github/workflows/release.yml`: on semver tag push, create a GitHub Release
   with auto-generated notes, then verify the Registry published the version.
2. Optionally `.github/release.yml` to categorise the auto-notes
   (features / fixes / docs / chore).
3. Settle the open decisions and apply them.
4. Update [[tech-stack]] §Gaps item 6 → done and the Registry & Release section;
   [[roadmap]] Phase 5 → status marker. Document the (still one-step) release
   procedure.

## Out of scope

- **Choosing/auto-bumping the version or auto-tagging.** The maintainer decides
  the semver and pushes the tag — keeping tagging manual is the explicit
  [[roadmap]] "Done when".
- **The 1.0 decision**, signing/provenance/SLSA, and any change to the module or
  the Registry connection itself.
- **Gating releases on e2e** unless open decision 1 selects Option B.

## Constraints

- **No manual steps beyond `git tag` + `git push --tags`** ([[roadmap]] Phase 5
  "Done when").
- **Least privilege** — `contents: write` only; no AWS/OIDC.
- **Idempotent / safe to re-run** — re-running on an existing tag must not error
  out or create a duplicate Release (check first / `--verify-tag`).
- **Honest verification** — the Registry-pickup check queries the real API; no
  assumed success.

## Context

- Resolves: [[tech-stack]] §Gaps item 6; [[roadmap]] Phase 5.
- Predecessors: Phases 2–4 (the green CI + public badge a release leans on).
- References: GitHub auto-generated release notes —
  `https://docs.github.com/repositories/releasing-projects-on-github/automatically-generated-release-notes`;
  Terraform Registry module API —
  `https://developer.hashicorp.com/terraform/registry/api-docs`.

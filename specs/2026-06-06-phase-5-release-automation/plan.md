# Plan — Phase 5: Release automation

Numbered task groups; intended to land as a small PR after this spec merges.
Refer to [[requirements]] for scope/decisions and [[validation]] for
done-criteria. No change to the module or to the existing AWS-touching
workflows.

## 1. Release workflow (`.github/workflows/release.yml`)

1.1. Trigger `on: push: tags: ["v[0-9]+.[0-9]+.[0-9]+"]`. Single job,
`runs-on: ubuntu-latest`, `permissions: contents: write` only (no `id-token`,
no AWS).

1.2. Checkout (full history / tags, `fetch-depth: 0`) so notes generation can
diff against the previous tag.

1.3. Create the GitHub Release for the pushed tag with auto-generated notes —
`gh release create "$GITHUB_REF_NAME" --generate-notes --verify-tag` using the
built-in `GITHUB_TOKEN`. Idempotency: if a Release for the tag already exists,
skip creation (check with `gh release view`) so a re-run doesn't error.

1.4. Verify Registry ingestion: derive `version="${GITHUB_REF_NAME#v}"`, then
poll `https://registry.terraform.io/v1/modules/nicodewet/s3backend/aws/versions`
until `version` appears, with bounded retries/backoff (~10 min total). On
timeout, behave per [[requirements]] open decision 2 (recommend: fail, but log
clearly that the Release succeeded and this is the external-dependency step).

1.5. (Open decision 1) If Option B is chosen: before 1.3, require the e2e Check
for the tag's SHA to be green (Checks/commit-status API) and stop otherwise.
Default (Option A): no gate.

## 2. Release-notes shaping (optional)

2.1. Add `.github/release.yml` to categorise auto-notes (e.g. Features / Fixes /
Docs / Chore / Dependencies) by PR label or title prefix, so the generated notes
read well. Keep it light — the notes are a convenience, the tag is canonical.

## 3. Decision artifact + docs

3.1. [[tech-stack]] §Gaps item 6 → done; update the Registry & Release section
("manual tag-and-push" → "tag-and-push, then automated Release + Registry
verify").

3.2. [[roadmap]] Phase 5 → status marker done.

3.3. Document the release procedure (one step — `git tag vX.Y.Z &&
git push --tags` — and what the automation then does) in the spec dir
(`HOW_TO_RELEASE.md`) and/or the README.

## 4. Verify, record, hygiene

4.1. Dry-run the notes + Registry-verify logic via `workflow_dispatch` (guarded
so it does **not** create a Release) to prove the script before a real tag.

4.2. Prove end-to-end on the **next genuine version bump** (e.g. `v0.7.0`):
confirm a GitHub Release with notes appears and the Registry versions API lists
the new version. Link the Release + the workflow run.

4.3. Confirm no AWS credentials are referenced anywhere in `release.yml`
(`git grep` for `aws`/`role-to-assume`/`id-token` in the file returns nothing).

4.4. `./ci/tf-checks.sh` still passes; existing workflows unaffected. Walk
[[validation]] top to bottom; open the PR to `main` linking this spec.

## Open questions to resolve during implementation

- **e2e gate (open decision 1)** — A (no gate) vs B (require green e2e for SHA).
- **Registry verify on timeout (open decision 2)** — hard-fail vs soft-warn, and
  the exact poll window/backoff.
- **Notes categorisation** — whether `.github/release.yml` is worth it now or
  plain `--generate-notes` suffices for a single-maintainer repo.
- **README mention** — add a short "Releases" pointer, or keep it spec-only.

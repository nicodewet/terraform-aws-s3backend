# Validation — Phase 5: Release automation

Done-criteria for merging the implementation branch back to `main`. Every box
must tick before the PR is approved. References [[requirements]] §Scope and
[[plan]] task groups.

## Release workflow

- [ ] `.github/workflows/release.yml` triggers on a semver tag push
  (`v[0-9]+.[0-9]+.[0-9]+`) and on nothing else.
- [ ] It creates a GitHub Release for the pushed tag with **auto-generated
  notes** (`--generate-notes`), using the built-in `GITHUB_TOKEN`.
- [ ] Re-running on an existing tag does not error or double-create the Release
  (idempotent — checked before create).
- [ ] After the Release, it verifies the Terraform Registry published the
  version: polls the versions API for `${tag#v}` with a bounded timeout, and
  behaves on timeout per the settled [[requirements]] open decision 2.

## Least privilege

- [ ] The workflow grants only `contents: write` (plus default `contents: read`
  semantics) — **no `id-token`, no AWS credentials, no OIDC role**. `git grep`
  in `release.yml` for `aws` / `role-to-assume` / `id-token` returns nothing.
- [ ] (If open decision 1 = B) the e2e-green gate for the tag SHA is present and
  scoped; otherwise no gate, as decided.

## Proven end-to-end

- [ ] The notes + verify logic was dry-run via `workflow_dispatch` without
  creating a Release.
- [ ] A genuine tag (e.g. `v0.7.0`) produced a GitHub Release with readable
  notes **and** the Registry versions API lists the new version. Both linked in
  the PR.

## No regressions / scope

- [ ] No change to the module (`*.tf`) or to `tf-checks` / `terraform-security`
  / `oidc-smoke-test` / `e2e-test`.
- [ ] Releasing still requires no manual step beyond `git tag vX.Y.Z` +
  `git push --tags` ([[roadmap]] "Done when").
- [ ] No auto-tagging / version-bumping logic was added (out of scope).
- [ ] `./ci/tf-checks.sh` passes.

## Decision artifact

- [ ] [[tech-stack]] §Gaps item 6 reads done (not open) and points to
  `specs/2026-06-06-phase-5-release-automation/`; the Registry & Release section
  no longer says "no release automation yet".
- [ ] [[roadmap]] Phase 5 carries a done status marker.

## Spec hygiene

- [ ] This feature dir contains `requirements.md`, `plan.md`, `validation.md`
  (+ any `HOW_TO_RELEASE`/notes added during implementation).
- [ ] All `[[wikilinks]]` resolve (`mission`, `tech-stack`, `roadmap`, sibling
  files, Phase 2–4 references).

## Stop-the-line conditions

If any of these is true, **do not merge** — fix or escalate:

- The workflow needs broader than `contents: write` (e.g. AWS creds or
  `id-token`) — releasing must not touch the disposable account.
- A Release was created but the Registry never ingested the version, and the
  cause (webhook/Registry config) is unexplained — don't ship a release path
  that silently fails to publish.
- The automation introduces a manual step beyond `git tag` + `git push --tags`,
  contradicting the [[roadmap]] "Done when".
- A throwaway/test tag published a junk version to the **public** Registry that
  cannot be cleanly removed (validate without polluting — [[requirements]] open
  decision 3).

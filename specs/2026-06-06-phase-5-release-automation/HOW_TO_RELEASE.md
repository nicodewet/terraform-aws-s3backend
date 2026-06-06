# How to cut a release

Companion to [[requirements]] / [[plan]] / [[validation]]. The git tag is the
release; everything else is automated by `.github/workflows/release.yml`.

## Cut a release (the only manual step)

```bash
# from an up-to-date, green main
git tag v0.7.0            # choose the semver (see "Choosing the version")
git push --tags
```

That's it. Pushing a `vMAJOR.MINOR.PATCH` tag does two things:

1. The **Terraform Registry** webhook publishes `nicodewet/s3backend/aws` at that
   version automatically (this has always worked — the tag *is* the release).
2. **`release.yml`** fires on the tag and:
   - creates a **GitHub Release** for the tag with auto-generated notes (built
     from merged PR titles since the previous tag), and
   - **verifies** the Registry actually lists the new version (polls the public
     versions API for ~10 min; fails loudly if it never appears, while noting the
     Release itself succeeded).

No changelog file to edit, no release notes to write by hand, no AWS — the
workflow holds only `contents: write`.

## Dry run (no Release created)

To preview the notes and exercise the verify poll without cutting anything, run
the workflow manually against an existing tag:

- **Actions → Release → Run workflow**, set `tag` to an existing tag (e.g.
  `v0.6.0`).

It prints the notes that *would* be generated and confirms the Registry lists
that version — but creates no Release.

## Choosing the version

Semantic versioning is the contract ([[mission]]). The module is pre-1.0, so
breaking changes may still ship in a minor; cutting `v1.0.0` is a separate,
deliberate decision (out of scope here). The workflow does **not** pick or bump
the version — you choose the tag.

## If the Registry-verify step fails

The GitHub Release was still created; only the external Registry ingestion
check timed out. Check:

- the tag is a clean `vX.Y.Z` and was pushed,
- the Registry/GitHub webhook for `nicodewet/s3backend/aws` is healthy
  (Registry ingestion is webhook-driven and usually lands within minutes),
- the versions API: `https://registry.terraform.io/v1/modules/nicodewet/s3backend/aws/versions`.

Re-running the workflow on the same tag is safe (Release creation is idempotent).

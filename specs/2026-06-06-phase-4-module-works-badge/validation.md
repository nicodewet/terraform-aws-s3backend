# Validation — Phase 4: Public "module works" badge

Done-criteria for merging the implementation branch back to `main`. Every box
must tick before the PR is approved. References [[requirements]] §Scope and
[[plan]] task groups.

## Badge

- [ ] The README badge line shows a third badge for `e2e-test.yml`, after the
  existing `tf-checks` and `terraform-security` badges, on a single row.
- [ ] The badge is the **native** GitHub Actions workflow badge
  (`actions/workflows/e2e-test.yml/badge.svg`) — not a static image — and links
  to the workflow page.
- [ ] The query (`?branch=main` per the settled [[requirements]] decision, or
  the agreed alternative) is applied, and the rendered badge is **green** at
  merge time.
- [ ] Alt text is meaningful for screen readers (e.g. "Module Works (e2e)").

## Explanatory copy

- [ ] A short paragraph (2–4 sentences) states what the badge proves: push-to-
  `main` + daily deploy of **this** module into a real disposable AWS account
  via keyless OIDC, assert state object + DynamoDB digest, then destroy +
  leak-check.
- [ ] The copy states the honest limit — a lifecycle + no-leak signal, not a
  guarantee of every property — i.e. it does not overclaim.
- [ ] The copy / badge points the reader to the run history.

## No regressions

- [ ] The existing two badges and the rest of the README render unchanged
  (alt text + links preserved; badge row is still one line).
- [ ] No change to `e2e-test.yml`, the module, or any other workflow.
- [ ] `./ci/tf-checks.sh` passes locally; `tf-checks` / `terraform-security`
  pass on the branch.

## Decision artifact

- [ ] [[tech-stack]] §Gaps item 5 reads done (not open), names the native badge,
  and points to `specs/2026-06-06-phase-4-module-works-badge/`.
- [ ] The [[tech-stack]] CI/CD note no longer says the e2e badge is "Phase 4"
  (it is live); [[roadmap]] Phase 4 carries a done status marker.

## Spec hygiene

- [ ] This feature dir contains `requirements.md`, `plan.md`, `validation.md`
  (+ any notes added during implementation).
- [ ] All `[[wikilinks]]` resolve (`mission`, `tech-stack`, `roadmap`, sibling
  files, Phase 2 / Phase 3 references).

## Stop-the-line conditions

If any of these is true, **do not merge** — fix or escalate:

- The badge is a static/hand-set image rather than the live workflow badge —
  a green badge that can lie breaks [[mission]] Goal #2's "signal strangers can
  trust".
- The badge renders red/unknown at merge (investigate the tracked run before
  publishing a trust signal that says the module is broken).
- The explanatory copy overclaims (implies the badge proves more than the
  lifecycle/no-leak scope).
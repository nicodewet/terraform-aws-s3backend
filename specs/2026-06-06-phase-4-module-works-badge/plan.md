# Plan — Phase 4: Public "module works" badge

Numbered task groups; intended to land as a single small PR after this spec
merges. Refer to [[requirements]] for scope and [[validation]] for
done-criteria. This is a docs-only phase — no workflow or module change.

## 1. README badge

1.1. Add the e2e badge to the existing badge line (line 3), after
`terraform-security`, using the native workflow badge:
`![Module Works (e2e)](…/actions/workflows/e2e-test.yml/badge.svg<query>)`
linking to `…/actions/workflows/e2e-test.yml`. The `<query>` is per the
[[requirements]] open decision (recommended: `?branch=main`).

1.2. Keep the row a single line of three badges; preserve the existing two
verbatim (alt text + links).

## 2. README explanatory paragraph

2.1. Immediately below the badge row (or in a short "Continuous verification"
note near the top / under "Context — Why?"), add 2–4 sentences stating what the
e2e badge proves: each push to `main` and a daily schedule deploy **this**
module into a real disposable AWS account via keyless OIDC, write real Terraform
state through the module's assume-role, assert the state object + DynamoDB
digest exist, then destroy everything and leak-check.

2.2. State the honest limit in one clause: it is a lifecycle + no-leak signal,
not a guarantee of every module property; deep semantic checks are out of scope
(as the Phase 2 spec noted).

2.3. Link the words to the run history (the badge already links to the workflow;
the prose can point readers to the latest run).

## 3. Decision artifact

3.1. [[tech-stack]] §Gaps item 5 → done, naming the native badge and pointing to
`specs/2026-06-06-phase-4-module-works-badge/`.

3.2. Update the CI/CD note in [[tech-stack]] that currently says "the e2e
'module works' badge is Phase 4" to reflect it is now live.

3.3. [[roadmap]] Phase 4 → status marker done (badge live, links to runs).

## 4. Verify, record, hygiene

4.1. Render-check the README locally (markdown preview / `grep` the badge URL)
and confirm the badge image resolves to a green state for the chosen query
(we have green `main` runs, so `?branch=main` is green today).

4.2. Confirm the link target is the workflow page and the alt text is meaningful
for screen readers.

4.3. `./ci/tf-checks.sh` still passes (no `.tf` touched, but run it as the
standard gate) and the `tf-checks` / `terraform-security` workflows stay green
on the branch.

4.4. Walk [[validation]] top to bottom; open the PR to `main` linking this spec.

## Open questions to resolve during implementation

- **Badge query** — finalize `?branch=main` vs default vs `?event=schedule`
  (see [[requirements]] open decision).
- **Paragraph placement** — directly under the badge row vs a short subsection;
  pick whichever reads best without pushing the existing intro down too far.
- **Alt text wording** — "Module Works (e2e)" vs "E2E Module Test"; choose the
  clearest public-facing label.
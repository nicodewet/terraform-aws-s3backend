# Requirements — Phase 1: Secure GitHub Actions ↔ AWS (OIDC)

Resolves the gap "Secure GitHub Actions ↔ AWS integration (OIDC, no
long-lived keys)" in [[tech-stack]] §Gaps item 2. Aligned with [[mission]]
(Goal #1 — personal mastery of IAM least-privilege and CI/CD for IaC) and
[[roadmap]] Phase 1. Builds directly on Phase 0
(`specs/2026-05-23-phase-0-decide-ci-substrate/`), which established the
disposable account as the CI substrate and proved the module's lifecycle
runs there on short-lived local SSO creds.

## Going-in decisions

These are the positions this branch starts from. The spec PR is the place to
confirm or challenge them; nothing is implemented until the spec merges.

1. **Keyless OIDC, full stop.** GitHub Actions authenticates to the
   disposable account via GitHub's OIDC provider + `sts:AssumeRoleWithWebIdentity`.
   No IAM user, no access keys, nothing long-lived in the repo or in GitHub
   secrets. This is the entire point of the phase.

2. **Bootstrap is Terraform-in-repo, applied once by a human.** The OIDC
   provider and the CI role live in a small config under `ci/oidc-bootstrap/`,
   applied manually by the maintainer using their **SSO admin** session (the
   Phase 0 `s3backend-poc` profile) — *not* by CI.
   - *Why Terraform, not click-ops:* reproducible and reviewable (the trust
     policy and permissions are diffable in PRs), and it serves Goal #1
     (mastering the actual IAM objects). Phase 0's `auth-setup.md` was a
     human-only doc because it configured the operator's *workstation*; this
     configures *account infrastructure*, which deserves to be code.
   - *Why applied by a human, not CI:* avoids the chicken-and-egg of the CI
     role managing the CI role. A maintainer with admin applies it; CI only
     ever *assumes* the result.
   - *State:* the bootstrap uses **local state, gitignored** (it contains
     account/role ARNs). It is idempotent and changes rarely. We deliberately
     do **not** store bootstrap state in the very S3 backend this module
     builds — that is a worse chicken-and-egg.

3. **Trust policy is scoped tight, and fork PRs get nothing.** The role's
   trust policy restricts `aud` to `sts.amazonaws.com` and `sub` to this repo
   (`repo:nicodewet/terraform-aws-s3backend:*`), and is further limited to
   refs we control: `ref:refs/heads/main` and `ref:refs/tags/*`.
   - **Pull requests from forks must not be able to assume the role.** A fork
     PR running with AWS deploy/destroy creds is a credential-exfiltration
     hole. The smoke-test workflow (and, later, the Phase 2 e2e workflow) runs
     the AWS-touching job only on `push` to `main` / tags, or on same-repo
     branches — never on `pull_request` from a fork. This is a hard security
     constraint, not a preference.

4. **The CI role gets genuine least-privilege, scoped to what the module
   touches.** Not `AdministratorAccess`. The role needs create + read +
   delete on exactly the services the module provisions: KMS, S3, DynamoDB,
   IAM (role/policy/attachment), Resource Groups, plus `sts`.
   - The disposable-account boundary already bounds blast radius, so a broad
     policy would "work" — but Goal #1 is *mastering* least-privilege, so we
     do the real thing here. The boundary is the safety net, not the excuse.

## Scope

In scope for this branch (spec only) and the implementation branch that
follows:

1. `ci/oidc-bootstrap/` Terraform: the GitHub OIDC provider, the CI IAM role
   with the scoped trust policy, and the least-privilege permissions policy.
2. A one-time documented apply of the bootstrap against the disposable
   account, capturing the resulting role ARN (sanitized) for the workflow.
3. A **smoke-test** GitHub Actions workflow that authenticates via OIDC and
   runs `aws sts get-caller-identity` — proving keyless auth works end to end.
   Nothing more; no `terraform apply` of the module.
4. `oidc-setup.md` documenting the bootstrap, the apply, and how the workflow
   consumes the role (mirrors Phase 0's `auth-setup.md`).
5. Update [[tech-stack]] §Gaps item 2 status from open to decided/done with a
   pointer to this dir.

## Out of scope

- **The end-to-end module test** (apply → assert → destroy). That is Phase 2;
  the smoke test deliberately stops at `get-caller-identity`.
- **Scheduled / daily runs.** Phase 3.
- **README "module works" badge.** Phase 4.
- **Any change to the module itself** (`main.tf`, `iam.tf`, etc.). Phase 1 is
  CI auth plumbing only.
- **Migrating Phase 0's PoC** (`ci/poc-decide-ci-substrate.sh`) to OIDC. It
  stays a local-SSO tool; the CI path is the new workflow.

## Constraints

- **No long-lived credentials anywhere** — not in the repo, not in GitHub
  Actions secrets. OIDC tokens are minted per-run and expire.
- **Bootstrap state is never committed** (gitignored alongside the existing
  `*.tfstate` rules).
- **Least-privilege is a deliverable, not a TODO.** If the role ends up with
  a wildcard service action, justify it in the PR.
- **Fork-PR isolation is mandatory** (see going-in decision 3).
- **Keep it minimal.** Bootstrap config + one workflow + one doc. No new
  framework, no reusable-action authoring.

## Context

- Resolves: [[tech-stack]] §Gaps item 2.
- Predecessor: `specs/2026-05-23-phase-0-decide-ci-substrate/` (substrate +
  lifecycle PoC) and its `auth-setup.md` (local SSO).
- Mission ordering: [[mission]] §Ordered Goals (Goal #1 drives the
  least-privilege call).
- Disposable account: the same AWS Organizations sub-account used in Phase 0.
- Reference: GitHub OIDC for AWS —
  `https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services`.
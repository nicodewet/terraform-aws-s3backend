# Mission

## Purpose

Build and maintain a production-ready Terraform module that provisions an AWS
S3 backend (S3 + KMS + DynamoDB + least-privileged IAM) for Terraform remote
state, published as `nicodewet/s3backend/aws` on the Terraform Registry.

## Ordered Goals

When goals conflict, resolve in this order:

1. **Personal mastery.** This project exists first so the maintainer learns
   and masters the guardrails (encryption at rest, state locking, IAM
   least-privilege, CI/CD for IaC, security scanning) that are normally
   handed to professional engineers pre-built. Decisions that maximize
   learning beat decisions that maximize convenience.
2. **Production-ready public module.** Strangers pulling the module from the
   Terraform Registry should be able to depend on it. That means semantic
   versioning, working examples, security scans on every change, and a
   visible signal that the module actually deploys end-to-end.
3. **Reference / teaching artifact.** The README and exercises adapt
   *Terraform in Action* (ch. 6) to current provider versions and document
   the "why" behind each component. Future readers should be able to learn
   from this repo, not just consume the module.

## Target Audience

Primary: **small teams (2–10 people) sharing Terraform state** and
**public Terraform Registry consumers** pulling the module into their own
projects. The `namespace` variable is designed around the team-name use case;
solo learners (using their own name as namespace) are supported but are not
the design center.

Out of scope: large-enterprise multi-account topologies, organizations that
need their own opinionated wrappers, and consumers who want non-AWS backends.

## Non-Goals

- Becoming a generic remote-state abstraction across cloud providers.
- Replacing managed offerings (Terraform Cloud, Spacelift, env0).
- Backwards-compatibility shims for pre-1.0 callers — semantic versioning is
  the contract, breaking changes ship in a new major.

## Success Signals

- The module deploys cleanly into a disposable AWS account from CI on every
  change and on a daily schedule, and tears down without leaks.
- A passing "module works" badge in the README that the public can trust.
- Security scans (Checkov, [[tech-stack]]) stay green at `HIGH` severity.
- A new small team can `terraform init` against the module using only the
  README within 30 minutes.

## Stakeholder

Nico de Wet (maintainer). All design calls route through him until the
module reaches a stable 1.x.
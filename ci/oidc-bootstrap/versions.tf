# Phase-1 OIDC bootstrap — spec: specs/2026-06-01-phase-1-secure-aws-oidc/
#
# This is a standalone ROOT module, applied ONCE by the maintainer with the
# SSO admin session (profile s3backend-poc) — never by CI. It provisions the
# account-level infrastructure that lets GitHub Actions authenticate keylessly:
# the GitHub OIDC provider and a scoped, least-privilege CI role. CI only ever
# *assumes* the role created here; it never manages this config.
#
# State is LOCAL and gitignored (it holds account/role ARNs). Idempotent and
# rarely changed. Deliberately NOT stored in the S3 backend this module builds.

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.64"
    }
  }
}

# Phase-2 e2e fixture — STEP A (deploy the backend).
#
# Instantiates THIS repo's module via a relative source so the e2e test gates
# local code, not the published registry version. The provider is declared here
# (the module deliberately does not embed one — see ../../../versions.tf) so it
# honours the ambient credentials: the OIDC session in CI, or the Phase 0 SSO
# session locally. No profile is hard-coded for the same reason.
#
# Driven by ../../s3backend_e2e_test.go; not meant to be run by hand.

provider "aws" {
  region = "ap-southeast-2"
}

module "s3backend" {
  source    = "../../../"
  namespace = "e2e"
}

# Single map output consumed by the Terratest harness (bucket / dynamodb_table /
# region / role_arn) and fed into STEP B as -backend-config flags.
output "s3backend_config" {
  value = module.s3backend.config
}
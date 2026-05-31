# Phase-0 PoC fixture — STEP A (deploy).
#
# Deploys THIS repo's module via a relative source so the CI-substrate PoC
# gates local code, not the published registry version. The provider is
# declared here (the module no longer embeds one) so it honours AWS_PROFILE /
# AWS_REGION from the environment — i.e. the short-lived SSO session.
#
# Driven by ../../poc-decide-ci-substrate.sh; not meant to be run by hand.

provider "aws" {
  region = "ap-southeast-2"
}

module "s3backend" {
  source    = "../../../"
  namespace = "poc-ci"
}

# Single map output consumed by the PoC script (bucket / dynamodb_table /
# region / role_arn) and fed into STEP B as -backend-config flags.
output "s3backend_config" {
  value = module.s3backend.config
}
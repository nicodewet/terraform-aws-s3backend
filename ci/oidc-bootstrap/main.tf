provider "aws" {
  region = var.aws_region
  # No profile hard-coded (the Phase 0 lesson): the operator supplies creds via
  # AWS_PROFILE=s3backend-poc / AWS_REGION when applying this once by hand.
}

data "aws_caller_identity" "current" {}

# GitHub's OIDC identity provider in the CI account. GitHub Actions presents a
# signed OIDC token to AWS STS; this resource is what AWS trusts to verify it.
#
# thumbprint_list is intentionally NOT set: AWS now secures the GitHub OIDC
# endpoints using its library of trusted root CAs, so the thumbprint is no
# longer used to validate tokens. The aws provider (~> 5.64) treats it as
# optional + computed, so AWS auto-populates the current value and Terraform
# shows no drift. (Resolves the open question in the spec's plan.md — verified
# on apply: AWS populated a thumbprint on its own with this attribute omitted.)
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = {
    ManagedBy = "ci/oidc-bootstrap"
    Purpose   = "github-actions-oidc"
  }
}
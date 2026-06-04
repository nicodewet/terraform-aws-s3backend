# Phase-2 e2e fixture — STEP B (consume the backend produced by ../deploy).
#
# Backend attributes (bucket / region / dynamodb_table / assume_role) are
# supplied at init time via -backend-config flags (partial configuration) by the
# Terratest harness. Only the static key + encrypt live here: Terraform backend
# blocks cannot reference variables, so the dynamic values must come in at init.
# Note: Terraform >= 1.6 supplies the role via an `assume_role` block, not a
# top-level `role_arn` argument.

terraform {
  backend "s3" {
    key     = "team1/my-cool-project"
    encrypt = true
  }
  required_version = ">= 0.15"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# A no-infrastructure resource whose apply forces Terraform to write state to the
# S3 backend (and take a DynamoDB lock). Applying it proves the freshly created
# backend accepts a real read/write/lock cycle via the assumed role, and leaves
# behind the persistent digest item the test asserts on (THEN-2).
resource "null_resource" "state_marker" {
  triggers = {
    always = timestamp()
  }
  provisioner "local-exec" {
    command = "echo 'e2e: terraform state written to the s3 backend'"
  }
}
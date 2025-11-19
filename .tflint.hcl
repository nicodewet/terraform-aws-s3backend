# TFLint configuration for this AWS Terraform module

# ------------------------------------------------------------------------------
# AWS ruleset plugin
#
# Please see the rules that are enabled by default here:
#
# https://github.com/terraform-linters/tflint-ruleset-aws/tree/master/docs/rules
#
# Expressly disabling deep_check to show there has been thought in this regard.
#
# -------------------------------------------------------------------------------
# Enables AWS-specific checks. Version pinned so CI stays stable.
plugin "aws" {
    enabled = true
    deep_check = false
    version = "0.44.0"
    source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
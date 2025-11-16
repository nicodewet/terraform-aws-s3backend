#!/usr/bin/env bash

# -------------------------------------------------------------------
# Terraform version + format check
#
# This script does the following:
# 1) Ensures Terraform version is exactly 1.13.5
# 2) Checks that all Terraform files (*.tf) are properly formatted
#
# Safe to run locally or in CI.
# -------------------------------------------------------------------

# -------------------------------------------------------------------
# Bash safety flags
# -------------------------------------------------------------------
# set -e          : exit immediately if any command fails
# set -u          : treat unset variables as an error
# set -o pipefail : if any command in a pipeline fails, the pipeline fails
set -euo pipefail

# -------------------------------------------------------------------
# 1) Terraform version check
# -------------------------------------------------------------------
REQUIRED_TF_VERSION="1.13.5"

# Check if Terraform is installed in PATH
if ! command -v terraform >/dev/null 2>&1; then
  echo "❌ Terraform not installed. Please install Terraform $REQUIRED_TF_VERSION."
  exit 1
fi

# Extract the installed Terraform version using the JSON output
# `terraform version -json` produces JSON containing "terraform_version"
# `jq -r '.terraform_version'` extracts the version string
CURRENT_TF_VERSION=$(terraform version -json | jq -r '.terraform_version')

# Compare installed version to the required version
if [ "$CURRENT_TF_VERSION" != "$REQUIRED_TF_VERSION" ]; then
  echo "❌ Terraform version mismatch:"
  echo "   Required: $REQUIRED_TF_VERSION"
  echo "   Found   : $CURRENT_TF_VERSION"
  echo "   Please install the correct version."
  exit 1
fi

# Success message if version matches
echo "✅ Terraform version $CURRENT_TF_VERSION is correct."
echo

# -------------------------------------------------------------------
# 2) Terraform format check
# -------------------------------------------------------------------
echo "Running Terraform fmt check recursively from top level..."
echo

# `terraform fmt -check -recursive`
# - checks formatting of all Terraform files (*.tf) under current directory
# - -check     : returns non-zero exit code if formatting is incorrect, does not modify files
# - -recursive : checks all subdirectories
if ! terraform fmt -check -recursive; then
  echo
  echo "❌ Terraform fmt check failed."
  echo "   Run 'terraform fmt -recursive' to automatically fix formatting."
  exit 1
fi

# Success message if formatting passes
echo
echo "✅ All Terraform files are properly formatted."

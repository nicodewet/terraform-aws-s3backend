output "ci_role_arn" {
  description = "ARN of the CI role GitHub Actions assumes via OIDC. Feed this to the smoke-test workflow's role-to-assume (it is not a secret; redact the account ID in committed docs per the Phase 0 convention)."
  value       = aws_iam_role.ci.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider in this account."
  value       = aws_iam_openid_connect_provider.github.arn
}
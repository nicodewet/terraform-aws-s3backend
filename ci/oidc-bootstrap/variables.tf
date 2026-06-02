variable "aws_region" {
  description = "Region for the CI account. Matches the Phase 0 substrate."
  type        = string
  default     = "ap-southeast-2"
}

variable "github_org" {
  description = "GitHub org/user that owns the repo allowed to assume the CI role."
  type        = string
  default     = "nicodewet"
}

variable "github_repo" {
  description = "Repository allowed to assume the CI role (without the org prefix)."
  type        = string
  default     = "terraform-aws-s3backend"
}

variable "allowed_subs" {
  description = <<-EOT
    OIDC `sub` claims allowed to assume the CI role. Scoped tight on purpose:
    only the default branch and tags — NOT a bare `repo:<org>/<repo>:*`, which
    would let any fork pull-request branch in. Fork-PR isolation is a hard
    security constraint (see the spec's requirements §going-in decision 3).
  EOT
  type        = list(string)
  default     = ["ref:refs/heads/main", "ref:refs/tags/*"]
}

variable "ci_role_name" {
  description = "Name of the CI role GitHub Actions assumes via OIDC."
  type        = string
  default     = "s3backend-ci"
}

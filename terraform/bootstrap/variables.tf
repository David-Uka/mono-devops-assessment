variable "project" {
  description = "Short project slug used as a prefix for every resource"
  type        = string
  default     = "mono-api"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the CI roles, as owner/name"
  type        = string
}

variable "github_owner_id" {
  description = "Numeric GitHub owner ID, for immutable OIDC subjects (gh api users/<owner> --jq .id)"
  type        = number
  default     = null
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID, for immutable OIDC subjects (gh api repos/<owner>/<name> --jq .id)"
  type        = number
  default     = null
}

variable "deploy_environment" {
  description = "GitHub environment the deploy job runs under"
  type        = string
  default     = "prod"
}

variable "default_branch" {
  type    = string
  default = "main"
}

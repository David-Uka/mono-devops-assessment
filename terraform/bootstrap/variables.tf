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

variable "default_branch" {
  type    = string
  default = "main"
}

locals {
  cluster_name = "${var.project}-${var.environment}"
  tls_enabled  = var.domain_name != "" && var.acm_certificate_arn != ""
  image_name   = "${data.aws_ecr_repository.api.repository_url}:${var.image_tag}"
}

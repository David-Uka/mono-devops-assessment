output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_version" {
  value = module.eks.cluster_version
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "alb_controller_role_arn" {
  value = module.alb_controller_irsa.arn
}

output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.api.arn
}

output "alb_logs_bucket" {
  value = aws_s3_bucket.alb_logs.bucket
}

output "acm_certificate_arn" {
  value = local.tls_enabled ? aws_acm_certificate_validation.api[0].certificate_arn : ""
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "image" {
  value = local.image_name
}

output "alb_hostname" {
  value = data.aws_lb.api.dns_name
}

output "api_url" {
  value = local.tls_enabled ? "https://${var.domain_name}" : "http://${data.aws_lb.api.dns_name}"
}

output "grafana_port_forward" {
  value = var.enable_monitoring ? "kubectl -n ${var.monitoring_namespace} port-forward svc/kube-prometheus-stack-grafana 3001:80" : ""
}

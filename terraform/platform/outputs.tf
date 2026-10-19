output "image" {
  value = local.image_name
}

output "alb_hostname" {
  value = try(data.kubernetes_ingress_v1.api.status[0].load_balancer[0].ingress[0].hostname, "")
}

output "api_url" {
  value = var.domain_name != "" ? "https://${var.domain_name}" : "http://${try(data.kubernetes_ingress_v1.api.status[0].load_balancer[0].ingress[0].hostname, "<pending>")}"
}

output "grafana_port_forward" {
  value = var.enable_monitoring ? "kubectl -n ${var.monitoring_namespace} port-forward svc/kube-prometheus-stack-grafana 3001:80" : ""
}

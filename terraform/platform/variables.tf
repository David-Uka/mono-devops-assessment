variable "project" {
  type    = string
  default = "mono-api"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "image_tag" {
  description = "Tag for the image built from the repo root (CI passes the git sha)"
  type        = string
}

variable "source_path" {
  description = "Docker build context (the repo root)"
  type        = string
  default     = "../.."
}

variable "app_namespace" {
  type    = string
  default = "api"
}

variable "monitoring_namespace" {
  type    = string
  default = "monitoring"
}

variable "enable_monitoring" {
  description = "Install kube-prometheus-stack (Prometheus + Grafana) and the ServiceMonitor"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Must match the infra stack. Empty => plain HTTP on the ALB DNS name."
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "Certificate for the ALB listener when domain_name is set (infra output)"
  type        = string
  default     = ""
}

variable "alb_controller_chart_version" {
  type    = string
  default = "3.6.0"
}

variable "kube_prometheus_stack_version" {
  type    = string
  default = "92.10.1"
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Not exposed publicly; reach it via port-forward."
  type        = string
  sensitive   = true
  default     = ""
}

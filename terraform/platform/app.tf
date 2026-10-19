resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.app_namespace
    labels = {
      # Pod Security Admission: nothing privileged gets in
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

locals {
  # Fixed-response action: the ALB answers /metrics itself with 403 so the
  # Prometheus endpoint never leaves the VPC. In-cluster scraping is unaffected.
  metrics_deny_action = jsonencode({
    type = "fixed-response"
    fixedResponseConfig = {
      contentType = "application/json"
      statusCode  = "403"
      messageBody = "{\"error\":\"forbidden\"}"
    }
  })

  ingress_annotations = merge(
    {
      "alb.ingress.kubernetes.io/scheme"                       = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"                  = "ip"
      "alb.ingress.kubernetes.io/healthcheck-path"             = "/health"
      "alb.ingress.kubernetes.io/healthcheck-interval-seconds" = "15"
      "alb.ingress.kubernetes.io/success-codes"                = "200"
      "alb.ingress.kubernetes.io/wafv2-acl-arn"                = data.aws_wafv2_web_acl.api.arn
      "alb.ingress.kubernetes.io/load-balancer-attributes" = join(",", [
        "access_logs.s3.enabled=true",
        "access_logs.s3.bucket=${data.aws_s3_bucket.alb_logs.bucket}",
        "access_logs.s3.prefix=api",
        "idle_timeout.timeout_seconds=60",
        "routing.http.drop_invalid_header_fields.enabled=true",
        "deletion_protection.enabled=false",
      ])
      "alb.ingress.kubernetes.io/actions.metrics-deny" = local.metrics_deny_action
      "alb.ingress.kubernetes.io/group.name"           = local.cluster_name
    },
    local.tls_enabled ? {
      "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/certificate-arn" = var.acm_certificate_arn
      "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
      "alb.ingress.kubernetes.io/ssl-policy"      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      } : {
      "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\":80}]"
    }
  )
}

resource "helm_release" "api" {
  name      = "api"
  chart     = "${path.module}/../../charts/api"
  namespace = kubernetes_namespace_v1.app.metadata[0].name

  values = [yamlencode({
    image = {
      repository = data.aws_ecr_repository.api.repository_url
      tag        = var.image_tag
    }
    ingress = {
      enabled           = true
      className         = "alb"
      annotations       = local.ingress_annotations
      hosts             = var.domain_name != "" ? [var.domain_name] : []
      denyMetricsAtEdge = true
    }
    metrics = {
      serviceMonitor = {
        enabled = var.enable_monitoring
        labels  = { release = "kube-prometheus-stack" }
      }
    }
    networkPolicy = {
      monitoringNamespace = var.monitoring_namespace
    }
  })]

  wait    = true
  timeout = 600

  depends_on = [
    docker_registry_image.api,
    helm_release.alb_controller,
    helm_release.kube_prometheus_stack,
  ]
}

# Resolve the ALB hostname the controller provisioned, for the smoke test.
data "kubernetes_ingress_v1" "api" {
  metadata {
    name      = "api"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  depends_on = [helm_release.api]
}

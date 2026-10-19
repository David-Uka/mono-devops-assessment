# Bonus 1 + 3: Prometheus scrapes /metrics in-cluster; Grafana renders the
# RED dashboard committed at dashboards/api-red.json.
resource "kubernetes_namespace_v1" "monitoring" {
  count = var.enable_monitoring ? 1 : 0
  metadata {
    name = var.monitoring_namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  count      = var.enable_monitoring ? 1 : 0
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_version
  namespace  = kubernetes_namespace_v1.monitoring[0].metadata[0].name

  values = [yamlencode({
    # Small footprint for a 2-node cluster
    alertmanager = { enabled = false }
    prometheus = {
      prometheusSpec = {
        retention = "7d"
        resources = {
          requests = { cpu = "200m", memory = "512Mi" }
          limits   = { memory = "1Gi" }
        }
        # Pick up every ServiceMonitor in the cluster, not only the chart's own
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
      }
    }
    grafana = {
      adminPassword = var.grafana_admin_password != "" ? var.grafana_admin_password : null
      # Internal only. Reach it with:
      #   kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3001:80
      service = { type = "ClusterIP" }
      sidecar = {
        dashboards = {
          enabled         = true
          label           = "grafana_dashboard"
          labelValue      = "1"
          searchNamespace = "ALL"
        }
      }
    }
    # Not useful on EKS (control plane is managed, these endpoints are hidden)
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = false }
  })]

  wait    = true
  timeout = 900
}

# The dashboard JSON lives in git; the sidecar loads it from this ConfigMap.
resource "kubernetes_config_map_v1" "api_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  metadata {
    name      = "api-red-dashboard"
    namespace = kubernetes_namespace_v1.monitoring[0].metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = {
    "api-red.json" = file("${path.module}/../../dashboards/api-red.json")
  }
}

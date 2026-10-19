# AWS Load Balancer Controller: turns Ingress objects into ALBs.
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version
  namespace  = "kube-system"

  set = [
    { name = "clusterName", value = local.cluster_name },
    { name = "region", value = var.region },
    { name = "vpcId", value = data.aws_eks_cluster.this.vpc_config[0].vpc_id },
    { name = "serviceAccount.create", value = "true" },
    { name = "serviceAccount.name", value = "aws-load-balancer-controller" },
    { name = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn", value = data.aws_iam_role.alb_controller.arn },
    { name = "replicaCount", value = "2" },
    { name = "enableShield", value = "false" },
    { name = "enableWaf", value = "false" },
    { name = "enableWafv2", value = "true" },
  ]

  wait    = true
  timeout = 600
}

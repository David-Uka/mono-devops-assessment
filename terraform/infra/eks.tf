module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # API endpoint: private always on, public restricted to an allow-list
  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # Control-plane audit trail to CloudWatch
  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = 30

  # Envelope-encrypt Kubernetes Secrets with our CMK
  encryption_config = {
    provider_key_arn = aws_kms_key.main.arn
    resources        = ["secrets"]
  }
  create_kms_key = false

  # The identity running terraform gets cluster-admin via access entries
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  # Managed add-ons; versions resolved to the latest compatible with the cluster
  addons = {
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    vpc-cni                = { most_recent = true, before_compute = true }
    eks-pod-identity-agent = { most_recent = true, before_compute = true }
    metrics-server         = { most_recent = true }
  }

  eks_managed_node_groups = {
    general = {
      name           = "${local.name}-general"
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      # Nodes live in private subnets; no public IPs
      subnet_ids = module.vpc.private_subnets

      # Enforce IMDSv2 so a pod cannot steal the node role via 169.254.169.254
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 30
            volume_type           = "gp3"
            encrypted             = true
            kms_key_id            = aws_kms_key.main.arn
            delete_on_termination = true
          }
        }
      }

      update_config = {
        max_unavailable_percentage = 33
      }

      labels = {
        workload = "general"
      }
    }
  }

  tags = {
    # Lets Karpenter / cluster-autoscaler discover the cluster later
    "karpenter.sh/discovery" = local.name
  }
}

# Allow nodes to reach the cluster endpoint and each other (module handles the
# standard set). Extra rule: ALB -> pods on the app port via the node SG.
resource "aws_security_group_rule" "alb_to_nodes" {
  type              = "ingress"
  description       = "ALB (in VPC) to pods on the app port"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = module.eks.node_security_group_id
}

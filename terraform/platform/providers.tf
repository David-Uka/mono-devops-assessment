provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "platform"
    }
  }
}

# --- Read what the infra stack created (by name, no remote-state coupling) ---
data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

data "aws_ecr_repository" "api" {
  name = "${var.project}/api"
}

data "aws_ecr_authorization_token" "this" {}

data "aws_iam_role" "alb_controller" {
  name = "${local.cluster_name}-alb-controller"
}

data "aws_wafv2_web_acl" "api" {
  name  = "${local.cluster_name}-api"
  scope = "REGIONAL"
}

data "aws_s3_bucket" "alb_logs" {
  bucket = "${local.cluster_name}-alb-logs-${data.aws_caller_identity.current.account_id}"
}

# --- Cluster access via short-lived tokens from the caller's AWS identity ---
locals {
  k8s_exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.region]
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  exec {
    api_version = local.k8s_exec.api_version
    command     = local.k8s_exec.command
    args        = local.k8s_exec.args
  }
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec                   = local.k8s_exec
  }
}

# --- Docker: build locally (or on the CI runner), push to ECR ---
provider "docker" {
  registry_auth {
    address  = data.aws_ecr_authorization_token.this.proxy_endpoint
    username = data.aws_ecr_authorization_token.this.user_name
    password = data.aws_ecr_authorization_token.this.password
  }
}

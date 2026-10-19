module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway
  enable_dns_hostnames   = true
  enable_dns_support     = true

  # VPC flow logs to CloudWatch for audit / forensics (ISO 27001 A.8.15, PCI DSS 10)
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_iam_role             = true
  create_flow_log_cloudwatch_log_group            = true
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = 30
  # Names must fall inside the deploy role's mono-api-* IAM scope
  vpc_flow_log_iam_role_name              = "${local.name}-flow-log"
  vpc_flow_log_iam_role_use_name_prefix   = false
  vpc_flow_log_iam_policy_name            = "${local.name}-flow-log"
  vpc_flow_log_iam_policy_use_name_prefix = false

  # Subnet discovery tags for the AWS Load Balancer Controller
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

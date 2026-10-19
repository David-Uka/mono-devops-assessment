variable "project" {
  description = "Short project slug used as a prefix for every resource"
  type        = string
  default     = "mono-api"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "az_count" {
  description = "Number of AZs to spread subnets and nodes across (>= 2 for HA)"
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "One NAT gateway for all AZs (cheaper) vs one per AZ (HA egress)"
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS API endpoint. Narrow this to office / CI egress IPs."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "additional_cluster_admin_arns" {
  description = "IAM principal ARNs granted cluster-admin via access entries (e.g. your own user when CI created the cluster)"
  type        = list(string)
  default     = []
}

variable "waf_rate_limit_per_5min" {
  description = "Requests per source IP per 5 minutes before WAF starts blocking"
  type        = number
  default     = 2000
}

variable "domain_name" {
  description = "Optional public hostname for the API. Leave empty to use the ALB DNS name over plain HTTP."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Hosted zone that owns domain_name (needed for ACM DNS validation). Ignored when domain_name is empty."
  type        = string
  default     = ""
}

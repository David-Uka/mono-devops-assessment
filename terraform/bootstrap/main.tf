# ---------------------------------------------------------------------------
# Bootstrap stack - applied ONCE by a human with local credentials.
# Creates the remote state bucket and the GitHub Actions OIDC trust so that
# every later apply happens from CI with short-lived credentials, not keys.
# ---------------------------------------------------------------------------
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

# --- Remote state ----------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "state_tls_only" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# --- GitHub OIDC -----------------------------------------------------------
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# GitHub can issue "immutable" subject claims that embed the owner and repo
# IDs (repo:owner@<id>/name@<id>:...), which survive renames and cannot be
# hijacked by re-creating a deleted repo. Trust both spellings so the roles
# work whichever mode the repo is in; look the IDs up with
#   gh api repos/<owner>/<name> --jq '"\(.owner.id) \(.id)"'
locals {
  repo_owner = split("/", var.github_repo)[0]
  repo_name  = split("/", var.github_repo)[1]
  sub_prefixes = compact([
    "repo:${var.github_repo}",
    var.github_owner_id != null && var.github_repo_id != null
    ? "repo:${local.repo_owner}@${var.github_owner_id}/${local.repo_name}@${var.github_repo_id}"
    : "",
  ])
  # A job that targets a GitHub environment gets `environment:<name>` as its
  # subject instead of the branch ref, so the deploy role must trust both.
  oidc_sub_main = concat(
    [for p in local.sub_prefixes : "${p}:ref:refs/heads/${var.default_branch}"],
    [for p in local.sub_prefixes : "${p}:environment:${var.deploy_environment}"],
  )
  oidc_sub_pr = [for p in local.sub_prefixes : "${p}:pull_request"]
}

# Role used by `terraform plan` on pull requests: read-only plus state access.
data "aws_iam_policy_document" "gha_plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = concat(local.oidc_sub_pr, local.oidc_sub_main)
    }
  }
}

# Role used by `terraform apply` - ONLY from the default branch / prod environment.
# The `prod` environment itself is restricted to the default branch in GitHub.
data "aws_iam_policy_document" "gha_deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.oidc_sub_main
    }
  }
}

data "aws_iam_policy_document" "state_access" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "state_access" {
  name   = "${var.project}-tfstate-access"
  policy = data.aws_iam_policy_document.state_access.json
}

resource "aws_iam_role" "gha_plan" {
  name                 = "${var.project}-gha-plan"
  assume_role_policy   = data.aws_iam_policy_document.gha_plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "gha_plan_readonly" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "gha_plan_state" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = aws_iam_policy.state_access.arn
}

# Deploy role: PowerUser (no IAM) + a tightly scoped IAM grant limited to
# resources carrying the project prefix, so Terraform can create the EKS
# node/cluster/IRSA roles but cannot touch anything else in the account.
data "aws_iam_policy_document" "gha_deploy_iam" {
  statement {
    sid = "ScopedIamForProjectRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:TagRole", "iam:UntagRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:GetRolePolicy", "iam:UpdateAssumeRolePolicy", "iam:ListInstanceProfilesForRole",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion",
      "iam:ListPolicyVersions", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:TagPolicy",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.project}-*",
    ]
  }
  statement {
    sid       = "PassProjectRolesToServices"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["eks.amazonaws.com", "ec2.amazonaws.com", "pods.eks.amazonaws.com", "vpc-flow-logs.amazonaws.com"]
    }
  }
  statement {
    sid       = "ReadOidcAndServiceLinkedRoles"
    actions   = ["iam:GetOpenIDConnectProvider", "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider", "iam:TagOpenIDConnectProvider", "iam:CreateServiceLinkedRole", "iam:ListPolicies", "iam:ListRoles"]
    resources = ["*"]
  }
  statement {
    # EKS, Auto Scaling and ELB check for their service-linked roles before
    # creating resources; that lookup needs GetRole on the SLR path.
    sid       = "ReadServiceLinkedRoles"
    actions   = ["iam:GetRole", "iam:ListAttachedRolePolicies"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*"]
  }
}

resource "aws_iam_policy" "gha_deploy_iam" {
  name   = "${var.project}-gha-deploy-iam"
  policy = data.aws_iam_policy_document.gha_deploy_iam.json
}

resource "aws_iam_role" "gha_deploy" {
  name                 = "${var.project}-gha-deploy"
  assume_role_policy   = data.aws_iam_policy_document.gha_deploy_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "gha_deploy_poweruser" {
  role       = aws_iam_role.gha_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy_attachment" "gha_deploy_iam" {
  role       = aws_iam_role.gha_deploy.name
  policy_arn = aws_iam_policy.gha_deploy_iam.arn
}

resource "aws_iam_role_policy_attachment" "gha_deploy_state" {
  role       = aws_iam_role.gha_deploy.name
  policy_arn = aws_iam_policy.state_access.arn
}

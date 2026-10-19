# One CMK for the project: EKS secrets envelope encryption, ECR images, logs.
resource "aws_kms_key" "main" {
  description             = "${local.name} encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.main.key_id
}

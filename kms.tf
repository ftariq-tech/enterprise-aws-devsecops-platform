# Independent customer-managed keys for CloudWatch Logs, DynamoDB and ECR.
# Additional KMS key charges apply if deployed. Keep keys enabled while encrypted
# content is needed. Verify IAM grant permissions before a real AWS deployment.

data "aws_partition" "current" {}

data "aws_iam_policy_document" "logs_kms" {
  statement {
    sid       = "EnableAccountIAMPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowRegionalCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
      "kms:GenerateDataKey*", "kms:Describe*"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.project_name}/*"
      ]
    }
  }
}

resource "aws_kms_key" "logs" {
  description             = "CloudWatch Logs encryption for ${var.project_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.logs_kms.json
  tags                    = local.tags
}

resource "aws_kms_key" "dynamodb" {
  description             = "DynamoDB encryption for ${var.project_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = local.tags
}

resource "aws_kms_key" "ecr" {
  description             = "ECR repository encryption for ${var.project_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = local.tags
}

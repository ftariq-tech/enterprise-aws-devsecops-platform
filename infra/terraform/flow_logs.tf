# Enable VPC-level traffic metadata logging. It does not capture application payloads.
# CloudWatch ingestion, 365-day retention and KMS use can incur charges.
resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/vpc/${var.project_name}/flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.logs.arn
  tags              = local.tags
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.project_name}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project_name}-vpc-logging"
  role = aws_iam_role.flow_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteToConfiguredVpcLogGroup"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = [
        aws_cloudwatch_log_group.vpc_flow.arn,
        "${aws_cloudwatch_log_group.vpc_flow.arn}:log-stream:*"
      ]
    }]
  })
}

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.main.id
  log_destination      = aws_cloudwatch_log_group.vpc_flow.arn
  log_destination_type = "cloud-watch-logs"
  iam_role_arn         = aws_iam_role.flow_logs.arn
  traffic_type         = "ALL"
  tags                 = local.tags
  depends_on           = [aws_iam_role_policy.flow_logs]
}

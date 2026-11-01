resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }
  tags = local.tags
}
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep latest 15 images"
      selection = {
        tagStatus = "any", countType = "imageCountMoreThan", countNumber = 15
      }
      action = {
        type = "expire"
      }
    }]
  })
}
resource "aws_sqs_queue" "dead_letter" {
  name                       = "${var.project_name}-dlq"
  message_retention_seconds  = 1209600
  sqs_managed_sse_enabled    = true
  tags                       = local.tags
}
resource "aws_sqs_queue" "orders" {
  name                      = "${var.project_name}-orders"
  visibility_timeout_seconds = 60
  receive_wait_time_seconds = 15
  sqs_managed_sse_enabled   = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter.arn
    maxReceiveCount     = 5
  })
  tags = local.tags
}
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dead_letter.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.orders.arn]
  })
}
resource "aws_dynamodb_table" "orders" {
  name         = "${var.project_name}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"
  attribute {
    name = "order_id"
    type = "S"
  }
  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }
  tags = local.tags
}
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.project_name}/api"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.logs.arn
  tags = local.tags
}
resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${var.project_name}/worker"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.logs.arn
  tags = local.tags
}
resource "aws_cloudwatch_metric_alarm" "dlq_visible" {
  alarm_name          = "${var.project_name}-dlq-visible"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  dimensions = {
    QueueName = aws_sqs_queue.dead_letter.name
  }
  tags = local.tags
  # No notification destination is created; connect SNS/notifications before real use.
}

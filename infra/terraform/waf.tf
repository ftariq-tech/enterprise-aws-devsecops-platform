# Protect the public-facing ALB only when the optional runtime is enabled.
# WAF ACL, requests and managed rule groups can incur charges.
resource "aws_wafv2_web_acl" "api" {
  count = var.enable_runtime ? 1 : 0

  name  = "${var.project_name}-api-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # Example rate limiter. Tune limits using traffic patterns before production.
  rule {
    name     = "rate-limit-per-ip"
    priority = 1
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }


  # AWS managed protection for malicious input patterns, including Log4j signatures.
  # Review false-positive metrics before enabling in live traffic.
  rule {
    name     = "known-bad-inputs"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-api-waf"
    sampled_requests_enabled   = true
  }

  tags = local.tags
}

resource "aws_wafv2_web_acl_association" "api" {
  count        = var.enable_runtime ? 1 : 0
  resource_arn = aws_lb.api[0].arn
  web_acl_arn  = aws_wafv2_web_acl.api[0].arn
}

# Logging is separately configured from WAF metrics. Keep logs in CloudWatch
# for security review; these resources incur charges if runtime is enabled.
resource "aws_cloudwatch_log_group" "waf" {
  count             = var.enable_runtime ? 1 : 0
  name              = "aws-waf-logs-${var.project_name}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.logs.arn
  tags              = local.tags
}

resource "aws_wafv2_web_acl_logging_configuration" "api" {
  count                   = var.enable_runtime ? 1 : 0
  resource_arn            = aws_wafv2_web_acl.api[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]

  # Avoid recording credentials in WAF request logs.
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}

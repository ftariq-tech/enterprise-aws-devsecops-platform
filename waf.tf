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

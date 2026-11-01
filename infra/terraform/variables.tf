variable "aws_region" {
  type = string
  default = "us-east-1"
}
variable "project_name" {
  type = string
  default = "orders-devsecops-demo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{3,24}$", var.project_name))
    error_message = "Use 4–25 lowercase letters, numbers and hyphens; start with a letter."
  }
}
variable "vpc_cidr" {
  type = string
  default = "10.42.0.0/16"
}
variable "enable_runtime" {
  type = bool
  default = false
  description = "Default false: create core AWS resources, NOT load balancer or ECS services. Charges still apply to NAT/ECR/etc."
}
variable "acm_certificate_arn" {
  type = string
  default = ""
  description = "Required for HTTPS ALB if enable_runtime=true. Must match listener region."
}
variable "api_token_secret_arn" {
  type = string
  default = ""
  description = "Existing Secrets Manager secret ARN holding ORDERS_API_TOKEN. No secret values in Terraform."
}
variable "image_tag" {
  type = string
  default = "bootstrap"
  description = "Immutable ECR image tag built before enable_runtime=true."
}
variable "github_repository" {
  type = string
  default = "ftariq-tech/enterprise-aws-devsecops-platform"
  description = "Exact owner/repo allowed to assume optional GitHub OIDC role."
}
variable "create_github_oidc_provider" {
  type = bool
  default = false
  description = "True only when no GitHub OIDC provider already exists in this AWS account."
}
variable "enable_github_deploy_role" {
  type = bool
  default = false
  description = "Provision optional narrowly scoped GitHub Actions deployment role."
}
variable "api_desired_count" {
  type = number
  default = 1
}
variable "worker_desired_count" {
  type = number
  default = 1
}
locals {
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
  tags = {
    Project = var.project_name, Environment = "portfolio-demo", ManagedBy = "Terraform"
  }
  subnet_map = {
    for index, az in local.azs : tostring(index) => {
      az      = az
      public  = cidrsubnet(var.vpc_cidr, 8, index)
      private = cidrsubnet(var.vpc_cidr, 8, index + 10)
    }
  }
}
resource "terraform_data" "runtime_guard" {
  count = var.enable_runtime ? 1 : 0
  lifecycle {
    precondition {
      condition = startswith(var.acm_certificate_arn, "arn:aws:acm:") && startswith(var.api_token_secret_arn, "arn:aws:secretsmanager:") && var.image_tag != "bootstrap"
      error_message = "Runtime requires a valid ACM certificate ARN, a pre-created Secrets Manager secret ARN, and a built ECR image tag."
    }
  }
}

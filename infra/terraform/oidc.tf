# Optional one-time AWS account setup. Do NOT create duplicate OIDC providers.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  tags = local.tags
}
data "aws_iam_openid_connect_provider" "existing" {
  count = var.enable_github_deploy_role && !var.create_github_oidc_provider ? 1 : 0
  url = "https://token.actions.githubusercontent.com"
}
locals {
  oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : (
  var.enable_github_deploy_role ? data.aws_iam_openid_connect_provider.existing[0].arn : null
  )
}
resource "aws_iam_role" "github_deploy" {
  count = var.enable_github_deploy_role ? 1 : 0
  name  = "${var.project_name}-github-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:production"
        }
      }
    }]
  })
  tags = local.tags
}
resource "aws_iam_role_policy" "github_deploy" {
  count = var.enable_github_deploy_role ? 1 : 0
  name = "${var.project_name}-github-ecr-ecs"
  role = aws_iam_role.github_deploy[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
    {
      Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*"
    },
    {
      Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"], Resource = aws_ecr_repository.app.arn
    },
    {
      Effect = "Allow", Action = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition", "ecs:DescribeServices"], Resource = "*"
    },
    {
      Effect = "Allow", Action = ["ecs:UpdateService"], Resource = [
      "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.main.name}/${var.project_name}-api",
      "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.main.name}/${var.project_name}-worker"
      ]
    },
    {
      Effect = "Allow", Action = ["iam:PassRole"], Resource = [aws_iam_role.execution.arn, aws_iam_role.api.arn, aws_iam_role.worker.arn]
    }
    ]
  })
}

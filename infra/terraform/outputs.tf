output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}
output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}
output "orders_queue_url" {
  value = aws_sqs_queue.orders.url
}
output "dead_letter_queue_url" {
  value = aws_sqs_queue.dead_letter.url
}
output "orders_table" {
  value = aws_dynamodb_table.orders.name
}
output "alb_dns_name" {
  value = var.enable_runtime ? aws_lb.api[0].dns_name : null
}
output "github_deploy_role_arn" {
  value = var.enable_github_deploy_role ? aws_iam_role.github_deploy[0].arn : null
}

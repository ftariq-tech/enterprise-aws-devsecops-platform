resource "aws_ecs_cluster" "main" {
  name = var.project_name
  setting {
    name = "containerInsights"
    value = "disabled"
  }
  tags = local.tags
}
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "execution" {
  name = "${var.project_name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags = local.tags
}
resource "aws_iam_role_policy_attachment" "execution" {
  role = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "secret" {
  count = var.api_token_secret_arn != "" ? 1 : 0
  name = "${var.project_name}-secret-read"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Action = ["secretsmanager:GetSecretValue"],
      Resource = var.api_token_secret_arn != "" ? [var.api_token_secret_arn] : []
    }]
  })
}
resource "aws_iam_role" "api" {
  name = "${var.project_name}-api"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags = local.tags
}
resource "aws_iam_role_policy" "api" {
  name = "${var.project_name}-api-io"
  role = aws_iam_role.api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
    {
      Effect = "Allow", Action = ["sqs:SendMessage"], Resource = aws_sqs_queue.orders.arn
    },
    {
      Effect = "Allow", Action = ["dynamodb:GetItem"], Resource = aws_dynamodb_table.orders.arn
    }
    ]
  })
}
resource "aws_iam_role" "worker" {
  name = "${var.project_name}-worker"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags = local.tags
}
resource "aws_iam_role_policy" "worker" {
  name = "${var.project_name}-worker-io"
  role = aws_iam_role.worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
    {
      Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"], Resource = aws_sqs_queue.orders.arn
    },
    {
      Effect = "Allow", Action = ["dynamodb:PutItem", "dynamodb:GetItem"], Resource = aws_dynamodb_table.orders.arn
    }
    ]
  })
}
resource "aws_lb" "api" {
  count = var.enable_runtime ? 1 : 0
  name               = substr(var.project_name, 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = false
  tags = local.tags
  depends_on = [terraform_data.runtime_guard]
}
resource "aws_lb_target_group" "api" {
  count = var.enable_runtime ? 1 : 0
  name        = substr("${var.project_name}-api", 0, 32)
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/health/ready"
    healthy_threshold = 2
    unhealthy_threshold = 3
    interval = 30
    timeout = 5
    matcher = "200"
  }
  tags = local.tags
}
resource "aws_lb_listener" "https" {
  count = var.enable_runtime ? 1 : 0
  load_balancer_arn = aws_lb.api[0].arn
  port = 443
  protocol = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn = var.acm_certificate_arn
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.api[0].arn
  }
  tags = local.tags
}
resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project_name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.api.arn
  container_definitions = jsonencode([{
    name = "api"
    image = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true
    portMappings = [{
      containerPort = 8000, hostPort = 8000, protocol = "tcp"
    }]
    environment = [
    {
      name = "BACKEND", value = "aws"
    },
    {
      name = "QUEUE_URL", value = aws_sqs_queue.orders.url
    },
    {
      name = "ORDERS_TABLE", value = aws_dynamodb_table.orders.name
    },
    {
      name = "AWS_DEFAULT_REGION", value = var.aws_region
    }
    ]
   
secrets = var.api_token_secret_arn != "" ? [{ name = "ORDERS_API_TOKEN", valueFrom = var.api_token_secret_arn }] : []

    logConfiguration = {
      logDriver = "awslogs", options = {
        awslogs-group = aws_cloudwatch_log_group.api.name,
        awslogs-region = var.aws_region,
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
  tags = local.tags
}
resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.project_name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.worker.arn
  container_definitions = jsonencode([{
    name = "worker"
    image = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true
    command = ["python", "-m", "app.worker"]
    environment = [
    {
      name = "QUEUE_URL", value = aws_sqs_queue.orders.url
    },
    {
      name = "ORDERS_TABLE", value = aws_dynamodb_table.orders.name
    },
    {
      name = "AWS_DEFAULT_REGION", value = var.aws_region
    }
    ]
    logConfiguration = {
      logDriver = "awslogs", options = {
        awslogs-group = aws_cloudwatch_log_group.worker.name,
        awslogs-region = var.aws_region,
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
  tags = local.tags
}
resource "aws_ecs_service" "api" {
  count = var.enable_runtime ? 1 : 0
  name            = "${var.project_name}-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_desired_count
  launch_type     = "FARGATE"
  health_check_grace_period_seconds = 90
  deployment_circuit_breaker {
    enable = true
    rollback = true
  }
  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.api[0].arn
    container_name   = "api"
    container_port   = 8000
  }
  depends_on = [aws_lb_listener.https]
  tags = local.tags
}
resource "aws_ecs_service" "worker" {
  count = var.enable_runtime ? 1 : 0
  name            = "${var.project_name}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"
  deployment_circuit_breaker {
    enable = true
    rollback = true
  }
  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }
  tags = local.tags
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, {
    Name = "${var.project_name}-vpc"
  })
}
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, {
    Name = "${var.project_name}-igw"
  })
}
resource "aws_subnet" "public" {
  for_each = local.subnet_map
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.public
  availability_zone       = each.value.az
  map_public_ip_on_launch = false
  tags                    = merge(local.tags, {
    Name = "${var.project_name}-public-${each.key}"
  })
}
resource "aws_subnet" "private" {
  for_each = local.subnet_map
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.private
  availability_zone = each.value.az
  tags              = merge(local.tags, {
    Name = "${var.project_name}-private-${each.key}"
  })
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(local.tags, {
    Name = "${var.project_name}-public-routes"
  })
}
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
# Single NAT gateway is a cost-focused demonstration, NOT AZ-resilient production design.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = local.tags
}
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["0"].id
  depends_on    = [aws_internet_gateway.main]
  tags          = merge(local.tags, {
    Name = "${var.project_name}-nat"
  })
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = merge(local.tags, {
    Name = "${var.project_name}-private-routes"
  })
}
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  vpc_id      = aws_vpc.main.id
  tags        = local.tags
}
resource "aws_security_group" "tasks" {
  name_prefix = "${var.project_name}-ecs-"
  vpc_id      = aws_vpc.main.id
  tags        = local.tags
}
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from internet (authenticated API, demo)"
}
resource "aws_vpc_security_group_egress_rule" "alb_to_api" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.tasks.id
  from_port = 8000
  to_port = 8000
  ip_protocol = "tcp"
  description = "Only ECS API target port"
}
resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port = 8000
  to_port = 8000
  ip_protocol = "tcp"
  description = "API from ALB only; worker has no listener"
}
resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  security_group_id = aws_security_group.tasks.id
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 443
  to_port = 443
  ip_protocol = "tcp"
  description = "Outbound AWS API and container pulls via NAT; restrict with VPC endpoints in prod"
}

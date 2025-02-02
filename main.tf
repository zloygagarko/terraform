provider "aws" {
  region  = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "example" {
  cidr_block = var.vpc_cidr_block
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "example-vpc"
  }
}

resource "aws_subnet" "example" {
  count = length(var.subnet_cidr_blocks)

  vpc_id                  = aws_vpc.example.id
  cidr_block              = element(var.subnet_cidr_blocks, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "example-subnet-${count.index}"
  }
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "example-igw"
  }
}

resource "aws_security_group" "example" {
  name        = "example-sg"
  description = "Allow all inbound and outbound traffic for testing"
  vpc_id      = aws_vpc.example.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "example-sg"
  }
}

resource "aws_lb" "example" {
  name               = "example-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.example.id]
  subnets            = aws_subnet.example[*].id
  enable_deletion_protection = false
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "example-alb"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example.arn
  }
}


resource "aws_lb_target_group" "example" {
  name     = "example-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.example.id

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = 200
  }
}


data "aws_iam_role" "ecs_execution_role" {
  name = "ecsExecutionRole"
}

data "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole"  # Reference the existing role name
}


resource "aws_ecs_cluster" "example" {
  name = "example-cluster"
}

resource "aws_ecs_task_definition" "example" {
  family                   = "example-task"
  execution_role_arn       = data.aws_iam_role.ecs_execution_role.arn
  task_role_arn            = data.aws_iam_role.ecs_task_role.arn
  container_definitions    = jsonencode([{
    name      = "example-container"
    image     = "public.ecr.aws/l6n4l7y8/default/test_wordpress:latest"
    cpu       = 256
    memory    = 512
    essential = true
     portMappings = [
      {
        containerPort = 80
        hostPort      = 80  # You can leave this out if it's the same as the container port
        protocol      = "tcp"
      }
    ]
  }])
}

resource "aws_ecs_service" "example" {
  name            = "example-service"
  cluster         = aws_ecs_cluster.example.id
  task_definition = aws_ecs_task_definition.example.arn
  desired_count   = 1

  load_balancer {
    target_group_arn = aws_lb_target_group.example.arn
    container_name   = "example-container"
    container_port   = 80
  }

  depends_on = [aws_lb_target_group.example]  # Ensure the target group is created before the ECS service
}

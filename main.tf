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


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.subnet_cidr_blocks)
  subnet_id      = aws_subnet.example[count.index].id
  route_table_id = aws_route_table.public.id
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
  target_type = "ip"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = 302
  }
}

resource "aws_iam_policy" "ecs_ecr_policy" {
  name        = "ECS_ECR_Policy"
  description = "Policy to allow ECS to pull images from ECR"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "arn:aws:ecr:us-east-1:public:repository/l6n4l7y8/default/test_wordpress"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy_attachment" {
  role       = data.aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ecs_ecr_policy.arn
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

resource "aws_ecs_cluster_capacity_providers" "example_capacity_providers" {
  cluster_name = aws_ecs_cluster.example.name

  capacity_providers = ["FARGATE"]  # Here you can set the capacity provider to Fargate
  
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_ecs_task_definition" "example" {
  family                   = "example-task"
  execution_role_arn       = data.aws_iam_role.ecs_execution_role.arn
  task_role_arn            = data.aws_iam_role.ecs_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]  # Specify Fargate as the launch type
  cpu                      = "256"  # 0.25 vCPU
  memory                   = "512"  # 0.5 GB
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
  network_configuration {
    subnets          = aws_subnet.example[*].id  # Use the subnets you've defined earlier
    security_groups  = [aws_security_group.example.id]
    assign_public_ip = true  # Or "DISABLED" based on your use case
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.example.arn
    container_name   = "example-container"
    container_port   = 80
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }

  depends_on = [aws_lb_target_group.example]  # Ensure the target group is created before the ECS service
}

terraform {
  backend "s3" {
    bucket         = "rag-app-terraform-aws-state-047719620060" # To store terraform state at a centralized location
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks" # For state locking
  }
}

# --- 1. Provider & Networking ---
provider "aws" {
  region = "us-east-1"
}
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "rag-app-vpc"
  cidr = "10.0.0.0/16"

  azs            = ["us-east-1a", "us-east-1b"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# --- 2. Security Groups ---
resource "aws_security_group" "alb_sg" {
  name        = "rag-app-alb-sg"
  description = "Allow HTTP inbound traffic for ALB"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "ecs_sg" {
  name        = "rag-app-ecs-sg"
  description = "Allow inbound traffic from the ALB"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port       = 8501
    to_port         = 8501
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 3. ECR, ECS Cluster, and IAM Role ---
resource "aws_ecr_repository" "backend" {
  name         = "rag-backend"
  force_delete = true
}
resource "aws_ecr_repository" "frontend" {
  name         = "rag-frontend"
  force_delete = true
}
resource "aws_ecs_cluster" "main" {
  name = "rag-app-cluster"
}
resource "aws_cloudwatch_log_group" "backend_logs" {
  name = "/ecs/rag-backend"
}
resource "aws_cloudwatch_log_group" "frontend_logs" {
  name = "/ecs/rag-frontend"
}
data "aws_caller_identity" "current" {}
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs-task-execution-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_policy" "ssm_policy" {
  name        = "ecs-ssm-parameter-store-policy"
  description = "Allows ECS tasks to read from SSM Parameter Store"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameters"]
      Resource = "arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:parameter/rag-app/*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_ssm_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ssm_policy.arn
}

# --- 4. SSM Parameter Store ---
resource "aws_ssm_parameter" "openai_api_key" {
  name  = "/rag-app/secrets/openai_api_key"
  type  = "SecureString"
  value = var.openai_api_key
}
resource "aws_ssm_parameter" "pinecone_api_key" {
  name  = "/rag-app/secrets/pinecone_api_key"
  type  = "SecureString"
  value = var.pinecone_api_key
}
resource "aws_ssm_parameter" "openai_embedding_model" {
  name  = "/rag-app/config/openai_embedding_model"
  type  = "String"
  value = var.openai_embedding_model
}
resource "aws_ssm_parameter" "openai_chat_model" {
  name  = "/rag-app/config/openai_chat_model"
  type  = "String"
  value = var.openai_chat_model
}
resource "aws_ssm_parameter" "openai_embedding_model_dimensions" {
  name  = "/rag-app/config/openai_embedding_model_dimensions"
  type  = "String"
  value = var.openai_embedding_model_dimensions
}
resource "aws_ssm_parameter" "pinecone_environment" {
  name  = "/rag-app/config/pinecone_environment"
  type  = "String"
  value = var.pinecone_environment
}
resource "aws_ssm_parameter" "pinecone_index_name" {
  name  = "/rag-app/config/pinecone_index_name"
  type  = "String"
  value = var.pinecone_index_name
}
resource "aws_ssm_parameter" "pinecone_cloud_provider" {
  name  = "/rag-app/config/pinecone_cloud_provider"
  type  = "String"
  value = var.pinecone_cloud_provider
}

# --- 5. ALB, Target Groups, and Listeners ---
resource "aws_lb" "main" {
  name               = "rag-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets
}
resource "aws_lb_target_group" "frontend" {
  name        = "rag-app-frontend-tg"
  port        = 8501
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
  health_check { path = "/" }
}
resource "aws_lb_target_group" "backend" {
  name        = "rag-app-backend-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
  health_check { path = "/ping" }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}
resource "aws_lb_listener_rule" "backend_api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
  condition {
    path_pattern { values = ["/ask*", "/upload*", "/ping*"] }
  }
}

# --- 6. ECS Task Definitions and Services ---
resource "aws_ecs_task_definition" "backend" {
  family                   = "rag-backend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"  # 0.25 vCPU
  memory                   = "512" # 0.5 GB
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "rag-backend"
      image     = "${aws_ecr_repository.backend.repository_url}:latest"
      essential = true
      portMappings = [{ containerPort = 8000, hostPort = 8000 }]
      
      environment = [
        { name = "OPENAI_EMBEDDING_MODEL", valueFrom = aws_ssm_parameter.openai_embedding_model.arn },
        { name = "OPENAI_CHAT_MODEL", valueFrom = aws_ssm_parameter.openai_chat_model.arn },
        { name = "OPENAI_EMBEDDING_MODEL_DIMENSIONS", valueFrom = aws_ssm_parameter.openai_embedding_model_dimensions.arn },
        { name = "PINECONE_ENVIRONMENT", valueFrom = aws_ssm_parameter.pinecone_environment.arn },
        { name = "PINECONE_INDEX_NAME", valueFrom = aws_ssm_parameter.pinecone_index_name.arn },
        { name = "PINECONE_CLOUD_PROVIDER", valueFrom = aws_ssm_parameter.pinecone_cloud_provider.arn },
      ]
      
      secrets = [
        { name = "OPENAI_API_KEY", valueFrom = aws_ssm_parameter.openai_api_key.arn },
        { name = "PINECONE_API_KEY", valueFrom = aws_ssm_parameter.pinecone_api_key.arn }
      ]
      
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend_logs.name,
          "awslogs-region"        = "us-east-1",
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  # This block explicitly defines the dependency order
  depends_on = [
    aws_ssm_parameter.openai_embedding_model,
    aws_ssm_parameter.openai_chat_model,
    aws_ssm_parameter.openai_embedding_model_dimensions,
    aws_ssm_parameter.pinecone_environment,
    aws_ssm_parameter.pinecone_index_name,
    aws_ssm_parameter.pinecone_cloud_provider,
    aws_ssm_parameter.openai_api_key,
    aws_ssm_parameter.pinecone_api_key
  ]
}
resource "aws_ecs_task_definition" "frontend" {
  family                   = "rag-frontend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" # 0.25 vCPU
  memory                   = "512" # 0.5 GB
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "rag-frontend"
      image     = "${aws_ecr_repository.frontend.repository_url}:latest"
      essential = true
      portMappings = [{ containerPort = 8501, hostPort = 8501 }]
      environment = [{
          name  = "BACKEND_URL",
          value = "http://${aws_lb.main.dns_name}"
      }]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend_logs.name,
          "awslogs-region"        = "us-east-1",
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}
resource "aws_ecs_service" "backend" {
  name            = "rag-backend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = module.vpc.public_subnets
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "rag-backend"
    container_port   = 8000
  }
}
resource "aws_ecs_service" "frontend" {
  name            = "rag-frontend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = module.vpc.public_subnets
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "rag-frontend"
    container_port   = 8501
  }
}

# --- 7. Outputs ---
output "app_url" {
  value = "http://${aws_lb.main.dns_name}"
}

# --- Replace the old debug output with this new one ---
output "debug_ssm_parameter_arns" {
  description = "Check the values of the SSM Parameter ARNs directly."
  value = {
    # These are the variables for the 'environment' block that is failing
    embedding_model_arn = aws_ssm_parameter.openai_embedding_model.arn
    chat_model_arn      = aws_ssm_parameter.openai_chat_model.arn
    dimensions_arn      = aws_ssm_parameter.openai_embedding_model_dimensions.arn
    pinecone_env_arn    = aws_ssm_parameter.pinecone_environment.arn
    pinecone_index_arn  = aws_ssm_parameter.pinecone_index_name.arn
    pinecone_cloud_arn  = aws_ssm_parameter.pinecone_cloud_provider.arn

    # These are for the 'secrets' block that is working, for comparison
    openai_secret_arn   = aws_ssm_parameter.openai_api_key.arn
    pinecone_secret_arn = aws_ssm_parameter.pinecone_api_key.arn
  }
  sensitive = true # Marking as sensitive to be safe
}

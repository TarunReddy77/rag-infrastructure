terraform {
  backend "s3" {
    bucket         = "rag-app-terraform-aws-state-047719620060" # To store terraform state at a centralized location
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks" # For state locking
  }
}

# --- 1. Provider & Networking ---
# We keep the provider and VPC definition as they don't incur costs
# and provide a stable foundation for the next time you apply.

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

# All other resources (Security Groups, ECR, ECS, ALB, SSM, etc.) have been removed.
# When this file is applied, Terraform will destroy all resources that are
# managed in its state but are no longer present in this configuration.

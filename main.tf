terraform {
  backend "s3" {
    bucket         = "terraform-state-alexw5418-2026"
    key            = "k3s-cluster/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source       = "./modules/vpc"
  project_name = "k3s-cluster"
}

module "security" {
  source       = "./modules/security"
  project_name = "k3s-cluster"
  vpc_id       = module.vpc.vpc_id
}

module "compute" {
  source            = "./modules/compute"
  project_name      = "k3s-cluster"
  subnet_id         = module.vpc.subnet_id
  security_group_id = module.security.security_group_id
  key_name          = "test-keypair"
}

output "server_ip" {
  value = module.compute.server_public_ip
}

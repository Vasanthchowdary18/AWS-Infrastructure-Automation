terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Optional remote state - create the bucket first, then uncomment
  # backend "s3" {
  #   bucket = "my-tf-state-bucket"
  #   key    = "devops-eks/terraform.tfstate"
  #   region = "ap-south-1"
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "pravin-devops-platform"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

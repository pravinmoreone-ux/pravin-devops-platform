variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
  default     = "devops"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "pravin-devops-platform"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.40.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default = [
    "ap-south-1a",
    "ap-south-1b"
  ]
}


variable "key_name" {
  description = "Existing AWS EC2 key pair name"
  type        = string
  default     = "linux-ec2-lab-key"
}

variable "jump_instance_type" {
  description = "Jump server instance type"
  type        = string
  default     = "t3.small"
}

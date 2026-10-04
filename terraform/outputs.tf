output "jump_instance_id" {
  description = "Jump server EC2 instance ID"
  value       = aws_instance.jump.id
}

output "jump_public_ip" {
  description = "Jump server public IP"
  value       = aws_instance.jump.public_ip
}

output "jump_private_ip" {
  description = "Jump server private IP"
  value       = aws_instance.jump.private_ip
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "app_instance_id" {
  description = "Application server EC2 instance ID"
  value       = aws_instance.app.id
}

output "app_private_ip" {
  description = "Application server private IP"
  value       = aws_instance.app.private_ip
}

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

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS Kubernetes API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "eks_cluster_version" {
  description = "EKS Kubernetes version"
  value       = aws_eks_cluster.main.version
}

output "eks_node_group_name" {
  description = "EKS managed node group name"
  value       = aws_eks_node_group.main.node_group_name
}

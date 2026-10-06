package terraform.security

# ============================================================
# Deny rules - each rule produces a message if violated
# ============================================================

# 1. All resources must have required tags
deny[msg] {
    resource := input.resource_changes[_]
    resource.type != "aws_iam_role_policy"
    resource.type != "aws_iam_role_policy_attachment"
    resource.type != "aws_iam_openid_connect_provider"
    resource.type != "aws_kms_key"
    resource.type != "aws_kms_alias"
    
    tags := resource.change.after.tags
    not tags.Project
    
    msg := sprintf("Resource '%s' (%s) missing required tag: Project", [resource.address, resource.type])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type != "aws_iam_role_policy"
    resource.type != "aws_iam_role_policy_attachment"
    resource.type != "aws_iam_openid_connect_provider"
    resource.type != "aws_kms_key"
    resource.type != "aws_kms_alias"
    
    tags := resource.change.after.tags
    not tags.Environment
    
    msg := sprintf("Resource '%s' (%s) missing required tag: Environment", [resource.address, resource.type])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type != "aws_iam_role_policy"
    resource.type != "aws_iam_role_policy_attachment"
    resource.type != "aws_iam_openid_connect_provider"
    resource.type != "aws_kms_key"
    resource.type != "aws_kms_alias"
    
    tags := resource.change.after.tags
    not tags.ManagedBy
    
    msg := sprintf("Resource '%s' (%s) missing required tag: ManagedBy", [resource.address, resource.type])
}

# 2. EBS volumes must be encrypted
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_ebs_volume"
    not resource.change.after.encrypted
    
    msg := sprintf("EBS volume '%s' must be encrypted", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    root_block := resource.change.after.root_block_device
    not root_block.encrypted
    
    msg := sprintf("EC2 instance '%s' root volume must be encrypted", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    ebs_devices := resource.change.after.ebs_block_device
    ebs_devices[_]
    ebs_device := ebs_devices[_]
    not ebs_device.encrypted
    
    msg := sprintf("EC2 instance '%s' has unencrypted EBS block device", [resource.address])
}

# 3. EC2 instances must require IMDSv2
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    metadata := resource.change.after.metadata_options
    metadata.http_tokens != "required"
    
    msg := sprintf("EC2 instance '%s' must require IMDSv2 (metadata_options.http_tokens = required)", [resource.address])
}

# 4. Private resources must not have public IPs
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    resource.change.after.associate_public_ip_address == true
    is_private_subnet(resource.change.after.subnet_id)
    
    msg := sprintf("EC2 instance '%s' in private subnet must not have public IP", [resource.address])
}

is_private_subnet(subnet_id) {
    subnet := input.planned_values.root_module.resources[_]
    subnet.type == "aws_subnet"
    subnet.values.id == subnet_id
    subnet.values.tags.Tier == "private"
}

# 5. Security groups must not allow unrestricted ingress (0.0.0.0/0) on sensitive ports
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_security_group"
    rule := resource.change.after.ingress[_]
    rule.cidr_blocks[_] == "0.0.0.0/0"
    sensitive_port(rule.from_port, rule.to_port)
    
    msg := sprintf("Security group '%s' allows 0.0.0.0/0 on sensitive port %d-%d", [resource.address, rule.from_port, rule.to_port])
}

sensitive_port(from, to) {
    ports := {22, 3389, 3306, 5432, 6379, 27017, 9200, 9300}
    ports[from]
    from == to
}

# 6. EKS cluster must have private endpoint only
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_eks_cluster"
    resource.change.after.vpc_config.endpoint_public_access == true
    
    msg := "EKS cluster must have private endpoint only (endpoint_public_access = false)"
}

# 7. EKS cluster must have secrets encryption
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_eks_cluster"
    not resource.change.after.encryption_config[_].resources[_] == "secrets"
    
    msg := "EKS cluster must have encryption_config for secrets"
}

# 8. EKS node group must use approved instance types
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_eks_node_group"
    instance_type := resource.change.after.instance_types[_]
    not approved_eks_instance_type[instance_type]
    
    msg := sprintf("EKS node group '%s' uses unapproved instance type: %s", [resource.address, instance_type])
}

approved_eks_instance_type contains "t3.small"
approved_eks_instance_type contains "t3.medium"
approved_eks_instance_type contains "t3.large"
approved_eks_instance_type contains "t3.xlarge"
approved_eks_instance_type contains "t4g.small"
approved_eks_instance_type contains "t4g.medium"
approved_eks_instance_type contains "t4g.large"

# 9. KMS keys must have rotation enabled
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_kms_key"
    not resource.change.after.enable_key_rotation
    
    msg := sprintf("KMS key '%s' must have key rotation enabled", [resource.address])
}

# 10. NAT Gateway must be in public subnet
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_nat_gateway"
    not is_public_subnet(resource.change.after.subnet_id)
    
    msg := sprintf("NAT Gateway '%s' must be in public subnet", [resource.address])
}

is_public_subnet(subnet_id) {
    subnet := input.planned_values.root_module.resources[_]
    subnet.type == "aws_subnet"
    subnet.values.id == subnet_id
    subnet.values.tags.Tier == "public"
}

# 11. RDS instances (if any) must be encrypted and not publicly accessible
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_db_instance"
    not resource.change.after.storage_encrypted
    
    msg := sprintf("RDS instance '%s' must be encrypted", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_db_instance"
    resource.change.after.publicly_accessible
    
    msg := sprintf("RDS instance '%s' must not be publicly accessible", [resource.address])
}

# ============================================================
# Warning rules - non-blocking but reported
# ============================================================

warn[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_instance"
    instance_type := resource.change.after.instance_type
    not cost_effective_instance_type[instance_type]
    
    msg := sprintf("WARNING: Instance '%s' uses instance type '%s' - consider right-sizing for cost optimization", [resource.address, instance_type])
}

cost_effective_instance_type contains "t3.small"
cost_effective_instance_type contains "t3.medium"
cost_effective_instance_type contains "t4g.small"
cost_effective_instance_type contains "t4g.medium"

# 12. S3 buckets (if any) must have versioning and encryption
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_s3_bucket"
    not resource.change.after.versioning[_].enabled
    
    msg := sprintf("S3 bucket '%s' must have versioning enabled", [resource.address])
}

deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_s3_bucket_server_side_encryption_configuration"
    not resource.change.after.rule[_].apply_server_side_encryption_by_default.sse_algorithm
    
    msg := sprintf("S3 bucket '%s' must have default encryption", [resource.address])
}
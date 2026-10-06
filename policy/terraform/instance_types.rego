package terraform.instance_types

deny contains msg if {
  resource := input.resource_changes[_]
  resource.type == "aws_instance"
  instance_type := resource.change.after.instance_type
  not allowed_instance_type[instance_type]

  msg := sprintf(
    "EC2 instance type '%s' is not allowed. Use an approved instance type.",
    [instance_type]
  )
}

allowed_instance_type contains "t3.small"
allowed_instance_type contains "t3.medium"
allowed_instance_type contains "t3.large"

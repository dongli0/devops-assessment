output "vpc_id" {
  description = "ID of the shared platform VPC."
  value       = alicloud_vpc.this.id
}

output "vpc_cidr" {
  description = "IPv4 CIDR of the shared platform VPC."
  value       = alicloud_vpc.this.cidr_block
}

output "vswitch_ids" {
  description = "vSwitch IDs keyed by stable logical name."
  value = {
    for key, vswitch in alicloud_vswitch.this :
    key => vswitch.id
  }
}

output "alb_vswitch_ids" {
  description = "Ordered vSwitch IDs used to render the shared ALB configuration."
  value = [
    alicloud_vswitch.this["a"].id,
    alicloud_vswitch.this["b"].id,
  ]
}

output "security_group_id" {
  description = "Security group ID used by the ACS cluster."
  value       = alicloud_security_group.acs.id
}

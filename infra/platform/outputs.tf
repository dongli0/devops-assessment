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

output "cluster_id" {
  description = "ID of the shared ACS cluster."
  value       = alicloud_cs_managed_kubernetes.this.id
}

output "cluster_name" {
  description = "Name of the shared ACS cluster."
  value       = alicloud_cs_managed_kubernetes.this.name
}

output "cluster_version" {
  description = "Kubernetes version running on the ACS cluster."
  value       = alicloud_cs_managed_kubernetes.this.version
}

output "cluster_api_endpoints" {
  description = "Public and private Kubernetes API endpoints."
  value = {
    internet = try(
      alicloud_cs_managed_kubernetes.this.connections["api_server_internet"],
      null,
    )
    intranet = try(
      alicloud_cs_managed_kubernetes.this.connections["api_server_intranet"],
      null,
    )
  }
}

output "cluster_rrsa_oidc_issuer_url" {
  description = "OIDC issuer URL created for RRSA."
  value = try(
    alicloud_cs_managed_kubernetes.this.rrsa_metadata[0].rrsa_oidc_issuer_url,
    null,
  )
}

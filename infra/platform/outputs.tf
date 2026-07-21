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

output "rds_instance_id" {
  description = "ID of the shared PostgreSQL Serverless instance."
  value       = alicloud_db_instance.postgresql.id
}

output "rds_internal_endpoint" {
  description = "Internal RDS endpoint used by workloads in the VPC."
  value = {
    host = alicloud_db_instance.postgresql.connection_string
    port = alicloud_db_instance.postgresql.port
  }
}

output "database_names" {
  description = "Database names keyed by environment."
  value = {
    for environment in local.environment_names :
    environment => alicloud_db_database.environment[environment].data_base_name
  }
}

output "database_account_names" {
  description = "Database account names keyed by environment."
  value = {
    for environment in local.environment_names :
    environment => alicloud_rds_account.environment[environment].account_name
  }
}

output "database_urls" {
  description = "SQLAlchemy database URLs keyed by environment."
  sensitive   = true

  value = {
    for environment in local.environment_names :
    environment => format(
      "postgresql+asyncpg://%s:%s@%s:%s/%s",
      alicloud_rds_account.environment[environment].account_name,
      random_password.database[environment].result,
      alicloud_db_instance.postgresql.connection_string,
      alicloud_db_instance.postgresql.port,
      alicloud_db_database.environment[environment].data_base_name,
    )
  }
}

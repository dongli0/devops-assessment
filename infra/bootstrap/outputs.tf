output "state_bucket_name" {
  description = "OSS bucket containing Terraform state."
  value       = alicloud_oss_bucket.state.bucket
}

output "lock_instance_name" {
  description = "Tablestore instance used by the OSS backend."
  value       = alicloud_ots_instance.locks.name
}

output "lock_table_name" {
  description = "Tablestore table used by the OSS backend."
  value       = alicloud_ots_table.locks.table_name
}

output "tablestore_endpoint" {
  description = "Public Tablestore endpoint used by GitHub Actions."
  value       = "https://${alicloud_ots_instance.locks.name}.${var.region}.ots.aliyuncs.com"
}

output "platform_state_prefix" {
  description = "OSS prefix reserved for the platform Terraform state."
  value       = "devops-assessment/platform"
}

output "platform_state_key" {
  description = "Object key used for the platform Terraform state."
  value       = "terraform.tfstate"
}

output "github_oidc_provider_arn" {
  description = "OIDC provider ARN configured for GitHub Actions."
  value       = alicloud_ims_oidc_provider.github.arn
}

output "github_terraform_role_arn" {
  description = "RAM role ARN assumed by GitHub Actions."
  value       = alicloud_ram_role.github.arn
}

output "github_deploy_role_arn" {
  description = "RAM role ARN used by the service deployment pipeline."
  value       = try(alicloud_ram_role.github_deploy[0].arn, null)
}

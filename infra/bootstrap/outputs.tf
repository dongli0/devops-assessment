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

output "platform_state_key" {
  description = "Object key reserved for the platform Terraform state."
  value       = "devops-assessment/platform/terraform.tfstate"
}

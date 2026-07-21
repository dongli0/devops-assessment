variable "region" {
  description = "Alibaba Cloud region used by the platform."
  type        = string
  default     = "cn-shanghai"
}

variable "project_name" {
  description = "Short name used as the prefix for platform resources."
  type        = string
  default     = "portfolio"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,31}$", var.project_name))
    error_message = "project_name must match ^[a-z][a-z0-9-]{2,31}$."
  }
}

variable "state_bucket_name" {
  description = "Globally unique OSS bucket name for Terraform state."
  type        = string

  validation {
    condition = can(
      regex(
        "^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$",
        var.state_bucket_name,
      )
    )
    error_message = "state_bucket_name must be a valid lowercase OSS bucket name."
  }
}

variable "lock_instance_name" {
  description = "Tablestore instance name used for Terraform locking."
  type        = string

  validation {
    condition = can(
      regex(
        "^[a-z][a-z0-9-]{1,14}[a-z0-9]$",
        var.lock_instance_name,
      )
    )
    error_message = "lock_instance_name must contain 3-16 lowercase characters."
  }
}

variable "lock_table_name" {
  description = "Tablestore table name used for Terraform locking."
  type        = string
  default     = "terraform_locks"
}

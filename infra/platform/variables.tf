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

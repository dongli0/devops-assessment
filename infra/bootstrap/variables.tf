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

variable "github_oidc_fingerprints" {
  description = "SHA-1 CA fingerprints trusted for the GitHub OIDC issuer."
  type        = set(string)

  validation {
    condition = (
      length(var.github_oidc_fingerprints) >= 1 &&
      length(var.github_oidc_fingerprints) <= 5 &&
      alltrue([
        for fingerprint in var.github_oidc_fingerprints :
        can(regex("^[0-9A-Fa-f]{40}$", fingerprint))
      ])
    )
    error_message = "Provide between one and five 40-character SHA-1 fingerprints."
  }
}

variable "github_oidc_subjects" {
  description = "Exact GitHub OIDC subject claims allowed to assume the role."
  type        = set(string)

  validation {
    condition = (
      length(var.github_oidc_subjects) >= 1 &&
      length(var.github_oidc_subjects) <= 10 &&
      alltrue([
        for subject in var.github_oidc_subjects :
        startswith(subject, "repo:") && !strcontains(subject, "*")
      ])
    )
    error_message = "Provide exact repo-scoped OIDC subjects without wildcards."
  }
}

variable "deployment_cluster_id" {
  description = "ACS cluster ID authorized for service deployment after platform apply."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.deployment_cluster_id == null ?
      true :
      can(regex("^[A-Za-z0-9][A-Za-z0-9-]{7,127}$", var.deployment_cluster_id))
    )
    error_message = "deployment_cluster_id must be null or a valid ACS cluster ID."
  }
}

variable "github_deploy_oidc_subjects" {
  description = "Exact GitHub Environment OIDC subjects allowed to deploy services."
  type        = set(string)
  default     = []

  validation {
    condition = (
      (
        var.deployment_cluster_id == null &&
        length(var.github_deploy_oidc_subjects) == 0
      ) ||
      (
        var.deployment_cluster_id != null &&
        length(var.github_deploy_oidc_subjects) >= 1 &&
        length(var.github_deploy_oidc_subjects) <= 10 &&
        alltrue([
          for subject in var.github_deploy_oidc_subjects :
          startswith(subject, "repo:") &&
          strcontains(subject, ":environment:") &&
          !strcontains(subject, "*")
        ])
      )
    )
    error_message = "Configure the cluster ID and one to ten exact GitHub Environment subjects together."
  }
}

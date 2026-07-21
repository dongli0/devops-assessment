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

variable "vpc_cidr" {
  description = "IPv4 CIDR allocated to the shared platform VPC."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR."
  }
}

variable "vswitches" {
  description = "Two explicitly selected vSwitches in distinct zones."
  type = map(object({
    zone_id    = string
    cidr_block = string
  }))

  validation {
    condition = (
      toset(keys(var.vswitches)) == toset(["a", "b"])
    )
    error_message = "vswitches must contain exactly the keys a and b."
  }

  validation {
    condition = (
      length(distinct([
        for config in values(var.vswitches) : config.zone_id
      ])) == 2 &&
      length(distinct([
        for config in values(var.vswitches) : config.cidr_block
      ])) == 2
    )
    error_message = "vSwitch zones and CIDR blocks must be distinct."
  }

  validation {
    condition = alltrue([
      for config in values(var.vswitches) :
      startswith(config.zone_id, "${var.region}-") &&
      can(cidrnetmask(config.cidr_block))
    ])
    error_message = "Each vSwitch requires a zone in the selected region and a valid CIDR."
  }
}

data "alicloud_alb_zones" "available" {}

resource "alicloud_vpc" "this" {
  vpc_name     = "${var.project_name}-vpc"
  cidr_block   = var.vpc_cidr
  description  = "Shared VPC for the portfolio assessment platform."
  enable_ipv6  = false
  force_delete = false

  tags = merge(local.common_tags, {
    Component = "network"
  })

  lifecycle {
    precondition {
      condition = try(
        alltrue([
          for network in values(local.network_ranges.vswitches) :
          network.first >= local.network_ranges.vpc.first &&
          network.last <= local.network_ranges.vpc.last
        ]),
        false,
      )
      error_message = "Every vSwitch CIDR must be fully contained within vpc_cidr."
    }

    precondition {
      condition = try(
        local.network_ranges.vswitches["a"].last <
        local.network_ranges.vswitches["b"].first ||
        local.network_ranges.vswitches["b"].last <
        local.network_ranges.vswitches["a"].first,
        false,
      )
      error_message = "The a and b vSwitch CIDR blocks must not overlap."
    }

    precondition {
      condition = try(
        local.network_ranges.service.last <
        local.network_ranges.vpc.first ||
        local.network_ranges.vpc.last <
        local.network_ranges.service.first,
        false,
      )
      error_message = "kubernetes_service_cidr must not overlap vpc_cidr."
    }
  }
}

resource "alicloud_vswitch" "this" {
  for_each = var.vswitches

  vpc_id       = alicloud_vpc.this.id
  zone_id      = each.value.zone_id
  cidr_block   = each.value.cidr_block
  vswitch_name = "${var.project_name}-vswitch-${each.key}"
  description  = "Shared ${each.key} vSwitch for ACS, ALB, and RDS."
  enable_ipv6  = false

  tags = merge(local.common_tags, {
    Component = "network"
    Zone      = each.value.zone_id
  })

  lifecycle {
    precondition {
      condition = contains(
        data.alicloud_alb_zones.available.ids,
        each.value.zone_id,
      )
      error_message = "The selected vSwitch zone is not supported by ALB."
    }
  }
}

resource "alicloud_security_group" "acs" {
  security_group_name = "${var.project_name}-acs"
  description         = "Security group for the shared ACS cluster."
  vpc_id              = alicloud_vpc.this.id
  security_group_type = "normal"
  inner_access_policy = "Accept"

  tags = merge(local.common_tags, {
    Component = "kubernetes"
  })
}

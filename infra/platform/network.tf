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

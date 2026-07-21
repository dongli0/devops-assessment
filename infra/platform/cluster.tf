resource "alicloud_cs_managed_kubernetes" "this" {
  name         = "${var.project_name}-acs"
  profile      = "Acs"
  cluster_spec = "ack.pro.small"
  version      = var.kubernetes_version

  vswitch_ids = [
    for key in sort(keys(alicloud_vswitch.this)) :
    alicloud_vswitch.this[key].id
  ]

  security_group_id = alicloud_security_group.acs.id
  service_cidr      = var.kubernetes_service_cidr
  cluster_domain    = "cluster.local"
  ip_stack          = "ipv4"
  timezone          = "Asia/Shanghai"

  new_nat_gateway                = false
  slb_internet_enabled           = var.cluster_api_public_access
  deletion_protection            = var.cluster_deletion_protection
  enable_rrsa                    = true
  skip_set_certificate_authority = true

  addons {
    name = "managed-coredns"
  }

  addons {
    name = "managed-metrics-server"
  }

  addons {
    name = "alb-ingress-controller"
    config = jsonencode({
      albIngress = {
        CreateDefaultALBConfig = false
      }
    })
  }

  tags = merge(local.common_tags, {
    Component = "kubernetes"
  })

  timeouts {
    create = "90m"
    update = "60m"
    delete = "60m"
  }
}

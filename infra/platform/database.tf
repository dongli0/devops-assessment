data "alicloud_db_zones" "postgresql_serverless" {
  engine                   = "PostgreSQL"
  engine_version           = "14.0"
  instance_charge_type     = "Serverless"
  category                 = "serverless_basic"
  db_instance_storage_type = "cloud_essd"
}

resource "random_password" "database" {
  for_each = local.environment_names

  length      = 24
  upper       = true
  lower       = true
  numeric     = true
  special     = false
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
}

resource "alicloud_db_instance" "postgresql" {
  engine                   = "PostgreSQL"
  engine_version           = "14.0"
  instance_type            = "pg.n2.serverless.1c"
  instance_storage         = 20
  instance_charge_type     = "Serverless"
  category                 = "serverless_basic"
  db_instance_storage_type = "cloud_essd"

  instance_name = "${var.project_name}-postgresql"
  zone_id       = var.vswitches["a"].zone_id
  vpc_id        = alicloud_vpc.this.id
  vswitch_id    = alicloud_vswitch.this["a"].id
  port          = "5432"
  db_time_zone  = "Asia/Shanghai"

  security_ips = toset([
    for config in values(var.vswitches) :
    config.cidr_block
  ])
  security_group_ids     = [alicloud_security_group.acs.id]
  whitelist_network_type = "VPC"
  modify_mode            = "Cover"

  deletion_protection = false

  serverless_config {
    min_capacity = 0.5
    max_capacity = 1
    auto_pause   = false
    switch_force = false
  }

  tags = merge(local.common_tags, {
    Component = "database"
  })

  lifecycle {
    precondition {
      condition = contains(
        data.alicloud_db_zones.postgresql_serverless.ids,
        var.vswitches["a"].zone_id,
      )
      error_message = "The selected zone does not support PostgreSQL 14 Serverless Basic."
    }
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

resource "alicloud_db_database" "environment" {
  for_each = local.environment_names

  instance_id    = alicloud_db_instance.postgresql.id
  data_base_name = "${var.project_name}_${each.key}"
  character_set  = "UTF8,C,en_US.utf8"
  description    = "Portfolio_${each.key}_database"
}

resource "alicloud_rds_account" "environment" {
  for_each = local.environment_names

  db_instance_id      = alicloud_db_instance.postgresql.id
  account_name        = "app_${each.key}"
  account_password    = random_password.database[each.key].result
  account_type        = "Normal"
  account_description = "Portfolio_${each.key}_application_account"
}

resource "alicloud_db_account_privilege" "environment" {
  for_each = local.environment_names

  instance_id  = alicloud_db_instance.postgresql.id
  account_name = alicloud_rds_account.environment[each.key].account_name
  privilege    = "DBOwner"
  db_names = [
    alicloud_db_database.environment[each.key].data_base_name,
  ]
}

locals {
  bootstrap_tags = {
    ManagedBy = "Terraform"
    Project   = var.project_name
    Stack     = "bootstrap"
  }
}

resource "alicloud_oss_bucket" "state" {
  bucket          = var.state_bucket_name
  storage_class   = "Standard"
  redundancy_type = "LRS"
  force_destroy   = false
  tags            = local.bootstrap_tags

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      versioning,
      server_side_encryption_rule,
    ]
  }
}

resource "alicloud_oss_bucket_acl" "state" {
  bucket = alicloud_oss_bucket.state.bucket
  acl    = "private"
}

resource "alicloud_oss_bucket_versioning" "state" {
  bucket = alicloud_oss_bucket.state.bucket
  status = "Enabled"
}

resource "alicloud_oss_bucket_server_side_encryption" "state" {
  bucket        = alicloud_oss_bucket.state.bucket
  sse_algorithm = "AES256"
}

resource "alicloud_ots_instance" "locks" {
  name               = var.lock_instance_name
  instance_type      = "Capacity"
  description        = "Terraform remote-state locking"
  network_type_acl   = ["INTERNET"]
  network_source_acl = ["TRUST_PROXY"]
  tags               = local.bootstrap_tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "alicloud_ots_table" "locks" {
  instance_name = alicloud_ots_instance.locks.name
  table_name    = var.lock_table_name
  time_to_live  = -1
  max_version   = 1
  allow_update  = true

  primary_key {
    name = "LockID"
    type = "String"
  }

  lifecycle {
    prevent_destroy = true
  }
}

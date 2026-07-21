terraform {
  required_version = ">= 1.14.0, < 1.15.0"

  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "= 1.285.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.9.0"
    }
  }
}

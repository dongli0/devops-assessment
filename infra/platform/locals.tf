locals {
  common_tags = {
    Environment = "shared"
    ManagedBy   = "Terraform"
    Project     = var.project_name
    Repository  = "dongli0/devops-assessment"
  }

  environment_names = toset([
    "dev",
    "test",
    "perf",
    "staging",
    "production",
  ])

  network_ranges = try({
    vpc = {
      first = sum([
        for index, octet in split(".", cidrhost(var.vpc_cidr, 0)) :
        tonumber(octet) * pow(256, 3 - index)
      ])
      last = sum([
        for index, octet in split(".", cidrhost(var.vpc_cidr, -1)) :
        tonumber(octet) * pow(256, 3 - index)
      ])
    }

    service = {
      first = sum([
        for index, octet in split(".", cidrhost(var.kubernetes_service_cidr, 0)) :
        tonumber(octet) * pow(256, 3 - index)
      ])
      last = sum([
        for index, octet in split(".", cidrhost(var.kubernetes_service_cidr, -1)) :
        tonumber(octet) * pow(256, 3 - index)
      ])
    }

    vswitches = {
      for key, config in var.vswitches : key => {
        first = sum([
          for index, octet in split(".", cidrhost(config.cidr_block, 0)) :
          tonumber(octet) * pow(256, 3 - index)
        ])
        last = sum([
          for index, octet in split(".", cidrhost(config.cidr_block, -1)) :
          tonumber(octet) * pow(256, 3 - index)
        ])
      }
    }
  }, null)
}

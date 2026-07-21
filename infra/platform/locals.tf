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
}

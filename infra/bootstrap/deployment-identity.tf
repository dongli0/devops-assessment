locals {
  service_deployment_identity_enabled = (
    var.deployment_cluster_id != null &&
    length(var.github_deploy_oidc_subjects) > 0
  )
}

resource "alicloud_ram_role" "github_deploy" {
  for_each = (
    local.service_deployment_identity_enabled ?
    var.github_deploy_oidc_subjects :
    tomap({})
  )

  role_name            = "${var.project_name}-github-deploy-${each.key}"
  max_session_duration = 3600

  assume_role_policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = alicloud_ims_oidc_provider.github.arn
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "oidc:iss" = [
              "https://token.actions.githubusercontent.com",
            ]
            "oidc:aud" = [
              "sts.aliyuncs.com",
            ]
            "oidc:sub" = [
              each.value,
            ]
          }
        }
      },
    ]
  })
}

resource "alicloud_ram_policy" "github_deploy" {
  count = local.service_deployment_identity_enabled ? 1 : 0

  policy_name = "${var.project_name}-github-service-deploy"

  rotate_strategy = "DeleteOldestNonDefaultVersionWhenLimitExceeded"

  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cs:GetClusters",
          "cs:DescribeClusterDetail",
          "cs:GetClusterAuditProject",
          "cs:DescribeResourcesDeleteProtection",
        ]
        Resource = [
          "acs:cs:${var.region}:${data.alicloud_account.current.id}:cluster/${var.deployment_cluster_id}",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cs:DescribeClusterUserKubeconfig",
        ]
        Resource = [
          "acs:cs:${var.region}:${data.alicloud_account.current.id}:cluster/${var.deployment_cluster_id}",
        ]
        Condition = {
          NumericEquals = {
            "cs:KubeConfigDurationMinutes" = "15"
          }
        }
      },
    ]
  })
}

resource "alicloud_ram_role_policy_attachment" "github_deploy" {
  for_each = alicloud_ram_role.github_deploy

  policy_name = alicloud_ram_policy.github_deploy[0].policy_name
  policy_type = alicloud_ram_policy.github_deploy[0].type
  role_name   = each.value.role_name
}

resource "alicloud_cs_kubernetes_permissions" "github_deploy" {
  for_each = alicloud_ram_role.github_deploy

  uid = each.value.role_id

  permissions {
    cluster     = var.deployment_cluster_id
    role_type   = "namespace"
    role_name   = "portfolio-service-deployer"
    namespace   = "portfolio-${each.key}"
    is_custom   = true
    is_ram_role = true
  }

  depends_on = [
    alicloud_ram_role_policy_attachment.github_deploy,
  ]
}

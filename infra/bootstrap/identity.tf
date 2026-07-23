data "alicloud_account" "current" {}

resource "alicloud_ims_oidc_provider" "github" {
  oidc_provider_name = coalesce(
    var.github_oidc_provider_name,
    "${var.project_name}-github-actions",
  )
  issuer_url          = "https://token.actions.githubusercontent.com"
  client_ids          = ["sts.aliyuncs.com"]
  fingerprints        = var.github_oidc_fingerprints
  issuance_limit_time = 12
  description         = "GitHub Actions OIDC for Terraform"
}

resource "alicloud_ram_role" "github" {
  role_name            = "${var.project_name}-github-terraform"
  max_session_duration = 3600

  assume_role_policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = [
            alicloud_ims_oidc_provider.github.arn,
          ]
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
            "oidc:sub" = sort(tolist(var.github_oidc_subjects))
          }
        }
      },
    ]
  })
}

resource "alicloud_ram_policy" "github_backend" {
  policy_name = "${var.project_name}-github-terraform-backend"

  rotate_strategy = "DeleteOldestNonDefaultVersionWhenLimitExceeded"

  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "oss:GetBucketInfo",
          "oss:ListObjects",
        ]
        Resource = [
          "acs:oss:*:*:${alicloud_oss_bucket.state.bucket}",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "oss:GetObject",
          "oss:PutObject",
          "oss:DeleteObject",
        ]
        Resource = [
          "acs:oss:*:*:${alicloud_oss_bucket.state.bucket}/devops-assessment/platform/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ots:DescribeTable",
          "ots:GetRow",
          "ots:PutRow",
          "ots:DeleteRow",
        ]
        Resource = [
          "acs:ots:${var.region}:${data.alicloud_account.current.id}:instance/${alicloud_ots_instance.locks.name}",
          "acs:ots:${var.region}:${data.alicloud_account.current.id}:instance/${alicloud_ots_instance.locks.name}/table/${alicloud_ots_table.locks.table_name}",
        ]
      },
    ]
  })
}

resource "alicloud_ram_role_policy_attachment" "github_backend" {
  policy_name = alicloud_ram_policy.github_backend.policy_name
  policy_type = alicloud_ram_policy.github_backend.type
  role_name   = alicloud_ram_role.github.role_name
}

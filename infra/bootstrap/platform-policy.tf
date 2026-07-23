resource "alicloud_ram_policy" "github_platform" {
  policy_name = "${var.project_name}-github-terraform-platform"

  rotate_strategy = "DeleteOldestNonDefaultVersionWhenLimitExceeded"

  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "vpc:CreateVpc",
          "vpc:DescribeVpcs",
          "vpc:DescribeVpcAttribute",
          "vpc:ModifyVpcAttribute",
          "vpc:DeleteVpc",
          "vpc:CreateVSwitch",
          "vpc:DescribeVSwitches",
          "vpc:DescribeVSwitchAttributes",
          "vpc:ModifyVSwitchAttribute",
          "vpc:DeleteVSwitch",
          "vpc:DescribeRouteTableList",
          "vpc:DescribeNatGateways",
          "vpc:ListTagResources",
          "vpc:TagResources",
          "vpc:UnTagResources",
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:CreateSecurityGroup",
          "ecs:DescribeSecurityGroups",
          "ecs:DescribeSecurityGroupAttribute",
          "ecs:ModifySecurityGroupAttribute",
          "ecs:ModifySecurityGroupPolicy",
          "ecs:DeleteSecurityGroup",
          "ecs:ListTagResources",
          "ecs:TagResources",
          "ecs:UntagResources",
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "alb:DescribeZones",
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "cs:CreateCluster",
          "cs:DescribeTask",
          "cs:DescribeTaskInfo",
          "cs:DescribeCluster",
          "cs:DescribeClusterDetail",
          "cs:DescribeClusterResources",
          "cs:CheckControlPlaneLogEnable",
          "cs:GetClusterAuditProject",
          "cs:ModifyCluster",
          "cs:ModifyClusterTags",
          "cs:UpgradeCluster",
          "cs:CancelTask",
          "cs:DeleteCluster",
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeRegions",
          "rds:DescribeAvailableZones",
          "rds:CreateDBInstance",
          "rds:DescribeDBInstances",
          "rds:DescribeDBInstanceAttribute",
          "rds:DescribeDBInstanceNetInfo",
          "rds:DescribeDBInstanceIPArrayList",
          "rds:DescribeSecurityGroupConfiguration",
          "rds:DescribeTags",
          "rds:DescribeDBInstanceMonitor",
          "rds:DescribeSQLCollectorPolicy",
          "rds:DescribeSQLCollectorRetention",
          "rds:DescribeDBInstanceEncryptionKey",
          "rds:DescribeDBInstanceHAConfig",
          "rds:DescribeDBInstanceSSL",
          "rds:DescribeDBInstanceTDE",
          "rds:DescribeHASwitchConfig",
          "rds:DescribeHADiagnoseConfig",
          "rds:DescribeParameters",
          "rds:DescribePGHbaConfig",
          "rds:DescribeInstanceLinkedWhitelistTemplate",
          "rds:ModifyDBInstanceDescription",
          "rds:ModifyDBInstanceConnectionString",
          "rds:ModifyDBInstanceDeletionProtection",
          "rds:ModifyDBInstanceSpec",
          "rds:ModifySecurityIps",
          "rds:ModifySecurityGroupConfiguration",
          "rds:DeleteDBInstance",
          "rds:ListTagResources",
          "rds:TagResources",
          "rds:UntagResources",
          "rds:CreateDatabase",
          "rds:DescribeDatabases",
          "rds:ModifyDBDescription",
          "rds:DeleteDatabase",
          "rds:CreateAccount",
          "rds:DescribeAccounts",
          "rds:ModifyAccountDescription",
          "rds:ResetAccountPassword",
          "rds:DeleteAccount",
          "rds:GrantAccountPrivilege",
          "rds:RevokeAccountPrivilege",
        ]
        Resource = ["*"]
      },
    ]
  })
}

resource "alicloud_ram_role_policy_attachment" "github_platform" {
  policy_name = alicloud_ram_policy.github_platform.policy_name
  policy_type = alicloud_ram_policy.github_platform.type
  role_name   = alicloud_ram_role.github.role_name
}

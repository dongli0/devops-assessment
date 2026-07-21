# Terraform Bootstrap

## Purpose

This Terraform root creates the resources required before the main platform stack can use remote state and GitHub Actions authentication.

It manages:

- One private OSS bucket for Terraform state
- OSS versioning and AES256 server-side encryption
- One Tablestore Capacity instance and lock table
- One GitHub Actions OIDC provider
- One RAM role with an exact OIDC trust policy
- One least-privilege policy for the platform state and lock table
- One action-scoped policy for the current VPC, Security Group, ALB discovery, ACS, and RDS Terraform lifecycle

It does not create the VPC, ACS cluster, RDS instance, ALB, or application workloads.

## Security Model

- No Alibaba Cloud AccessKey is stored in Git, Terraform variables, or GitHub.
- Initial local authentication uses an interactive Alibaba Cloud CLI OAuth profile.
- GitHub Actions later exchanges its OIDC token for temporary STS credentials.
- OIDC subjects must be exact values and cannot contain wildcards.
- Backend access and platform lifecycle access are managed by separate custom RAM policies.
- No administrator, product FullAccess, billing, or general RAM permissions are attached to the GitHub role.
- Some create and list APIs require `Resource = "*"`, so access is constrained through an explicit action allowlist and exact OIDC subjects.
- ACS default and service-linked roles must be authorized interactively before the platform pipeline runs.
- The initial bootstrap state is local because the remote backend does not exist yet.
- The OSS bucket and Tablestore resources use `prevent_destroy`.

## Platform Deployment Policy

The platform policy is defined in `platform-policy.tf` and covers only the current Terraform lifecycle:

- VPC and vSwitch management
- ECS Security Group management
- ALB availability-zone discovery
- ACS cluster lifecycle management
- RDS instance, database, account, and privilege management

The ALB lifecycle is not granted directly to the GitHub role. The ALB ingress controller and the Alibaba Cloud service roles manage the shared ALB after the cluster is created.

When the platform stack or Alicloud provider changes, review `AccessDenied` errors and update the explicit action allowlist. Do not resolve missing permissions by attaching administrator or product FullAccess policies.

## Code-Only Validation

From the repository root, validate both Terraform stacks with:

```bash
./scripts/validate-terraform.sh
```

The script:

- checks Terraform formatting;
- validates both provider lock files;
- prevents generated or sensitive Terraform files from being tracked;
- initializes each stack with `-backend=false`;
- uses temporary `TF_DATA_DIR` directories;
- validates the bootstrap and platform configurations.

Provider initialization may access the configured Terraform registry mirror, but it does not initialize the OSS backend or query Alibaba Cloud resource APIs.

To reuse already installed providers without registry access:

```bash
TERRAFORM_OFFLINE=1 \
  ./scripts/validate-terraform.sh
```

For targeted bootstrap troubleshooting:

```bash
terraform -chdir=infra/bootstrap init -backend=false
terraform -chdir=infra/bootstrap fmt -check
terraform -chdir=infra/bootstrap validate
```

## Required Inputs

Copy the example file only when preparing a real plan:

```bash
cp \
  infra/bootstrap/terraform.tfvars.example \
  infra/bootstrap/terraform.tfvars

chmod 600 infra/bootstrap/terraform.tfvars
```

Configure:

- `state_bucket_name`: globally unique OSS bucket name
- `lock_instance_name`: unique Tablestore instance name with 3-16 characters
- `github_oidc_fingerprints`: current GitHub OIDC HTTPS CA fingerprints
- `github_oidc_subjects`: exact subject claims permitted to assume the role

The real `terraform.tfvars` file is ignored by Git.

## GitHub OIDC Fingerprint

Use the Alibaba Cloud RAM console fingerprint retrieval function with this issuer:

```text
https://token.actions.githubusercontent.com
```

Copy the returned SHA-1 fingerprint into `github_oidc_fingerprints`, then cancel the console operation. Terraform remains the owner of the OIDC provider.

Do not permanently hard-code an unverified fingerprint copied from a blog or old example. During certificate rotation, add the new fingerprint before removing the old one.

## GitHub OIDC Subject

Do not guess the subject claim.

A diagnostic GitHub Actions workflow with `id-token: write` will be added with the pipeline code. It will print only selected claims such as `iss`, `aud`, and `sub`, never the complete token.

Depending on the repository configuration, the subject may resemble either:

```text
repo:OWNER/REPOSITORY:ref:refs/heads/main
```

or an immutable subject containing numeric owner and repository IDs.

Copy only the actual value returned by GitHub into `github_oidc_subjects`.

## Interactive OAuth Authentication

Create an interactive profile without a long-lived AccessKey:

```bash
aliyun configure \
  --mode OAuth \
  --profile terraform-bootstrap
```

Use it for the current shell:

```bash
export ALIBABA_CLOUD_PROFILE="terraform-bootstrap"
export ALIBABA_CLOUD_REGION="cn-shanghai"
```

Verify the identity before planning:

```bash
aliyun sts GetCallerIdentity \
  --profile terraform-bootstrap
```

Do not commit the Alibaba Cloud CLI configuration or OAuth tokens.

## Review the Bootstrap Plan

The following commands access Alibaba Cloud APIs but do not create resources:

```bash
terraform -chdir=infra/bootstrap plan \
  -out=bootstrap.tfplan

terraform -chdir=infra/bootstrap show \
  bootstrap.tfplan
```

Review every resource, region, bucket name, OIDC condition, and RAM action before applying.

## Cost and Mutation Boundary

The following command creates cloud resources and may incur charges:

```bash
terraform -chdir=infra/bootstrap apply \
  bootstrap.tfplan
```

Do not run it during code-only validation. Run it only after the plan and account identity have been reviewed.

## Configure the Platform Backend

After a successful bootstrap apply, obtain the generated values:

```bash
terraform -chdir=infra/bootstrap output
```

Copy the platform backend template:

```bash
cp \
  infra/platform/backend.hcl.example \
  infra/platform/backend.hcl
```

Set these values from the bootstrap outputs:

- `bucket`
- `tablestore_endpoint`
- `tablestore_table`

Keep these fixed values:

```hcl
prefix = "devops-assessment/platform"
key    = "terraform.tfstate"
region = "cn-shanghai"
```

Initialize the platform stack:

```bash
terraform -chdir=infra/platform init \
  -reconfigure \
  -backend-config=backend.hcl

terraform -chdir=infra/platform validate
```

The real `backend.hcl` file is ignored by Git.

## GitHub Repository Configuration

After bootstrap, record these outputs as GitHub repository or environment variables:

- `github_oidc_provider_arn` as `ALIBABA_CLOUD_OIDC_PROVIDER_ARN`
- `github_terraform_role_arn` as `ALIBABA_CLOUD_ROLE_ARN`
- Region as `ALIBABA_CLOUD_REGION`

No Alibaba Cloud AccessKey should be added to GitHub.

The ACR Personal Edition registry password is a separate product limitation and will be stored only as a protected GitHub Environment secret.

## State Protection and Recovery

Do not delete the local bootstrap state after apply. Keep an encrypted backup until its controlled migration to remote state is complete.

Do not attempt to destroy bootstrap resources before the platform stack has been destroyed and its final state has been backed up.

A final bootstrap teardown requires:

1. Destroying the platform resources.
2. Backing up the final state.
3. Reviewing removal of `prevent_destroy`.
4. Emptying every current and historical OSS object version.
5. Destroying the bootstrap resources with a reviewed plan.

Never enable `force_destroy` merely to bypass a failed deletion.

## Current Status

- Terraform configuration: validated
- Alibaba Cloud resources: not yet planned or applied
- GitHub OIDC claim inspection workflow: pending
- Platform deployment policy: implemented and locally validated; not applied
- ACR Personal Edition initialization: pending

## References

- [Terraform OSS backend](https://developer.hashicorp.com/terraform/language/backend/oss)
- [Alibaba Cloud Terraform authentication](https://help.aliyun.com/en/terraform/terraform-authentication)
- [Alibaba Cloud OIDC provider management](https://help.aliyun.com/en/ram/manage-an-oidc-idp)
- [GitHub Actions OIDC claims](https://docs.github.com/en/actions/reference/security/oidc)

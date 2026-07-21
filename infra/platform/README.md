# Terraform Platform

## Purpose

This Terraform root provisions the shared Alibaba Cloud platform used by all five application environments:

- dev
- test
- perf
- staging
- production

The environments are logically isolated in Kubernetes and PostgreSQL while sharing the network, ACS cluster, ALB, and RDS instance to stay within the assessment budget.

## Managed Resources

| Component | Implementation |
|---|---|
| Network | One VPC and two vSwitches in distinct availability zones |
| Security | One normal ECS Security Group |
| Kubernetes | One ACS cluster without worker nodes |
| Cluster add-ons | CoreDNS, Metrics Server, and ALB Ingress Controller |
| Database | One PostgreSQL 14 Serverless Basic RDS instance |
| Isolation | One database and application account per environment |
| Credentials | Randomly generated database password per environment |

The platform intentionally does not manage:

- Terraform backend and GitHub OIDC bootstrap resources
- A public RDS endpoint
- NAT Gateway
- Application OSS bucket
- Redis
- ACR Personal Edition initialization
- Kubernetes application workloads
- The shared ALB directly

The ALB Ingress Controller creates and manages the public ALB from the repository-owned `AlbConfig`.

## Design Decisions

- Region: `cn-shanghai`
- Shared infrastructure with logical environment isolation
- Two vSwitches in separate ALB-supported zones
- ACS profile with no worker nodes
- No automatically created NAT Gateway
- Public Kubernetes API enabled for GitHub-hosted deployment runners
- Terraform preconditions enforce vSwitch containment and CIDR non-overlap
- RDS reachable only through the VPC
- RDS network access permits the two platform vSwitch CIDRs and the ACS Security Group
- Five separate databases and accounts on one RDS instance
- No unused RRSA or application object-storage configuration
- Deletion protection disabled only to support controlled assessment teardown

RDS IP whitelists and Security Groups are independent network authorization paths, not an intersection. Workloads within an allowed vSwitch CIDR can attempt a connection, but each environment still requires its own database credentials. This shared-VPC boundary is accepted for the cost-optimized assessment topology.

This is a cost-optimized assessment topology, not a production reference architecture.

## Prerequisites

Before planning this stack:

1. Activate the required Alibaba Cloud services.
2. Complete the ACS default-role authorization using the Alibaba Cloud account.
3. Authorize the RDS PostgreSQL service-linked role `AliyunServiceRoleForRdsPgsqlOnEcs` using the Alibaba Cloud account.
4. Apply the `infra/bootstrap` stack.
5. Configure the OSS remote backend.
6. Authenticate using either the local OAuth profile or the GitHub OIDC role.
7. Select two distinct zones supported by both ALB and PostgreSQL Serverless Basic.

Do not grant GitHub Actions administrator, product FullAccess, billing, or general RAM permissions.

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

For targeted platform troubleshooting:

```bash
terraform -chdir=infra/platform init -backend=false
terraform -chdir=infra/platform fmt -check
terraform -chdir=infra/platform validate
```

## Configure Remote State

After applying `infra/bootstrap`, copy the backend template:

```bash
cp \
  infra/platform/backend.hcl.example \
  infra/platform/backend.hcl

chmod 600 infra/platform/backend.hcl
```

Set the following values from the bootstrap outputs:

- `bucket`
- `tablestore_endpoint`
- `tablestore_table`

Keep the platform prefix and key unchanged:

```hcl
prefix = "devops-assessment/platform"
key    = "terraform.tfstate"
```

Initialize the remote backend:

```bash
terraform -chdir=infra/platform init \
  -reconfigure \
  -backend-config=backend.hcl
```

The real `backend.hcl` file is ignored by Git.

## Configure Platform Inputs

Copy the example variables file:

```bash
cp \
  infra/platform/terraform.tfvars.example \
  infra/platform/terraform.tfvars

chmod 600 infra/platform/terraform.tfvars
```

Configure two distinct vSwitch zones and CIDR blocks.

Terraform preconditions enforce that:

- both vSwitch CIDRs are fully contained within the VPC CIDR;
- the two vSwitch CIDRs do not overlap;
- the Kubernetes Service CIDR does not overlap the VPC CIDR.

Before planning, manually verify that:

- both zones belong to `cn-shanghai`;
- both zones support ALB;
- the selected RDS zone currently supports PostgreSQL 14 Serverless Basic and the configured `pg.n2.serverless.1c` class.

A null `kubernetes_version` lets Alibaba Cloud select the current supported version during initial creation. Pin the resulting version before future upgrades.

The real `terraform.tfvars` file is ignored by Git.

## Review the Plan

The following commands query Alibaba Cloud and remote state but do not create platform resources:

```bash
terraform -chdir=infra/platform plan \
  -out=platform.tfplan

terraform -chdir=infra/platform show \
  platform.tfplan
```

Review:

- caller identity and region;
- selected zones and CIDRs;
- absence of a NAT Gateway and public RDS endpoint;
- ACS profile and add-ons;
- RDS Serverless capacity and storage;
- five database and account resources;
- deletion-protection settings;
- all unexpected replacements or deletions.

The generated plan file is ignored by Git.

## Cost and Mutation Boundary

The following command creates billable Alibaba Cloud resources:

```bash
terraform -chdir=infra/platform apply \
  platform.tfplan
```

Do not run it during code-only validation. Apply only a saved and reviewed plan.

The main cost-bearing resources are:

- ACS control plane and serverless pod execution
- RDS PostgreSQL Serverless
- Public ALB created later by the ALB Ingress Controller
- Network traffic and related usage

All resources must be destroyed after the assessment validation window.

## Outputs

Non-sensitive outputs include:

- VPC and vSwitch IDs
- ALB vSwitch IDs
- Security Group ID
- ACS cluster ID, name, version, and API endpoints
- RDS instance ID and private endpoint
- Database and account names

`database_urls` is sensitive. It contains generated database credentials and is stored in encrypted Terraform remote state.

Never print sensitive outputs in CI logs, screenshots, pull requests, or email. The deployment pipeline must transfer them directly into namespace-local Kubernetes Secrets with log masking enabled.

## Kubernetes Handoff

After Terraform apply:

1. Use `alb_vswitch_ids` to render the shared `AlbConfig`.
2. Initialize the ACR Personal namespace and repositories manually.
3. Create the namespace-local ACR pull Secret.
4. Create the namespace-local database Secret from the matching sensitive database URL.
5. Run the migration Job.
6. Deploy the requested Kustomize overlay.
7. Wait for rollouts and execute smoke tests.

See the [Kubernetes deployment guide](../../deploy/README.md) for the complete deployment order.

## Controlled Teardown

Before destroying the platform:

1. Remove application Ingress resources.
2. Remove the shared `AlbConfig`.
3. Wait until the controller deletes the public ALB.
4. Back up or explicitly discard contact-message data.
5. Review a saved destroy plan.
6. Destroy the platform stack.
7. Verify that no billable ACS, RDS, ALB, or related resources remain.
8. Remove manually managed ACR resources if they are no longer needed.
9. Destroy the bootstrap stack only after platform state is no longer required.

The ACS `delete_options` configuration deletes controller-created ALB resources as a final teardown safeguard. It does not replace removing the Ingress and `AlbConfig` resources first and waiting for controller cleanup.

Create and inspect the destroy plan with:

```bash
terraform -chdir=infra/platform plan \
  -destroy \
  -out=platform-destroy.tfplan

terraform -chdir=infra/platform show \
  platform-destroy.tfplan
```

Do not apply a destroy plan without reviewing its exact targets.

## Current Status

- Terraform formatting: validated
- Terraform configuration: validated
- Alibaba Cloud platform plan: not yet created
- Alibaba Cloud platform resources: not yet applied
- Remote backend: not yet initialized
- ACR Personal Edition: not yet initialized

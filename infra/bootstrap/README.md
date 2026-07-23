# Terraform Bootstrap

## Purpose

This Terraform root creates the resources required before the main platform stack can use remote state and GitHub Actions authentication.

It manages:

- One private OSS bucket for Terraform state
- OSS versioning and AES256 server-side encryption
- One Tablestore Capacity instance and lock table
- One GitHub Actions OIDC provider
- One platform Terraform RAM role with an exact OIDC trust policy
- Five optional environment-specific service deployment RAM roles
- One least-privilege policy for the platform state and lock table
- One action-scoped policy for the current VPC, Security Group, ALB discovery, ACS, and RDS Terraform lifecycle
- Namespace-scoped ACS permission assignments for the service deployment roles

It does not create the VPC, ACS cluster, RDS instance, ALB, or application workloads.

## Security Model

- No Alibaba Cloud AccessKey is stored in Git, Terraform variables, or GitHub.
- Initial local authentication uses an interactive Alibaba Cloud CLI OAuth profile.
- GitHub Actions later exchanges its OIDC token for temporary STS credentials.
- OIDC subjects must be exact values and cannot contain wildcards.
- Backend access and platform lifecycle access are managed by separate custom RAM policies.
- Service delivery uses one RAM role per environment so that a non-production workflow cannot assume the production role.
- Each service deployment role receives a 15-minute kubeconfig and access to exactly one Kubernetes namespace.
- No administrator, product FullAccess, billing, general RAM, or `cluster-admin` permissions are attached to any GitHub role.
- Some create and list APIs require `Resource = "*"`, so access is constrained through an explicit action allowlist and exact OIDC subjects.
- ACS default and service-linked roles must be authorized interactively before the platform pipeline runs.
- RDS PostgreSQL Serverless requires the account-level `AliyunServiceRoleForRdsPgsqlOnEcs` and `AliyunServiceRoleForRDSProxyOnEcs` service-linked roles before the platform pipeline runs.
- The bootstrap caller must be authorized to manage ACS user permissions; that capability is never delegated to service workflows.
- The initial bootstrap state is local because the remote backend does not exist yet.
- The OSS bucket and Tablestore resources use `prevent_destroy`.

## Account and Product Prerequisites

Before running the first mutating bootstrap operation:

- complete Alibaba Cloud account verification and billing setup;
- confirm that the account has no overdue balance or security restriction;
- activate OSS and Tablestore in the Alibaba Cloud account;
- use a RAM administrator only for the initial bootstrap operation; and
- verify the target account and region with `GetCallerIdentity`.

An OSS `UserDisable` response or a Tablestore `OTSAuthFailed: The user is
disabled` response is an account or product activation problem. Adding more
RAM permissions does not resolve it. Stop the apply, preserve the local state,
and resolve the account status before creating another plan.

Do not create the state bucket or lock table manually after Terraform has
started managing the bootstrap stack. A failed apply can still create and
record some resources successfully.

## Platform Deployment Policy

The platform policy is defined in `platform-policy.tf` and covers only the current Terraform lifecycle:

- VPC and vSwitch management
- ECS Security Group management
- ALB availability-zone discovery
- ACS cluster lifecycle management
- RDS instance, database, account, and privilege management

The ALB lifecycle is not granted directly to the GitHub role. The ALB ingress controller and the Alibaba Cloud service roles manage the shared ALB after the cluster is created.

When the platform stack or Alicloud provider changes, review `AccessDenied` errors and update the explicit action allowlist. Do not resolve missing permissions by attaching administrator or product FullAccess policies.

## Service Deployment Identities

Service deployment identities are enabled only after the ACS cluster and its
platform-owned Kubernetes access resources exist.

`github_deploy_oidc_subjects` must contain exactly these five keys:

| Key          | RAM role suffix            | Authorized namespace   |
| ------------ | -------------------------- | ---------------------- |
| `dev`        | `github-deploy-dev`        | `portfolio-dev`        |
| `test`       | `github-deploy-test`       | `portfolio-test`       |
| `perf`       | `github-deploy-perf`       | `portfolio-perf`       |
| `staging`    | `github-deploy-staging`    | `portfolio-staging`    |
| `production` | `github-deploy-production` | `portfolio-production` |

Terraform creates one RAM role per entry. Each trust policy accepts only the
exact OIDC subject of its matching protected GitHub Environment. Wildcards and
branch-only subjects are rejected for these roles.

The shared RAM policy allows only the cluster reads needed to obtain a
15-minute kubeconfig. `alicloud_cs_kubernetes_permissions` assigns the custom
`portfolio-service-deployer` role to exactly one namespace for each RAM role.
The service roles cannot create namespaces or deploy across environments.

The custom role and namespaces are owned by
[`deploy/platform/service-access`](../../deploy/platform/service-access). Apply
that Kustomization with platform or cluster-administrator credentials before
enabling the Terraform service deployment identities. The service delivery
pipeline must never apply these platform resources itself.

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

For the initial bootstrap apply, configure:

- `state_bucket_name`: globally unique OSS bucket name
- `lock_instance_name`: unique Tablestore instance name with 3-16 characters
- `github_oidc_fingerprints`: current GitHub OIDC HTTPS CA fingerprints
- `github_oidc_subjects`: exact subject claims permitted to assume the platform Terraform role
- `github_oidc_provider_name`: optional exact name of an existing account-wide GitHub OIDC provider to adopt

Leave `deployment_cluster_id` as `null` and
`github_deploy_oidc_subjects` empty during the initial bootstrap apply.

Leave `github_oidc_provider_name` as `null` when Terraform will create the
provider. Set it only after verifying and importing an existing provider as
described below.

After the platform cluster and service-access resources exist, configure both
of these inputs together:

- `deployment_cluster_id`: ACS cluster ID returned by the platform stack
- `github_deploy_oidc_subjects`: exact OIDC subject for each of the five protected GitHub Environments

The real `terraform.tfvars` file is ignored by Git.

## GitHub OIDC Fingerprint

Use the Alibaba Cloud RAM console fingerprint retrieval function with this issuer:

```text
https://token.actions.githubusercontent.com
```

Copy the returned SHA-1 fingerprint into `github_oidc_fingerprints`. If the
account does not already contain a provider for this issuer, cancel the console
operation and let Terraform create it. If a provider already exists, do not
attempt to create another one; verify and adopt it as described below.

Do not permanently hard-code an unverified fingerprint copied from a blog or old example. During certificate rotation, add the new fingerprint before removing the old one.

## Adopt an Existing GitHub OIDC Provider

An OIDC issuer URL must be unique within one Alibaba Cloud account. Before the
first plan, list account-wide providers and check for the GitHub issuer:

```bash
aliyun ims ListOIDCProviders \
  --MaxItems 100 \
  --profile terraform-bootstrap
```

If a matching provider exists, verify all of these values before adopting it:

- issuer URL: `https://token.actions.githubusercontent.com`
- client ID: `sts.aliyuncs.com`
- every configured SHA-1 fingerprint
- the exact case-sensitive provider name

Do not delete an existing provider to resolve
`EntityAlreadyExists.OIDCProvider.Url`. Other RAM roles may already trust its
ARN.

Set the verified name only in the ignored `terraform.tfvars` file:

```hcl
github_oidc_provider_name = "EXISTING_PROVIDER_NAME"
```

The provider name and issuer URL are replacement fields. The configuration
must therefore match the existing name before import. Back up the local state,
then import the provider by its exact name:

```bash
if [[ -f infra/bootstrap/terraform.tfstate ]]; then
  cp --preserve=mode,timestamps \
    infra/bootstrap/terraform.tfstate \
    infra/bootstrap/terraform.tfstate.pre-oidc-import

  chmod 600 \
    infra/bootstrap/terraform.tfstate \
    infra/bootstrap/terraform.tfstate.pre-oidc-import
fi

terraform -chdir=infra/bootstrap import \
  -input=false \
  -var-file=terraform.tfvars \
  alicloud_ims_oidc_provider.github \
  EXISTING_PROVIDER_NAME
```

After import, review a fresh plan. It may contain an in-place update for
mutable metadata, but it must not replace the OIDC provider.

## GitHub OIDC Subject

Do not guess the subject claim.

The manually triggered `.github/workflows/oidc-claims.yaml` workflow requests a
GitHub OIDC token for one protected environment and displays only the `iss`,
`aud`, and `sub` claims in the workflow summary. It never prints or preserves
the complete token.

Create and protect the `infra-plan`, `infra-apply`, `dev`, `test`, `perf`,
`staging`, and `production` GitHub Environments before running it. Run the
workflow once for each environment.

Copy the `infra-plan` and `infra-apply` subjects into
`github_oidc_subjects`. Copy each service environment subject into the
matching `github_deploy_oidc_subjects` entry.

Configure every Environment to allow deployments only from `main`. Require
manual approval for `infra-apply`, `staging`, and `production`. These controls
are required because an environment-based OIDC subject identifies the
Environment, not the source branch that requested it.

Each reported subject must end with `:environment:ENVIRONMENT_NAME`. The
owner and repository portion may use names or immutable numeric IDs depending
on the repository's OIDC claim customization.

Copy only actual values returned by GitHub. Put both infrastructure workflow
subjects in `github_oidc_subjects`. Put each service workflow subject in the
matching key of `github_deploy_oidc_subjects`; for example, the `dev` value
must end in `:environment:dev`.

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

## Finalize Service Deployment Access

The bootstrap root is intentionally applied in two phases:

1. Apply bootstrap without the optional service deployment inputs.
2. Apply the platform stack and obtain its `cluster_id` output.
3. With platform or cluster-administrator credentials, apply
   `deploy/platform/service-access` to create the five namespaces and the
   custom `portfolio-service-deployer` ClusterRole.
4. Record the exact OIDC subject emitted for each protected GitHub Environment.
5. Set `deployment_cluster_id` and all five entries in
   `github_deploy_oidc_subjects`.
6. Review and apply a second bootstrap plan to create the five RAM roles and
   their namespace-scoped ACS permission assignments.

Do not run the second apply before the custom Kubernetes role exists. Do not
replace the custom role with `cluster-admin` to bypass an authorization error.

## GitHub Repository Configuration

After bootstrap, record these outputs as GitHub repository or environment variables:

- `github_oidc_provider_arn` as `ALIBABA_CLOUD_OIDC_PROVIDER_ARN`
- `github_terraform_role_arn` as `ALIBABA_CLOUD_ROLE_ARN`
- `state_bucket_name` as `TERRAFORM_STATE_BUCKET`
- `tablestore_endpoint` as `TERRAFORM_STATE_TABLESTORE_ENDPOINT`
- `lock_table_name` as `TERRAFORM_STATE_TABLESTORE_TABLE`
- Each entry of `github_deploy_role_arns` as `ALIBABA_CLOUD_DEPLOY_ROLE_ARN` in its matching protected GitHub Environment
- Region as `ALIBABA_CLOUD_REGION`

No Alibaba Cloud AccessKey should be added to GitHub.

See the
[Infrastructure Pipeline Design](../../docs/infra-pipeline-design.md) for the
complete Environment, variable, encrypted-plan secret, and first-run
configuration.

The ACR Personal Edition registry password is a separate product limitation and will be stored only as a protected GitHub Environment secret.

## State Protection and Recovery

Do not delete the local bootstrap state after apply. Keep an encrypted backup until its controlled migration to remote state is complete.

Terraform apply is not transactional. If one resource fails, other resources
may already have been created and recorded in state. After a partial apply:

1. stop and preserve the current state;
2. use `terraform state list` to identify successful resources;
3. inspect each conflict before importing or changing configuration;
4. resolve account activation and billing errors outside Terraform; and
5. generate and review a new saved plan against the updated state.

Do not reapply the previous saved plan after the state serial changes.
Do not remove resources from state merely to make the next plan appear clean.

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
- Bootstrap rollout: recovery in progress after a partial initial apply; the existing GitHub OIDC provider is imported into local state
- Bootstrap resources already managed: Tablestore lock instance, platform RAM policy, and GitHub OIDC provider
- Remaining bootstrap resources: pending a fresh reviewed recovery plan
- GitHub OIDC claim inspection workflow: run for `infra-plan` and `infra-apply`; service environment claims are pending
- Platform deployment policy: implemented and locally validated; not applied
- Environment-specific service deployment roles: implemented and locally validated; not applied
- Namespace-scoped ACS permission assignments: implemented and locally validated; not applied
- Platform-owned namespaces and custom deployment role: implemented as Kubernetes manifests; not applied
- ACR Personal Edition initialization: pending

## References

- [Terraform OSS backend](https://developer.hashicorp.com/terraform/language/backend/oss)
- [Alibaba Cloud Terraform authentication](https://help.aliyun.com/en/terraform/terraform-authentication)
- [Alibaba Cloud OIDC provider management](https://help.aliyun.com/en/ram/manage-an-oidc-idp)
- [GitHub Actions OIDC claims](https://docs.github.com/en/actions/reference/security/oidc)

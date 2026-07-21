# Kubernetes Deployment

These manifests deploy the portfolio web application and API to five logical
environments in one Alibaba Cloud Container Compute Service (ACS) cluster.

The shared-cluster design is intentional for the assessment budget. Production
systems should normally use stronger account, cluster, and data-plane isolation.

## Layout

```text
deploy/
|-- base/                         # Cloud-neutral API and Web workloads
|-- jobs/
|   `-- migration/                # One-shot Alembic Job template
|-- overlays/
|   |-- dev/
|   |-- test/
|   |-- perf/
|   |-- staging/
|   `-- production/
`-- platform/
    `-- alicloud-alb/
        |-- cluster/              # Shared AlbConfig and IngressClass
        `-- ingress/              # Reusable namespaced Ingress template
```

## Environment Policy

| Environment | Namespace              | API replicas | Web replicas | HPA         | PDB         |
| ----------- | ---------------------- | -----------: | -----------: | ----------- | ----------- |
| dev         | `portfolio-dev`        |            1 |            1 | None        | None        |
| test        | `portfolio-test`       |            1 |            1 | None        | None        |
| perf        | `portfolio-perf`       |          2-4 |            2 | API         | None        |
| staging     | `portfolio-staging`    |          2-4 |            2 | API         | API and Web |
| production  | `portfolio-production` |          2-6 |          2-4 | API and Web | API and Web |

HPA uses CPU utilization and requires Metrics Server. Resource requests are
defined for every container so that utilization can be calculated.

## Routing

All environments share one ALB but use separate namespaces and Ingress
resources.

| Public path          | Backend              |
| -------------------- | -------------------- |
| `/<environment>/api` | `portfolio-api:8000` |
| `/<environment>`     | `portfolio-web:8080` |

Paths are forwarded without rewriting because both applications understand the
environment prefix.

## Image Contract

The base uses logical image names:

- `portfolio-api:0.1.0`
- `portfolio-web:0.1.0`

The delivery pipeline must replace both names with immutable ACR image digests.
Mutable tags such as `latest` must not be deployed.

The migration Job must use exactly the same API image digest as the API
Deployment being released.

## Registry Secret Contract

Every environment namespace must contain a private-registry Secret with this
interface:

| Field           | Value                                                  |
| --------------- | ------------------------------------------------------ |
| Secret name     | `portfolio-acr-pull`                                   |
| Type            | `kubernetes.io/dockerconfigjson`                       |
| Key             | `.dockerconfigjson`                                    |
| Registry server | Exact host used by the deployed ACR Personal image URI |

ACR Personal instances created on or after September 9, 2024 do not support the
credential helper or the `GetAuthorizationToken` API. The delivery pipeline
therefore creates this namespace-scoped Secret from protected GitHub
Environment credentials belonging to a read-only RAM user.

The fixed registry password and rendered Secret must never enter Git. The
registry server must exactly match the image host, such as
`crpi-example.cn-shanghai.personal.cr.aliyuncs.com`.

See the
[ACR Personal documentation](https://help.aliyun.com/en/acr/user-guide/use-a-container-registry-personal-edition-instance-to-push-and-pull-images)
for the current authentication limitations.

## Database Secret Contract

Every environment namespace must contain a Secret with this interface:

| Field        | Value                                                           |
| ------------ | --------------------------------------------------------------- |
| Secret name  | `portfolio-database`                                            |
| Key          | `database-url`                                                  |
| Value format | `postgresql+asyncpg://<user>:<password>@<host>:5432/<database>` |

The Secret value is supplied by the deployment pipeline from protected
environment credentials. No Secret value, rendered Secret manifest, or
database password is committed to Git.

The API Deployment and migration Job both consume this interface. A production
reference implementation should use separate runtime and migration database
roles; this assessment uses one account to keep the platform small.

## Workload Security

The workloads apply the following defaults:

- non-root fixed UIDs;
- read-only root filesystems;
- all Linux capabilities dropped;
- privilege escalation disabled;
- `RuntimeDefault` seccomp;
- ServiceAccount token automount disabled;
- explicit CPU and memory requests and limits;
- restricted Pod Security labels on every namespace;
- writable temporary data limited to an `emptyDir` volume.

## Shared ALB

Terraform provisions the VPC, two cross-zone vSwitches, and ACS cluster. The ALB
Ingress Controller owns the ALB instance and listener through `AlbConfig`.

The controller must be installed in **Do not create** mode so that its installer
does not create a second public ALB. The repository-owned `alb-shared` AlbConfig
is the only component allowed to create the assessment ALB.

The pipeline passes two vSwitch IDs and their zones from Terraform outputs to
`scripts/render-alb-config.sh`. The renderer rejects missing or malformed IDs,
duplicate IDs, same-zone mappings, and unresolved placeholders. The cluster
Kustomization intentionally contains only the `IngressClass`; the rendered
AlbConfig must be applied explicitly first.

See the
[shared ALB runbook](platform/alicloud-alb/cluster/README.md)
for rendering, validation, apply order, and teardown instructions.

Only HTTP is configured for the short-lived assessment endpoint. A long-lived
public service must add an HTTPS listener and managed certificate before
production use.

## Validation

Run all local Kubernetes checks without contacting a cluster:

```bash
./scripts/validate-kubernetes.sh
```

The script renders all five overlays, verifies environment-specific paths and
policies, and checks the ALB and migration templates.

## Deployment Order

For each platform deployment:

1. Apply Terraform for networking, ACS, RDS, and OSS resources.
2. Ensure the ACR Personal namespace and repositories exist.
3. Verify that Metrics Server is available and install the ALB Ingress Controller
   in **Do not create** mode.
4. Render the shared AlbConfig with `scripts/render-alb-config.sh`.
5. Run a server-side dry-run, apply the rendered AlbConfig, and wait for its ALB
   ID and DNS name.
6. Apply the repository-owned `IngressClass` Kustomization.
7. Create the target namespace.
8. Create or update the namespace-local `portfolio-acr-pull` Secret.
9. Create or update the `portfolio-database` Secret.
10. Render a uniquely named migration Job with the API image digest.
11. Create the Job and wait for the `Complete` condition.
12. Stop the release and collect Job logs if migration fails.
13. Render and apply the target overlay with immutable image digests.
14. Wait for both Deployment rollouts and run HTTP smoke tests.

Migrations are not init containers. This prevents concurrent migrations during
Pod restarts, rolling updates, or HPA scale-out.

## Teardown Order

To avoid leaving billable cloud resources behind:

1. Delete the five namespaced Ingress resources.
2. Wait for ALB forwarding rules and server groups to be removed.
3. Delete the environment workloads and namespaces.
4. Delete the `IngressClass`.
5. Delete the `AlbConfig` and confirm that the ALB is gone.
6. Run Terraform destroy and check the Alibaba Cloud console for leftovers.

The infrastructure ADR documents the cost and isolation trade-offs in more
detail.

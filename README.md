# DevOps Assessment

## Goals

This repository implements a small multi-tier portfolio application and the
platform needed to build, validate, publish, and deploy it as code.

- FastAPI API and static Nginx Web application
- PostgreSQL data layer and one-shot Alembic migrations
- Terraform-managed Alibaba Cloud platform
- Kubernetes manifests for five logical environments
- GitHub Actions CI, approval-gated infrastructure delivery, and staged service
  delivery

## Architecture

- [Cost-optimized topology decision](docs/adr/0001-cost-optimized-topology.md)
- [Terraform bootstrap](infra/bootstrap/README.md)
- [Terraform platform](infra/platform/README.md)
- [Kubernetes deployment](deploy/README.md)
- [Infrastructure pipeline design](docs/infra-pipeline-design.md)
- [Service pipeline design](docs/pipeline-design.md)

## Local Quick Start

```bash
cp .env.example .env
docker compose up --build --wait
```

Open `http://127.0.0.1:8080/dev/`. To remove the local containers and database
volume after testing:

```bash
docker compose down --volumes --remove-orphans
```

## Repository Structure

| Path      | Purpose                                      |
| --------- | -------------------------------------------- |
| `app/api` | FastAPI service, tests, and migrations       |
| `app/web` | Static portfolio site and Nginx image        |
| `infra`   | Terraform bootstrap and platform roots       |
| `deploy`  | Kubernetes bases, overlays, Jobs, and access |
| `.github` | CI/CD workflows                              |
| `scripts` | Validation, rendering, and delivery helpers  |
| `docs`    | Architecture decisions and diagrams          |

## Security Notes

- GitHub Actions use OIDC and temporary Alibaba Cloud credentials.
- Terraform saved plans are encrypted and bound to their source run before
  approval.
- Service roles are isolated by Environment and Kubernetes namespace.
- Images are scanned and deployed by immutable digest.
- Workloads run as non-root with restricted security contexts.
- Sensitive Terraform values, kubeconfigs, and runtime Secrets are excluded
  from Git.

## Known Limitations

This is a shared, cost-optimized assessment platform rather than a production
reference architecture. The five environments share one ACS cluster, ALB, and
RDS instance. ACR Personal requires a fixed registry password, and the public
assessment endpoint is HTTP-only.

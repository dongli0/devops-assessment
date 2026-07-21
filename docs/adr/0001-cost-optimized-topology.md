# ADR 0001: Use a Shared, Cost-Optimized Alibaba Cloud Platform

- **Status:** Accepted
- **Date:** 2026-07-20
- **Last updated:** 2026-07-21

## Context

This assessment must demonstrate Terraform, Kubernetes, and delivery automation across dev, test, perf, staging, and production.

The platform runs in a personal Alibaba Cloud account with a budget of CNY 300. Fully isolating every environment would exceed the budget and add unnecessary delivery risk.

The workload is a small portfolio and resume application consisting of a static HTML, CSS, and JavaScript frontend served by Nginx, a FastAPI backend, and PostgreSQL persistence.

## Decision

Use a shared, single-region Alibaba Cloud platform with logical environment isolation.

- Primary region: `cn-shanghai`
- One VPC with two vSwitches in different availability zones
- One Alibaba Cloud Container Compute Service cluster (ACS) without worker nodes
- The ALB Ingress Controller configured without creating a default `AlbConfig`
- One public ALB with path-based routing, such as `/dev` and `/production`
- Five Kubernetes namespaces:
  - `portfolio-dev`
  - `portfolio-test`
  - `portfolio-perf`
  - `portfolio-staging`
  - `portfolio-production`
- One RDS PostgreSQL 14 Serverless Basic instance with a separate database and account for each environment
- ACR Personal Edition in the same region
- A private OSS bucket and a Tablestore lock table for Terraform remote state
- GitHub Actions authentication through OIDC and temporary Alibaba Cloud STS credentials
- No long-lived Alibaba Cloud AccessKey in GitHub
- No NAT Gateway, public RDS endpoint, application OSS bucket, Redis, or optional paid observability services

The Terraform state and identity bootstrap resources are isolated from the main platform stack so that a platform destroy cannot remove its own backend or authentication path.

ACR Personal Edition requires manual initialization because the current product does not provide the required public API. Its fixed registry password is stored as a protected GitHub Environment secret and is never committed to Git or Terraform state.

Multi-region deployment is deliberately deferred because it is optional in the assessment and incompatible with the available short-term budget.

## Consequences

This design keeps the application and infrastructure small while demonstrating Terraform, Kubernetes, relational persistence, container delivery, remote state locking, and workload isolation.

The five environments are logically isolated but share the ACS cluster, ALB, and RDS instance. A shared-component failure or configuration error may affect every environment, and performance testing may influence other workloads.

The platform has a single regional failure domain and is not a production reference architecture. A production design would require multiple regions, independent data stores, tested recovery procedures, and stronger availability guarantees.

Terraform-managed database credentials are sensitive values stored in encrypted remote state. Access to the state bucket and lock table must therefore be restricted to the deployment role.

All five environments will be deployed briefly for validation. Non-development workloads will then be removed, dev will remain online for approximately three days, and all remaining billable resources will be destroyed.

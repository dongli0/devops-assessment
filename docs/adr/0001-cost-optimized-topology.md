# ADR 0001: Use a Shared, Cost-Optimized Alibaba Cloud Platform

* **Status:** Accepted
* **Date:** 2026-07-20

## Context

This assessment must demonstrate Terraform, Kubernetes, and delivery automation across dev, test, perf, staging, and production.

The platform runs in a personal Alibaba Cloud account with a budget of CNY 300。Building a fully isolated platform for each environment would exceed the budget and add unnecessary delivery risk.

The workload is a personal portfolio and resume website with a React frontend, a FastAPI backend, PostgreSQL persistence, and OSS-hosted resume assets.

## Decision

Use a shared Alibaba Cloud platform with logical environment isolation.

* Primary region: `cn-shanghai`
* fixed capacity fallback: `cn-hangzhou`
* One VPC with two vSwitches in different availability zones
* One Alibaba Cloud Container Compute Service cluster（ACS）without worker nodes
* One public ALB with path-based routing, such as `/dev` and `/production`
* Five Kubernetes namespaces:
  * `portfolio-dev`
  * `portfolio-test`
  * `portfolio-perf`
  * `portfolio-staging`
  * `portfolio-production`
* One RDS PostgreSQL 14 Serverless instance, with a separate database and account for each environment
*  One private OSS Standard LRS bucket per environment, with access controlled through a dedicated RRSA role
* ACR Personal Edition in the same region
* GitHub Actions authentication through OIDC and temporary Alibaba Cloud credentials
* No NAT Gateway or optional paid observability and security services

ACR Personal Edition requires a manual initialization step because the required setup is not fully available through OpenAPI. This step will be documented; everything else will be managed as code.

## Consequences

This design keeps costs within budget while demonstrating the required infrastructure, Kubernetes, and CI/CD capabilities.

The environments are logically isolated, but they still share the same cluster, ALB, and RDS instance. A failure or configuration error in a shared component may affect all environments. Performance-test results may also be influenced by shared capacity.

These trade-offs are acceptable for a short-lived assessment environment, but this design is not suitable as a production reference architecture.

All five environments will be deployed for validation. Non-development workloads will then be removed, dev will remain online for about three days, and all remaining resources will be destroyed.

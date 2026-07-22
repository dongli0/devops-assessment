#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "$#" -ne 3 ]]; then
  printf \
    'usage: %s <namespace> <job-name> <migration-manifest>\n' \
    "${0##*/}" \
    >&2
  exit 2
fi

kubernetes_namespace="$1"
migration_job="$2"
migration_manifest="$3"

if [[ ! "${kubernetes_namespace}" =~ ^portfolio-(dev|test|perf|staging|production)$ ]]; then
  printf 'invalid Kubernetes namespace\n' >&2
  exit 2
fi

if [[ ! "${migration_job}" =~ ^portfolio-migrate-r[0-9]+-[0-9]+-[0-9a-f]{8}$ ]]; then
  printf 'invalid migration job name\n' >&2
  exit 2
fi

if [[ ! -f "${migration_manifest}" ]]; then
  printf 'migration manifest does not exist\n' >&2
  exit 2
fi

for command_name in jq kubectl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'required command not found: %s\n' "${command_name}" >&2
    exit 1
  fi
done

validated_manifest="$(
  kubectl create \
    --dry-run=server \
    --filename "${migration_manifest}" \
    --output json
)"

if ! jq -e \
  --arg expected_name "${migration_job}" \
  --arg expected_namespace "${kubernetes_namespace}" \
  '
    .apiVersion == "batch/v1" and
    .kind == "Job" and
    .metadata.name == $expected_name and
    .metadata.namespace == $expected_namespace
  ' \
  <<< "${validated_manifest}" \
  >/dev/null; then
  printf \
    'migration manifest identity does not match requested job\n' \
    >&2
  exit 2
fi

kubectl create \
  --filename "${migration_manifest}"

if ! kubectl wait \
  --namespace "${kubernetes_namespace}" \
  --for=condition=complete \
  --timeout=330s \
  "job/${migration_job}"; then
  kubectl get \
    --namespace "${kubernetes_namespace}" \
    "job/${migration_job}" \
    --output wide \
    >&2 ||
    true

  kubectl logs \
    --namespace "${kubernetes_namespace}" \
    "job/${migration_job}" \
    --all-containers=true \
    --tail=200 \
    >&2 ||
    true

  exit 1
fi

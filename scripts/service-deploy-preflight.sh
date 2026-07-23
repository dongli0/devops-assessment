#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  printf '%s\n' "$1" >&2
  exit 2
}

validate_environment() {
  case "$1" in
    dev | test | perf | staging | production) ;;
    *) fail "unsupported deployment environment" ;;
  esac
}

validate_config() {
  if [[ "$#" -ne 9 ]]; then
    fail "validate-config requires 9 arguments"
  fi

  local environment="$1"
  local region="$2"
  local cluster_id="$3"
  local oidc_provider_arn="$4"
  local deploy_role_arn="$5"
  local acr_publish_registry="$6"
  local acr_pull_registry="$7"
  local acr_namespace="$8"
  local acr_username="$9"
  local acr_instance_id
  local acr_registry_region
  local expected_acr_pull_registry
  local oidc_account_id
  local role_account_id
  local acr_publish_pattern='^crpi-([a-z0-9]+)\.([a-z0-9-]+)\.personal\.cr\.aliyuncs\.com$'

  validate_environment "${environment}"

  [[ "${region}" =~ ^[a-z0-9]+(-[a-z0-9]+)+$ ]] ||
    fail "invalid Alibaba Cloud region"

  [[ "${cluster_id}" =~ ^[A-Za-z0-9][A-Za-z0-9-]{7,127}$ ]] ||
    fail "invalid ACS cluster ID"

  if [[ "${oidc_provider_arn}" =~ ^acs:ram::([0-9]+):oidc-provider/[^[:space:]]+$ ]]; then
    oidc_account_id="${BASH_REMATCH[1]}"
  else
    fail "invalid OIDC provider ARN"
  fi

  if [[ "${deploy_role_arn}" =~ ^acs:ram::([0-9]+):role/[^[:space:]]+$ ]]; then
    role_account_id="${BASH_REMATCH[1]}"
  else
    fail "invalid deployment role ARN"
  fi

  [[ "${oidc_account_id}" == "${role_account_id}" ]] ||
    fail "OIDC provider and deployment role belong to different accounts"

  if [[ "${acr_publish_registry}" =~ ${acr_publish_pattern} ]]; then
    acr_instance_id="${BASH_REMATCH[1]}"
    acr_registry_region="${BASH_REMATCH[2]}"
  else
    fail "invalid ACR Personal publish registry"
  fi

  [[ "${acr_registry_region}" == "${region}" ]] ||
    fail "ACR Personal publish registry is in a different region"

  expected_acr_pull_registry="crpi-${acr_instance_id}-vpc."
  expected_acr_pull_registry+="${region}.personal.cr.aliyuncs.com"

  [[ "${acr_pull_registry}" == "${expected_acr_pull_registry}" ]] ||
    fail "ACR pull registry must be the matching VPC endpoint"

  [[ "${acr_namespace}" =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]] ||
    fail "invalid ACR namespace"

  [[ -n "${acr_username}" ]] ||
    fail "ACR username is required"

  [[ "${acr_username}" != *[[:space:]]* ]] ||
    fail "ACR username must not contain whitespace"
}

verify_access() {
  if [[ "$#" -ne 1 ]]; then
    fail "verify-access requires a namespace"
  fi

  local kubernetes_namespace="$1"
  local environment
  local other_environment
  local other_namespace
  local permission
  local verb
  local resource
  local allowed
  local -a required_permissions=(
    "get secrets"
    "create secrets"
    "patch secrets"
    "get services"
    "create services"
    "patch services"
    "get services/proxy"
    "get pods"
    "list pods"
    "get pods/log"
    "get deployments.apps"
    "list deployments.apps"
    "create deployments.apps"
    "patch deployments.apps"
    "watch deployments.apps"
    "get replicasets.apps"
    "list replicasets.apps"
    "watch replicasets.apps"
    "get jobs.batch"
    "list jobs.batch"
    "create jobs.batch"
    "watch jobs.batch"
    "get ingresses.networking.k8s.io"
    "create ingresses.networking.k8s.io"
    "patch ingresses.networking.k8s.io"
    "get horizontalpodautoscalers.autoscaling"
    "create horizontalpodautoscalers.autoscaling"
    "patch horizontalpodautoscalers.autoscaling"
    "get poddisruptionbudgets.policy"
    "create poddisruptionbudgets.policy"
    "patch poddisruptionbudgets.policy"
  )
  local -a isolation_permissions=("${required_permissions[@]}")

  if [[ ! "${kubernetes_namespace}" =~ ^portfolio-(dev|test|perf|staging|production)$ ]]; then
    fail "invalid Kubernetes namespace"
  fi

  environment="${kubernetes_namespace#portfolio-}"

  command -v kubectl >/dev/null 2>&1 ||
    fail "required command not found: kubectl"

  for permission in "${required_permissions[@]}"; do
    verb="${permission%% *}"
    resource="${permission#* }"

    allowed="$(
      kubectl auth can-i \
        "${verb}" \
        "${resource}" \
        --namespace "${kubernetes_namespace}" ||
        true
    )"

    [[ "${allowed}" == "yes" ]] ||
      fail "deployment role lacks required permission: ${permission}"
  done

  allowed="$(
    kubectl auth can-i create namespaces ||
      true
  )"

  [[ "${allowed}" == "no" ]] ||
    fail "deployment role unexpectedly has namespace creation access"

  for other_environment in dev test perf staging production; do
    if [[ "${other_environment}" == "${environment}" ]]; then
      continue
    fi

    other_namespace="portfolio-${other_environment}"

    for permission in "${isolation_permissions[@]}"; do
      verb="${permission%% *}"
      resource="${permission#* }"

      allowed="$(
        kubectl auth can-i \
          "${verb}" \
          "${resource}" \
          --namespace "${other_namespace}" ||
          true
      )"

      [[ "${allowed}" == "no" ]] ||
        fail "deployment role has cross-environment permission: ${permission}"
    done
  done
}

if [[ "$#" -lt 1 ]]; then
  fail "a subcommand is required"
fi

subcommand="$1"
shift

case "${subcommand}" in
  validate-config)
    validate_config "$@"
    ;;
  verify-access)
    verify_access "$@"
    ;;
  *)
    fail "unsupported subcommand"
    ;;
esac

#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "$#" -ne 2 ]]; then
  printf \
    'usage: %s <environment> <kubernetes-namespace>\n' \
    "${0##*/}" \
    >&2
  exit 2
fi

target_environment="$1"
kubernetes_namespace="$2"

case "${target_environment}" in
  dev | test | perf | staging | production) ;;
  *)
    printf 'unsupported deployment environment\n' >&2
    exit 2
    ;;
esac

expected_namespace="portfolio-${target_environment}"

if [[ "${kubernetes_namespace}" != "${expected_namespace}" ]]; then
  printf 'namespace does not match deployment environment\n' >&2
  exit 2
fi

for command_name in curl jq kubectl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'required command not found: %s\n' "${command_name}" >&2
    exit 1
  fi
done

ingress_endpoint=""

for attempt in {1..24}; do
  if ! ingress_json="$(
    kubectl get \
      --namespace "${kubernetes_namespace}" \
      ingress/portfolio \
      --output json
  )"; then
    if [[ "${attempt}" -eq 24 ]]; then
      printf 'failed to read ALB Ingress status\n' >&2
      exit 1
    fi

    sleep 5
    continue
  fi


  hostname="$(
    jq -r \
      '.status.loadBalancer.ingress[0].hostname // empty' \
      <<< "${ingress_json}"
  )"

  if [[ -n "${hostname}" ]]; then
    if [[ ! "${hostname}" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
      printf 'Ingress returned an invalid hostname\n' >&2
      exit 1
    fi

    if [[ "${hostname}" == *..* ]]; then
      printf 'Ingress returned an invalid hostname\n' >&2
      exit 1
    fi

    case "${hostname}" in
      *.alb.aliyuncsslb.com | *.alb.aliyuncs.com) ;;
      *)
        printf 'Ingress returned an unexpected ALB hostname\n' >&2
        exit 1
        ;;
    esac

    ingress_endpoint="${hostname}"
    break
  fi

  if [[ "${attempt}" -eq 24 ]]; then
    printf 'ALB endpoint was not assigned\n' >&2
    exit 1
  fi

  sleep 5
done

base_url="http://${ingress_endpoint}"
api_url="${base_url}/${target_environment}/api/health/ready"
web_url="${base_url}/${target_environment}/"

service_ready=false

for _attempt in {1..18}; do
  api_ready=false
  web_ready=false

  if curl \
    --fail \
    --silent \
    --connect-timeout 3 \
    --max-time 5 \
    --output /dev/null \
    "${api_url}"; then
    api_ready=true
  fi

  if curl \
    --fail \
    --silent \
    --connect-timeout 3 \
    --max-time 5 \
    --output /dev/null \
    "${web_url}"; then
    web_ready=true
  fi

  if [[ "${api_ready}" == true && "${web_ready}" == true ]]; then
    service_ready=true
    break
  fi

  sleep 5
done

if [[ "${service_ready}" != true ]]; then
  printf 'public service smoke test failed\n' >&2
  exit 1
fi

printf '%s\n' "${base_url}"

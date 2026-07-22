#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "$#" -ne 3 ]]; then
  printf \
    'usage: %s <namespace> <acr-registry> <acr-username>\n' \
    "${0##*/}" \
    >&2
  exit 2
fi

kubernetes_namespace="$1"
acr_registry="$2"
acr_username="$3"
registry_pattern='^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.aliyuncs\.com$'

if [[ ! "${kubernetes_namespace}" =~ ^portfolio-(dev|test|perf|staging|production)$ ]]; then
  printf 'invalid Kubernetes namespace\n' >&2
  exit 2
fi

if [[ ! "${acr_registry}" =~ ${registry_pattern} ]]; then
  printf 'invalid ACR registry\n' >&2
  exit 2
fi

if [[ -z "${acr_username}" || "${acr_username}" == *[[:space:]]* ]]; then
  printf 'invalid ACR username\n' >&2
  exit 2
fi

if [[ -z "${ACR_PASSWORD:-}" ]]; then
  printf 'ACR_PASSWORD is required\n' >&2
  exit 2
fi

if [[ -z "${PORTFOLIO_DATABASE_URL:-}" ]]; then
  printf 'PORTFOLIO_DATABASE_URL is required\n' >&2
  exit 2
fi

if [[ "${ACR_PASSWORD}" == *$'\n'* || "${ACR_PASSWORD}" == *$'\r'* ]]; then
  printf 'ACR_PASSWORD must be a single line\n' >&2
  exit 2
fi

if [[ "${PORTFOLIO_DATABASE_URL}" != postgresql+asyncpg://* ]]; then
  printf 'invalid database URL scheme\n' >&2
  exit 2
fi

if [[ "${PORTFOLIO_DATABASE_URL}" == *$'\n'* ||
  "${PORTFOLIO_DATABASE_URL}" == *$'\r'* ]]; then
  printf 'database URL must be a single line\n' >&2
  exit 2
fi

runner_temp="${RUNNER_TEMP:-}"

if [[ -z "${runner_temp}" ||
  "${runner_temp}" != /* ||
  "${runner_temp}" == "/" ||
  ! -d "${runner_temp}" ]]; then
  printf 'RUNNER_TEMP must be a safe absolute directory\n' >&2
  exit 2
fi

runner_temp="${runner_temp%/}"

for command_name in jq kubectl mktemp; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'required command not found: %s\n' "${command_name}" >&2
    exit 1
  fi
done

umask 077

secret_directory="$(
  mktemp -d "${runner_temp}/service-secrets.XXXXXX"
)"

cleanup() {
  case "${secret_directory}" in
    "${runner_temp}"/service-secrets.*)
      rm -rf -- "${secret_directory}"
      ;;
    *)
      printf 'refusing to remove unexpected temporary path\n' >&2
      ;;
  esac
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

printf '%s' "${PORTFOLIO_DATABASE_URL}" \
  > "${secret_directory}/database-url"

export ACR_REGISTRY="${acr_registry}"
export ACR_USERNAME="${acr_username}"

acr_auth="$(
  jq -nr \
    '[env.ACR_USERNAME, env.ACR_PASSWORD] |
    join(":") |
    @base64'
)"

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  printf '::add-mask::%s\n' "${acr_auth}"
fi

export ACR_AUTH="${acr_auth}"

jq -n \
  '{
    auths: {
      (env.ACR_REGISTRY): {
        username: env.ACR_USERNAME,
        password: env.ACR_PASSWORD,
        auth: env.ACR_AUTH
      }
    }
  }' \
  > "${secret_directory}/dockerconfigjson"

kubectl create secret generic portfolio-database \
  --namespace "${kubernetes_namespace}" \
  --from-file="database-url=${secret_directory}/database-url" \
  --dry-run=client \
  --output yaml |
  kubectl apply \
    --server-side \
    --field-manager=portfolio-service-delivery \
    --filename -

kubectl create secret generic portfolio-acr-pull \
  --namespace "${kubernetes_namespace}" \
  --type kubernetes.io/dockerconfigjson \
  --from-file=".dockerconfigjson=${secret_directory}/dockerconfigjson" \
  --dry-run=client \
  --output yaml |
  kubectl apply \
    --server-side \
    --field-manager=portfolio-service-delivery \
    --filename -

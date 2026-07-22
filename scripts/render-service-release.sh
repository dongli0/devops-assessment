#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf \
    'Usage: %s ENV API_IMAGE WEB_IMAGE DEPLOYMENT_ID OUTPUT_DIR\n' \
    "${0##*/}"
}

require_fixed_count() {
  local expected="$1"
  local value="$2"
  local file="$3"
  local actual

  actual="$(grep -Fc -- "${value}" "${file}" || true)"

  [[ "${actual}" -eq "${expected}" ]] ||
    fail "${file}: expected ${expected} matches for ${value}, found ${actual}"
}

if [[ "$#" -ne 5 ]]; then
  usage >&2
  exit 2
fi

environment="$1"
api_image="$2"
web_image="$3"
deployment_id="$4"
output_dir="$5"

case "${environment}" in
  dev | test | perf | staging | production) ;;
  *)
    fail "environment must be dev, test, perf, staging, or production"
    ;;
esac

namespace="portfolio-${environment}"

[[ "${#deployment_id}" -le 45 ]] ||
  fail "deployment ID must not exceed 45 characters"

[[ "${deployment_id}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] ||
  fail "deployment ID must be a lowercase DNS label"

[[ ! -e "${output_dir}" ]] ||
  fail "output directory already exists: ${output_dir}"

output_parent="$(dirname -- "${output_dir}")"

[[ -d "${output_parent}" ]] ||
  fail "output directory parent does not exist: ${output_parent}"

command -v kubectl >/dev/null 2>&1 ||
  fail "kubectl is required"

command -v envsubst >/dev/null 2>&1 ||
  fail "envsubst is required"

registry_pattern='[a-z0-9.-]+\.aliyuncs\.com'
namespace_pattern='[a-z0-9]+([._-][a-z0-9]+)*'
digest_pattern='sha256:[0-9a-f]{64}'

api_pattern="^${registry_pattern}/${namespace_pattern}/"
api_pattern+="portfolio-api@${digest_pattern}$"

web_pattern="^${registry_pattern}/${namespace_pattern}/"
web_pattern+="portfolio-web@${digest_pattern}$"

[[ "${api_image}" =~ ${api_pattern} ]] ||
  fail "API image must be an immutable portfolio-api ACR digest reference"

[[ "${web_image}" =~ ${web_pattern} ]] ||
  fail "Web image must be an immutable portfolio-web ACR digest reference"

api_repository="${api_image%@*}"
api_digest="${api_image##*@}"
web_repository="${web_image%@*}"
web_digest="${web_image##*@}"

api_location="${api_repository%/portfolio-api}"
web_location="${web_repository%/portfolio-web}"

[[ "${api_location}" == "${web_location}" ]] ||
  fail "API and Web images must use the same registry and namespace"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
render_dir="$(mktemp -d)"

cleanup() {
  rm -rf -- "${render_dir}"
}

trap cleanup EXIT

cp -R -- "${repo_root}/deploy" "${render_dir}/deploy"

{
  printf '%s\n' \
    'apiVersion: kustomize.config.k8s.io/v1beta1' \
    'kind: Kustomization' \
    '' \
    'resources:'
  printf '  - overlays/%s\n' "${environment}"
  printf '%s\n' \
    '' \
    'images:' \
    '  - name: portfolio-api'
  printf '    newName: %s\n' "${api_repository}"
  printf '    digest: %s\n' "${api_digest}"
  printf '%s\n' '  - name: portfolio-web'
  printf '    newName: %s\n' "${web_repository}"
  printf '    digest: %s\n' "${web_digest}"
} > "${render_dir}/deploy/kustomization.yaml"

workloads_render="${render_dir}/workloads.yaml"
migration_render="${render_dir}/migration.yaml"

kubectl kustomize \
  "${render_dir}/deploy" \
  > "${workloads_render}"

export DEPLOYMENT_ID="${deployment_id}"
export KUBERNETES_NAMESPACE="${namespace}"
export PORTFOLIO_API_IMAGE="${api_image}"
export PORTFOLIO_ENVIRONMENT="${environment}"

kubectl kustomize \
  "${render_dir}/deploy/jobs/migration" |
  envsubst \
    '${DEPLOYMENT_ID} ${KUBERNETES_NAMESPACE} ${PORTFOLIO_API_IMAGE} ${PORTFOLIO_ENVIRONMENT}' \
    > "${migration_render}"

if grep -Eq \
  '__ENVIRONMENT__|\$\{[A-Z][A-Z0-9_]*\}' \
  "${workloads_render}" \
  "${migration_render}"; then
  fail "rendered manifests contain unresolved placeholders"
fi

if grep -Fq \
  -e 'portfolio-api:0.1.0' \
  -e 'portfolio-web:0.1.0' \
  "${workloads_render}"; then
  fail "rendered workloads contain mutable logical image references"
fi

require_fixed_count 1 "image: ${api_image}" "${workloads_render}"
require_fixed_count 1 "image: ${web_image}" "${workloads_render}"
require_fixed_count 1 "image: ${api_image}" "${migration_render}"
require_fixed_count 1 'kind: Job' "${migration_render}"
require_fixed_count \
  1 \
  "name: portfolio-migrate-${deployment_id}" \
  "${migration_render}"
require_fixed_count 1 "namespace: ${namespace}" "${migration_render}"

mkdir -- "${output_dir}"

cp -- "${migration_render}" "${output_dir}/migration.yaml"
cp -- "${workloads_render}" "${output_dir}/workloads.yaml"

printf 'rendered immutable release: %s\n' "${output_dir}"

#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_count() {
  local expected="$1"
  local pattern="$2"
  local file="$3"
  local actual

  actual="$(grep -Ec -- "${pattern}" "${file}" || true)"

  if [[ "${actual}" -ne "${expected}" ]]; then
    fail "${file}: expected ${expected} matches for ${pattern}, found ${actual}"
  fi
}

command -v kubectl >/dev/null 2>&1 ||
  fail "kubectl is required"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
render_dir="$(mktemp -d)"

cleanup() {
  rm -rf -- "${render_dir}"
}

trap cleanup EXIT

environments=(dev test perf staging production)

for environment in "${environments[@]}"; do
  case "${environment}" in
    dev | test)
      expected_replicas=1
      expected_hpas=0
      expected_pdbs=0
      ;;
    perf)
      expected_replicas=2
      expected_hpas=1
      expected_pdbs=0
      ;;
    staging)
      expected_replicas=2
      expected_hpas=1
      expected_pdbs=2
      ;;
    production)
      expected_replicas=2
      expected_hpas=2
      expected_pdbs=2
      ;;
  esac

  rendered="${render_dir}/${environment}.yaml"

  kubectl kustomize \
    "${repo_root}/deploy/overlays/${environment}" \
    > "${rendered}"

  if grep -Eq '__ENVIRONMENT__|\$\{[A-Z_]+\}' "${rendered}"; then
    fail "${environment}: unresolved placeholder found"
  fi

  require_count 1 '^kind: Namespace$' "${rendered}"
  require_count 2 '^kind: Service$' "${rendered}"
  require_count 2 '^kind: Deployment$' "${rendered}"
  require_count 1 '^kind: Ingress$' "${rendered}"
  require_count "${expected_hpas}" '^kind: HorizontalPodAutoscaler$' "${rendered}"
  require_count "${expected_pdbs}" '^kind: PodDisruptionBudget$' "${rendered}"

  require_count 1 "^  name: portfolio-${environment}$" "${rendered}"
  require_count 2 "^  replicas: ${expected_replicas}$" "${rendered}"
  require_count 1 "^          value: ${environment}$" "${rendered}"

  require_count 2 "path: /${environment}/api/health/live$" "${rendered}"
  require_count 1 "path: /${environment}/api/health/ready$" "${rendered}"
  require_count 1 "path: /${environment}/api$" "${rendered}"
  require_count 1 "path: /${environment}$" "${rendered}"
  require_count 1 '^  ingressClassName: alb-shared$' "${rendered}"

  printf 'validated environment: %s\n' "${environment}"
done

platform_render="${render_dir}/alicloud-alb.yaml"

kubectl kustomize \
  "${repo_root}/deploy/platform/alicloud-alb/cluster" \
  > "${platform_render}"

require_count 1 '^kind: AlbConfig$' "${platform_render}"
require_count 1 '^kind: IngressClass$' "${platform_render}"
require_count 1 '\$\{ALB_VSWITCH_ID_A\}' "${platform_render}"
require_count 1 '\$\{ALB_VSWITCH_ID_B\}' "${platform_render}"
require_count 1 '^    edition: Standard$' "${platform_render}"

migration_render="${render_dir}/migration.yaml"

kubectl kustomize \
  "${repo_root}/deploy/jobs/migration" \
  > "${migration_render}"

require_count 1 '^kind: Job$' "${migration_render}"
require_count 1 '\$\{DEPLOYMENT_ID\}' "${migration_render}"
require_count 1 '\$\{KUBERNETES_NAMESPACE\}' "${migration_render}"
require_count 1 '\$\{PORTFOLIO_API_IMAGE\}' "${migration_render}"
require_count 5 '\$\{PORTFOLIO_ENVIRONMENT\}' "${migration_render}"
require_count 1 'name: portfolio-database$' "${migration_render}"
require_count 1 'key: database-url$' "${migration_render}"

printf 'validated platform and migration templates\n'
printf 'Kubernetes manifest validation passed\n'

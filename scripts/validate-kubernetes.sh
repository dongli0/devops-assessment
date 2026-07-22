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
      expected_replica_fields=2
      expected_fixed_replicas=1
      expected_hpas=0
      expected_pdbs=0
      ;;
    perf)
      expected_replica_fields=1
      expected_fixed_replicas=2
      expected_hpas=1
      expected_pdbs=0
      ;;
    staging)
      expected_replica_fields=1
      expected_fixed_replicas=2
      expected_hpas=1
      expected_pdbs=2
      ;;
    production)
      expected_replica_fields=0
      expected_fixed_replicas=0
      expected_hpas=2
      expected_pdbs=2
      ;;
  esac

  if [[ "${environment}" == "production" ]]; then
    expected_replica_directives=0
  else
    expected_replica_directives=1
  fi

  require_count \
    "${expected_replica_directives}" \
    '^replicas:$' \
    "${repo_root}/deploy/overlays/${environment}/kustomization.yaml"

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
  require_count 2 'name: portfolio-acr-pull$' "${rendered}"
  require_count 1 '^kind: Ingress$' "${rendered}"
  require_count "${expected_hpas}" '^kind: HorizontalPodAutoscaler$' "${rendered}"
  require_count "${expected_pdbs}" '^kind: PodDisruptionBudget$' "${rendered}"

  require_count 1 "^  name: portfolio-${environment}$" "${rendered}"

  require_count \
    "${expected_replica_fields}" \
    '^  replicas: [0-9]+$' \
    "${rendered}"

  require_count \
    "${expected_replica_fields}" \
    "^  replicas: ${expected_fixed_replicas}$" \
    "${rendered}"

  require_count 1 "^          value: ${environment}$" "${rendered}"

  require_count 2 "path: /${environment}/api/health/live$" "${rendered}"
  require_count 1 "path: /${environment}/api/health/ready$" "${rendered}"
  require_count 1 "path: /${environment}/api$" "${rendered}"
  require_count 1 "path: /${environment}$" "${rendered}"
  require_count 1 '^  ingressClassName: alb-shared$' "${rendered}"

  printf 'validated environment: %s\n' "${environment}"
done

albconfig_render="${render_dir}/alicloud-albconfig.yaml"

ALB_VSWITCH_ID_A='vsw-validationa' \
  ALB_VSWITCH_ID_B='vsw-validationb' \
  ALB_VSWITCH_ZONE_A='cn-shanghai-e' \
  ALB_VSWITCH_ZONE_B='cn-shanghai-f' \
  "${repo_root}/scripts/render-alb-config.sh" \
  > "${albconfig_render}"

require_count 1 '^kind: AlbConfig$' "${albconfig_render}"
require_count 0 '\$\{[A-Z][A-Z0-9_]*\}' "${albconfig_render}"
require_count 1 'vSwitchId: "vsw-validationa"$' "${albconfig_render}"
require_count 1 'vSwitchId: "vsw-validationb"$' "${albconfig_render}"
require_count 1 '^    edition: Standard$' "${albconfig_render}"

if ALB_VSWITCH_ID_A='vsw-validationa' \
  ALB_VSWITCH_ID_B='vsw-validationa' \
  ALB_VSWITCH_ZONE_A='cn-shanghai-e' \
  ALB_VSWITCH_ZONE_B='cn-shanghai-f' \
  "${repo_root}/scripts/render-alb-config.sh" \
  > /dev/null 2>&1; then
  fail "ALB renderer accepted duplicate vSwitch IDs"
fi

if ALB_VSWITCH_ID_A='vsw-validationa' \
  ALB_VSWITCH_ID_B='vsw-validationb' \
  ALB_VSWITCH_ZONE_A='cn-shanghai-e' \
  ALB_VSWITCH_ZONE_B='cn-shanghai-e' \
  "${repo_root}/scripts/render-alb-config.sh" \
  > /dev/null 2>&1; then
  fail "ALB renderer accepted duplicate zones"
fi

ingress_class_render="${render_dir}/alicloud-ingress-class.yaml"

kubectl kustomize \
  "${repo_root}/deploy/platform/alicloud-alb/cluster" \
  > "${ingress_class_render}"

require_count 0 '^kind: AlbConfig$' "${ingress_class_render}"
require_count 1 '^kind: IngressClass$' "${ingress_class_render}"

migration_render="${render_dir}/migration.yaml"

kubectl kustomize \
  "${repo_root}/deploy/jobs/migration" \
  > "${migration_render}"

require_count 1 '^kind: Job$' "${migration_render}"
require_count 1 'name: portfolio-acr-pull$' "${migration_render}"
require_count 1 '\$\{DEPLOYMENT_ID\}' "${migration_render}"
require_count 1 '\$\{KUBERNETES_NAMESPACE\}' "${migration_render}"
require_count 1 '\$\{PORTFOLIO_API_IMAGE\}' "${migration_render}"
require_count 5 '\$\{PORTFOLIO_ENVIRONMENT\}' "${migration_render}"
require_count 1 'name: portfolio-database$' "${migration_render}"
require_count 1 'key: database-url$' "${migration_render}"

release_digest="sha256:$(printf 'a%.0s' {1..64})"
release_registry="crpi-validation-vpc.cn-shanghai.personal.cr.aliyuncs.com/portfolio"
release_api_image="${release_registry}/portfolio-api@${release_digest}"
release_web_image="${release_registry}/portfolio-web@${release_digest}"
release_output="${render_dir}/service-release-valid"

"${repo_root}/scripts/render-service-release.sh" \
  dev \
  "${release_api_image}" \
  "${release_web_image}" \
  validation-1 \
  "${release_output}" \
  > /dev/null

release_migration="${release_output}/migration.yaml"
release_workloads="${release_output}/workloads.yaml"

require_count 1 '^kind: Job$' "${release_migration}"
require_count 1 '^  name: portfolio-migrate-validation-1$' "${release_migration}"
require_count 1 '^  namespace: portfolio-dev$' "${release_migration}"
require_count 1 '@sha256:[0-9a-f]{64}$' "${release_migration}"

require_count 1 '^kind: Namespace$' "${release_workloads}"
require_count 2 '^kind: Deployment$' "${release_workloads}"
require_count 2 '@sha256:[0-9a-f]{64}$' "${release_workloads}"
require_count 0 'portfolio-(api|web):0\.1\.0' "${release_workloads}"
require_count 0 '\$\{[A-Z][A-Z0-9_]*\}' "${release_migration}"
require_count 0 '\$\{[A-Z][A-Z0-9_]*\}' "${release_workloads}"

mutable_output="${render_dir}/service-release-mutable"

if "${repo_root}/scripts/render-service-release.sh" \
  dev \
  "${release_registry}/portfolio-api:latest" \
  "${release_web_image}" \
  invalid-tag \
  "${mutable_output}" \
  > /dev/null 2>&1; then
  fail "service release renderer accepted a mutable image tag"
fi

environment_output="${render_dir}/service-release-environment"

if "${repo_root}/scripts/render-service-release.sh" \
  qa \
  "${release_api_image}" \
  "${release_web_image}" \
  invalid-environment \
  "${environment_output}" \
  > /dev/null 2>&1; then
  fail "service release renderer accepted an unsupported environment"
fi

location_output="${render_dir}/service-release-location"
mismatched_web_image="crpi-validation-vpc.cn-shanghai.personal.cr.aliyuncs.com/other/portfolio-web@${release_digest}"

if "${repo_root}/scripts/render-service-release.sh" \
  dev \
  "${release_api_image}" \
  "${mismatched_web_image}" \
  mismatched-location \
  "${location_output}" \
  > /dev/null 2>&1; then
  fail "service release renderer accepted mismatched image locations"
fi

for rejected_output in \
  "${mutable_output}" \
  "${environment_output}" \
  "${location_output}"; do
  [[ ! -e "${rejected_output}" ]] ||
    fail "failed render left output behind: ${rejected_output}"
done

printf 'validated immutable service release renderer\n'

printf 'validated platform and migration templates\n'
printf 'Kubernetes manifest validation passed\n'

#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
  pwd
)"

test_parent="${TMPDIR:-/tmp}"
test_parent="${test_parent%/}"

if [[ -z "${test_parent}" || "${test_parent}" != /* || "${test_parent}" == "/" ]]; then
  printf 'unsafe temporary directory root\n' >&2
  exit 1
fi

test_root="$(mktemp -d "${test_parent}/portfolio-service-tests.XXXXXX")"
mock_bin="${test_root}/bin"
mock_log="${test_root}/kubectl.log"
curl_log="${test_root}/curl.log"
mock_counter="${test_root}/counter"
capture_directory="${test_root}/captured"
runner_temp="${test_root}/runner"

cleanup() {
  case "${test_root}" in
    "${test_parent}"/portfolio-service-tests.*)
      rm -rf -- "${test_root}"
      ;;
    *)
      printf 'refusing to remove unexpected test path\n' >&2
      ;;
  esac
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

mkdir -- "${mock_bin}" "${capture_directory}" "${runner_temp}"
: > "${mock_log}"
: > "${curl_log}"

fail_test() {
  printf 'test failure: %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  if [[ "${actual}" != "${expected}" ]]; then
    printf \
      'test failure: %s\nexpected: %s\nactual:   %s\n' \
      "${description}" \
      "${expected}" \
      "${actual}" \
      >&2
    exit 1
  fi
}

expect_failure() {
  local description="$1"
  shift

  if "$@" >"${test_root}/failure.stdout" 2>"${test_root}/failure.stderr"; then
    fail_test "${description} unexpectedly succeeded"
  fi
}

reset_mocks() {
  : > "${mock_log}"
  : > "${curl_log}"
  rm -f -- "${mock_counter}" "${capture_directory}"/*
  rm -f -- \
    "${runner_temp}"/portfolio-*-rollout.log \
    "${runner_temp}"/portfolio-*-rollback.log
  rm -rf -- "${runner_temp}"/service-secrets.*
  export MOCK_CURL_MODE="success"
}

cat > "${mock_bin}/kubectl" <<'MOCK_KUBECTL'
#!/usr/bin/env bash

set -Eeuo pipefail

: "${MOCK_SCENARIO:?}"
: "${MOCK_LOG:?}"

rendered_command="kubectl"
for argument in "$@"; do
  printf -v quoted_argument '%q' "${argument}"
  rendered_command+=" ${quoted_argument}"
done
printf '%s\n' "${rendered_command}" >> "${MOCK_LOG}"

has_argument() {
  local expected="$1"
  shift
  local argument

  for argument in "$@"; do
    if [[ "${argument}" == "${expected}" ]]; then
      return 0
    fi
  done

  return 1
}

argument_after() {
  local expected="$1"
  shift
  local previous=""
  local argument

  for argument in "$@"; do
    if [[ "${previous}" == "${expected}" ]]; then
      printf '%s\n' "${argument}"
      return 0
    fi
    previous="${argument}"
  done

  return 1
}

case "${MOCK_SCENARIO}" in
  preflight-valid | preflight-cross | preflight-missing)
    if [[ "${1:-}" != "auth" || "${2:-}" != "can-i" ]]; then
      exit 90
    fi

    verb="${3:-}"
    resource="${4:-}"
    namespace="$(argument_after --namespace "$@" || true)"

    if [[ -z "${namespace}" ]]; then
      printf 'no\n'
      exit 1
    fi

    if [[ "${MOCK_SCENARIO}" == "preflight-missing" &&
      "${namespace}" == "portfolio-dev" &&
      "${verb}" == "patch" &&
      "${resource}" == "poddisruptionbudgets.policy" ]]; then
      printf 'no\n'
      exit 1
    fi

    if [[ "${namespace}" == "portfolio-dev" ]]; then
      printf 'yes\n'
      exit 0
    fi

    if [[ "${MOCK_SCENARIO}" == "preflight-cross" &&
      "${namespace}" == "portfolio-test" &&
      "${verb}" == "get" &&
      "${resource}" == "secrets" ]]; then
      printf 'yes\n'
      exit 0
    fi

    printf 'no\n'
    exit 1
    ;;

  secrets-success | secrets-apply-failure)
    : "${MOCK_CAPTURE_DIR:?}"

    if [[ "${1:-}" == "create" && "${2:-}" == "secret" ]]; then
      secret_name="${4:-}"
      source_file=""

      for argument in "$@"; do
        case "${argument}" in
          --from-file=*)
            source_file="${argument#--from-file=}"
            source_file="${source_file#*=}"
            ;;
        esac
      done

      [[ -n "${source_file}" ]]
      cp -- "${source_file}" "${MOCK_CAPTURE_DIR}/${secret_name}"

      printf \
        'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n' \
        "${secret_name}"
      exit 0
    fi

    if [[ "${1:-}" == "apply" ]]; then
      cat >/dev/null
      if [[ "${MOCK_SCENARIO}" == "secrets-apply-failure" ]]; then
        exit 1
      fi
      exit 0
    fi

    exit 90
    ;;

  migration-success | migration-mismatch | migration-failure | migration-dry-run-failure)
    : "${MOCK_MIGRATION_JOB:?}"
    : "${MOCK_NAMESPACE:?}"

    if [[ "${1:-}" == "create" ]] && has_argument --dry-run=server "$@"; then
      if [[ "${MOCK_SCENARIO}" == "migration-dry-run-failure" ]]; then
        exit 1
      fi

      manifest_name="${MOCK_MIGRATION_JOB}"
      if [[ "${MOCK_SCENARIO}" == "migration-mismatch" ]]; then
        manifest_name="portfolio-migrate-wrong"
      fi

      printf \
        '{"apiVersion":"batch/v1","kind":"Job","metadata":{"name":"%s","namespace":"%s"}}\n' \
        "${manifest_name}" \
        "${MOCK_NAMESPACE}"
      exit 0
    fi

    if [[ "${1:-}" == "create" ]]; then
      exit 0
    fi

    if [[ "${1:-}" == "wait" ]]; then
      if [[ "${MOCK_SCENARIO}" == "migration-failure" ]]; then
        exit 1
      fi
      exit 0
    fi

    if [[ "${1:-}" == "get" || "${1:-}" == "logs" ]]; then
      exit 0
    fi

    exit 90
    ;;

  smoke-success | smoke-curl-failure | smoke-invalid-host | smoke-ip-only)
    : "${MOCK_COUNTER:?}"

    if [[ "${1:-}" != "get" ]]; then
      exit 90
    fi

    count=0
    if [[ -f "${MOCK_COUNTER}" ]]; then
      count="$(< "${MOCK_COUNTER}")"
    fi
    count="$((count + 1))"
    printf '%s\n' "${count}" > "${MOCK_COUNTER}"

    case "${MOCK_SCENARIO}" in
      smoke-success)
        if [[ "${count}" -eq 1 ]]; then
          exit 1
        fi
        printf '%s\n' \
          '{"status":{"loadBalancer":{"ingress":[{"hostname":"alb-validation.cn-shanghai.alb.aliyuncsslb.com"}]}}}'
        ;;
      smoke-curl-failure)
        printf '%s\n' \
          '{"status":{"loadBalancer":{"ingress":[{"hostname":"alb-validation.cn-shanghai.alb.aliyuncsslb.com"}]}}}'
        ;;
      smoke-invalid-host)
        printf '%s\n' \
          '{"status":{"loadBalancer":{"ingress":[{"hostname":"example.com"}]}}}'
        ;;
      smoke-ip-only)
        printf '%s\n' \
          '{"status":{"loadBalancer":{"ingress":[{"ip":"203.0.113.10"}]}}}'
        ;;
    esac
    ;;

  rollout-wait-success | rollout-wait-failure)
    if [[ "${1:-}" != "rollout" || "${2:-}" != "status" ]]; then
      exit 90
    fi

    if [[ "${MOCK_SCENARIO}" == "rollout-wait-failure" &&
      "$*" == *"deployment/portfolio-web"* ]]; then
      printf 'mock Web rollout failure\n' >&2
      exit 1
    fi

    exit 0
    ;;

  rollout-capture)
    if [[ "${1:-}" != "get" ]]; then
      exit 90
    fi

    if [[ "$*" == *"deployment/portfolio-api"* ]]; then
      printf '%s\n' \
        '{"metadata":{"annotations":{"deployment.kubernetes.io/revision":"3"}},"spec":{"template":{"metadata":{"labels":{"app":"api"}},"spec":{"containers":[{"name":"api","image":"api:v1"}]}}}}'
      exit 0
    fi

    if [[ "$*" == *"deployment/portfolio-web"* ]]; then
      exit 0
    fi

    exit 90
    ;;

  rollout-success)
    if [[ "${1:-}" == "get" && "$*" == *"deployment/portfolio-api"* ]]; then
      printf '%s\n' \
        '{"metadata":{"annotations":{"deployment.kubernetes.io/revision":"4"}},"spec":{"template":{"metadata":{"labels":{"app":"api"}},"spec":{"containers":[{"name":"api","image":"api:v2"}]}}}}'
      exit 0
    fi

    if [[ "${1:-}" == "get" && "$*" == *"deployment/portfolio-web"* ]]; then
      printf '%s\n' \
        '{"metadata":{"annotations":{"deployment.kubernetes.io/revision":"6"}},"spec":{"template":{"metadata":{"labels":{"app":"web"}},"spec":{"containers":[{"name":"web","image":"web:v1"}]}}}}'
      exit 0
    fi

    if [[ "${1:-}" == "rollout" &&
      ("${2:-}" == "undo" || "${2:-}" == "status") ]]; then
      exit 0
    fi

    exit 90
    ;;

  *)
    printf 'unsupported mock scenario: %s\n' "${MOCK_SCENARIO}" >&2
    exit 90
    ;;
esac
MOCK_KUBECTL

cat > "${mock_bin}/curl" <<'MOCK_CURL'
#!/usr/bin/env bash

set -Eeuo pipefail

: "${MOCK_CURL_LOG:?}"

url="${!#}"
printf '%s\n' "${url}" >> "${MOCK_CURL_LOG}"

case "${MOCK_CURL_MODE:-success}" in
  success) ;;
  failure) exit 22 ;;
  *) exit 90 ;;
esac
MOCK_CURL

cat > "${mock_bin}/sleep" <<'MOCK_SLEEP'
#!/usr/bin/env bash

set -Eeuo pipefail
exit 0
MOCK_SLEEP

chmod 0755 \
  "${mock_bin}/kubectl" \
  "${mock_bin}/curl" \
  "${mock_bin}/sleep"

export PATH="${mock_bin}:${PATH}"
export MOCK_LOG="${mock_log}"
export MOCK_CURL_LOG="${curl_log}"
export MOCK_COUNTER="${mock_counter}"
export MOCK_CAPTURE_DIR="${capture_directory}"

preflight_script="${repo_root}/scripts/service-deploy-preflight.sh"
secrets_script="${repo_root}/scripts/apply-service-secrets.sh"
migration_script="${repo_root}/scripts/run-service-migration.sh"
rollout_script="${repo_root}/scripts/service-rollout.sh"
smoke_script="${repo_root}/scripts/smoke-test-service.sh"

valid_publish_registry="crpi-validation.cn-shanghai.personal.cr.aliyuncs.com"
valid_pull_registry="crpi-validation-vpc.cn-shanghai.personal.cr.aliyuncs.com"
valid_oidc_arn="acs:ram::123456789:oidc-provider/github"
valid_role_arn="acs:ram::123456789:role/portfolio-deploy-dev"

"${preflight_script}" \
  validate-config \
  dev \
  cn-shanghai \
  cvalidation123 \
  "${valid_oidc_arn}" \
  "${valid_role_arn}" \
  "${valid_publish_registry}" \
  "${valid_pull_registry}" \
  portfolio \
  validation-user

expect_failure \
  "cross-account deployment configuration" \
  "${preflight_script}" \
  validate-config \
  dev \
  cn-shanghai \
  cvalidation123 \
  "${valid_oidc_arn}" \
  acs:ram::987654321:role/portfolio-deploy-dev \
  "${valid_publish_registry}" \
  "${valid_pull_registry}" \
  portfolio \
  validation-user

expect_failure \
  "malformed ACR registry" \
  "${preflight_script}" \
  validate-config \
  dev \
  cn-shanghai \
  cvalidation123 \
  "${valid_oidc_arn}" \
  "${valid_role_arn}" \
  foo..aliyuncs.com \
  "${valid_pull_registry}" \
  portfolio \
  validation-user

expect_failure \
  "mismatched ACR VPC endpoint" \
  "${preflight_script}" \
  validate-config \
  dev \
  cn-shanghai \
  cvalidation123 \
  "${valid_oidc_arn}" \
  "${valid_role_arn}" \
  "${valid_publish_registry}" \
  crpi-other-vpc.cn-shanghai.personal.cr.aliyuncs.com \
  portfolio \
  validation-user

reset_mocks
export MOCK_SCENARIO="preflight-valid"
"${preflight_script}" verify-access portfolio-dev

required_permissions=(
  "get secrets"
  "create secrets"
  "patch secrets"
  "get services"
  "create services"
  "patch services"
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

for permission in "${required_permissions[@]}"; do
  verb="${permission%% *}"
  resource="${permission#* }"

  grep -Fqx \
    "kubectl auth can-i ${verb} ${resource} --namespace portfolio-dev" \
    "${mock_log}" ||
    fail_test "required permission was not checked: ${permission}"
done

assert_equal \
  "${#required_permissions[@]}" \
  "$(grep -c -- '--namespace portfolio-dev$' "${mock_log}")" \
  "target namespace permission check count"

for other_namespace in \
  portfolio-test \
  portfolio-perf \
  portfolio-staging \
  portfolio-production; do
  for permission in "${required_permissions[@]}"; do
    verb="${permission%% *}"
    resource="${permission#* }"

    grep -Fqx \
      "kubectl auth can-i ${verb} ${resource} --namespace ${other_namespace}" \
      "${mock_log}" ||
      fail_test \
        "cross-environment permission was not checked: ${other_namespace} ${permission}"
  done
done

assert_equal \
  "$((4 * ${#required_permissions[@]}))" \
  "$(grep -Ec -- '--namespace portfolio-(test|perf|staging|production)$' "${mock_log}")" \
  "cross-environment permission check count"

grep -Fqx \
  'kubectl auth can-i create namespaces' \
  "${mock_log}" ||
  fail_test "cluster-scoped namespace creation was not checked"

reset_mocks
export MOCK_SCENARIO="preflight-missing"
expect_failure \
  "missing target Kubernetes permission" \
  "${preflight_script}" \
  verify-access \
  portfolio-dev

reset_mocks
export MOCK_SCENARIO="preflight-cross"
expect_failure \
  "cross-environment Kubernetes permission" \
  "${preflight_script}" \
  verify-access \
  portfolio-dev

reset_mocks
export MOCK_SCENARIO="secrets-success"
export RUNNER_TEMP="${runner_temp}"
export ACR_PASSWORD="validation-password"
export PORTFOLIO_DATABASE_URL="postgresql+asyncpg://portfolio:validation@db/portfolio"

GITHUB_ACTIONS=true \
  "${secrets_script}" \
  portfolio-dev \
  "${valid_pull_registry}" \
  validation-user \
  >"${test_root}/secrets.stdout" \
  2>"${test_root}/secrets.stderr"

assert_equal \
  "1" \
  "$(grep -Ec '^kubectl create secret generic portfolio-database --namespace portfolio-dev --from-file=database-url=.+ --dry-run=client --output yaml$' "${mock_log}")" \
  "database Secret create flags"

assert_equal \
  "1" \
  "$(grep -Ec '^kubectl create secret generic portfolio-acr-pull --namespace portfolio-dev --type kubernetes.io/dockerconfigjson --from-file=\.dockerconfigjson=.+ --dry-run=client --output yaml$' "${mock_log}")" \
  "ACR pull Secret create flags"

assert_equal \
  "2" \
  "$(grep -Fxc 'kubectl apply --server-side --field-manager=portfolio-service-delivery --filename -' "${mock_log}")" \
  "Secret server-side apply flags"

assert_equal \
  "${PORTFOLIO_DATABASE_URL}" \
  "$(< "${capture_directory}/portfolio-database")" \
  "database Secret content"

expected_auth="$(
  printf '%s' "validation-user:${ACR_PASSWORD}" |
    base64 |
    tr -d '\n'
)"

jq -e \
  --arg registry "${valid_pull_registry}" \
  --arg username "validation-user" \
  --arg password "${ACR_PASSWORD}" \
  --arg auth "${expected_auth}" \
  '
    .auths[$registry].username == $username and
    .auths[$registry].password == $password and
    .auths[$registry].auth == $auth
  ' \
  "${capture_directory}/portfolio-acr-pull" \
  >/dev/null

grep -Fqx \
  "::add-mask::${expected_auth}" \
  "${test_root}/secrets.stdout" ||
  fail_test "derived ACR auth was not masked"

if grep -Fq "${ACR_PASSWORD}" \
  "${test_root}/secrets.stdout" \
  "${test_root}/secrets.stderr"; then
  fail_test "ACR password leaked to helper output"
fi

if grep -Fq "${PORTFOLIO_DATABASE_URL}" \
  "${test_root}/secrets.stdout" \
  "${test_root}/secrets.stderr"; then
  fail_test "database URL leaked to helper output"
fi

if find "${runner_temp}" \
  -mindepth 1 \
  -maxdepth 1 \
  -type d \
  -name 'service-secrets.*' |
  grep -q .; then
  fail_test "Secret temporary directory was not removed"
fi

reset_mocks
export MOCK_SCENARIO="secrets-apply-failure"
expect_failure \
  "failed Secret apply" \
  env \
  GITHUB_ACTIONS=false \
  RUNNER_TEMP="${runner_temp}" \
  ACR_PASSWORD="${ACR_PASSWORD}" \
  PORTFOLIO_DATABASE_URL="${PORTFOLIO_DATABASE_URL}" \
  "${secrets_script}" \
  portfolio-dev \
  "${valid_pull_registry}" \
  validation-user

if find "${runner_temp}" \
  -mindepth 1 \
  -maxdepth 1 \
  -type d \
  -name 'service-secrets.*' |
  grep -q .; then
  fail_test "failed Secret apply left temporary files"
fi

migration_job="portfolio-migrate-r123-1-aaaaaaaa"
migration_manifest="${test_root}/migration.yaml"

cat > "${migration_manifest}" <<EOF_MIGRATION
apiVersion: batch/v1
kind: Job
metadata:
  name: ${migration_job}
  namespace: portfolio-dev
EOF_MIGRATION

export MOCK_MIGRATION_JOB="${migration_job}"
export MOCK_NAMESPACE="portfolio-dev"

reset_mocks
export MOCK_SCENARIO="migration-success"
"${migration_script}" \
  portfolio-dev \
  "${migration_job}" \
  "${migration_manifest}"

assert_equal \
  "1" \
  "$(grep -c -- '--dry-run=server' "${mock_log}")" \
  "migration server dry-run count"

assert_equal \
  "1" \
  "$(grep -c '^kubectl create --filename' "${mock_log}")" \
  "migration create count"

assert_equal \
  "1" \
  "$(grep -c '^kubectl wait ' "${mock_log}")" \
  "migration wait count"

reset_mocks
export MOCK_SCENARIO="migration-mismatch"
expect_failure \
  "mismatched migration manifest" \
  "${migration_script}" \
  portfolio-dev \
  "${migration_job}" \
  "${migration_manifest}"

if grep -q '^kubectl create --filename' "${mock_log}"; then
  fail_test "mismatched migration manifest was created"
fi

reset_mocks
export MOCK_SCENARIO="migration-dry-run-failure"
expect_failure \
  "failed migration server dry-run" \
  "${migration_script}" \
  portfolio-dev \
  "${migration_job}" \
  "${migration_manifest}"

if grep -q '^kubectl create --filename' "${mock_log}"; then
  fail_test "migration was created after its server dry-run failed"
fi

if grep -q '^kubectl wait ' "${mock_log}"; then
  fail_test "migration wait ran after its server dry-run failed"
fi

reset_mocks
export MOCK_SCENARIO="migration-failure"
expect_failure \
  "failed migration Job" \
  "${migration_script}" \
  portfolio-dev \
  "${migration_job}" \
  "${migration_manifest}"

grep -q '^kubectl get ' "${mock_log}" ||
  fail_test "failed migration did not inspect the Job"
grep -q '^kubectl logs ' "${mock_log}" ||
  fail_test "failed migration did not collect logs"

reset_mocks
export MOCK_SCENARIO="smoke-success"
base_url="$("${smoke_script}" dev portfolio-dev)"

assert_equal \
  "http://alb-validation.cn-shanghai.alb.aliyuncsslb.com" \
  "${base_url}" \
  "service smoke-test URL"

assert_equal \
  "2" \
  "$(grep -c '^kubectl get ' "${mock_log}")" \
  "Ingress retry count"

grep -Fqx \
  "${base_url}/dev/api/health/ready" \
  "${curl_log}" ||
  fail_test "API readiness URL was not requested"

grep -Fqx \
  "${base_url}/dev/" \
  "${curl_log}" ||
  fail_test "Web URL was not requested"

reset_mocks
export MOCK_SCENARIO="smoke-curl-failure"
export MOCK_CURL_MODE="failure"
expect_failure \
  "persistently unavailable public service" \
  "${smoke_script}" \
  dev \
  portfolio-dev

assert_equal \
  "36" \
  "$(wc -l < "${curl_log}")" \
  "public service retry request count"

reset_mocks
export MOCK_SCENARIO="smoke-invalid-host"
expect_failure \
  "untrusted Ingress hostname" \
  "${smoke_script}" \
  dev \
  portfolio-dev

[[ ! -s "${curl_log}" ]] ||
  fail_test "untrusted Ingress hostname reached curl"

reset_mocks
export MOCK_SCENARIO="smoke-ip-only"
expect_failure \
  "IP-only Ingress endpoint" \
  "${smoke_script}" \
  dev \
  portfolio-dev

[[ ! -s "${curl_log}" ]] ||
  fail_test "IP-only Ingress endpoint reached curl"

reset_mocks
export MOCK_SCENARIO="rollout-capture"
capture_output="$(
  "${rollout_script}" capture-revisions portfolio-dev
)"

api_previous_template_hash="$(
  printf '%s\n' \
    '{"metadata":{"labels":{"app":"api"}},"spec":{"containers":[{"name":"api","image":"api:v1"}]}}' |
    jq -cS . |
    sha256sum
)"
api_previous_template_hash="${api_previous_template_hash%% *}"

web_previous_template_hash="$(
  printf '%s\n' \
    '{"metadata":{"labels":{"app":"web"}},"spec":{"containers":[{"name":"web","image":"web:v1"}]}}' |
    jq -cS . |
    sha256sum
)"
web_previous_template_hash="${web_previous_template_hash%% *}"

expected_capture_output="api_exists=true
api_revision=3
api_template_hash=${api_previous_template_hash}
web_exists=false
web_revision=
web_template_hash="
assert_equal \
  "${expected_capture_output}" \
  "${capture_output}" \
  "captured workload state"

reset_mocks
export MOCK_SCENARIO="rollout-wait-success"
RUNNER_TEMP="${runner_temp}" \
  "${rollout_script}" \
  wait \
  portfolio-dev

assert_equal \
  "2" \
  "$(grep -c '^kubectl rollout status --namespace portfolio-dev --timeout=300s deployment/portfolio-' "${mock_log}")" \
  "successful workload rollout wait count"

reset_mocks
export MOCK_SCENARIO="rollout-wait-failure"
expect_failure \
  "failed workload rollout" \
  env \
  RUNNER_TEMP="${runner_temp}" \
  "${rollout_script}" \
  wait \
  portfolio-dev

grep -Fq \
  'mock Web rollout failure' \
  "${test_root}/failure.stderr" ||
  fail_test "failed workload rollout log was not reported"

assert_equal \
  "2" \
  "$(grep -c '^kubectl rollout status --namespace portfolio-dev --timeout=300s deployment/portfolio-' "${mock_log}")" \
  "failed workload rollout wait count"

reset_mocks
export MOCK_SCENARIO="rollout-success"
RUNNER_TEMP="${runner_temp}" \
  "${rollout_script}" \
  rollback \
  portfolio-dev \
  true \
  3 \
  "${api_previous_template_hash}" \
  true \
  6 \
  "${web_previous_template_hash}" \
  >"${test_root}/rollback.stdout" \
  2>"${test_root}/rollback.stderr"

grep -Fq \
  'kubectl rollout undo --namespace portfolio-dev --to-revision 3 deployment/portfolio-api' \
  "${mock_log}" ||
  fail_test "API was not rolled back to its exact previous revision"

if grep -Fq \
  'kubectl rollout undo --namespace portfolio-dev --to-revision 6 deployment/portfolio-web' \
  "${mock_log}"; then
  fail_test "unchanged Web pod template was rolled back"
fi

grep -Fq \
  'kubectl rollout status --namespace portfolio-dev --timeout=240s deployment/portfolio-api' \
  "${mock_log}" ||
  fail_test "API rollback completion was not observed"

printf 'service deployment helper validation passed\n'

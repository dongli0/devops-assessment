#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for command_name in jq kubectl; do
  command -v "${command_name}" >/dev/null 2>&1 ||
    fail "required command not found: ${command_name}"
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
subject="${script_dir}/write-acs-kubeconfig.sh"
export ALIBABA_CLOUD_REGION_ID=cn-shanghai
test_root="$(mktemp -d /tmp/portfolio-acs-kubeconfig-test.XXXXXX)"
mock_bin="${test_root}/bin"

cleanup() {
  case "${test_root}" in
    /tmp/portfolio-acs-kubeconfig-test.*)
      rm -rf -- "${test_root}"
      ;;
    *)
      fail "refusing to remove unexpected path: ${test_root}"
      ;;
  esac
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

mkdir -p -- "${mock_bin}"

cat >"${mock_bin}/aliyun" <<'MOCK'
#!/usr/bin/env bash

set -Eeuo pipefail

[[ "${ALIBABA_CLOUD_IGNORE_PROFILE:-}" == "TRUE" ]] || {
  printf 'profile fallback was not disabled\n' >&2
  exit 2
}

: "${MOCK_ALIYUN_CALL_LOG:?}"

printf '%s\n' "$@" >"${MOCK_ALIYUN_CALL_LOG}"

case "${MOCK_ALIYUN_MODE:-success}" in
  success)
    kubeconfig="$(
      cat <<'KUBECONFIG'
apiVersion: v1
kind: Config
clusters:
  - name: validation
    cluster:
      server: https://127.0.0.1
      insecure-skip-tls-verify: true
contexts:
  - name: validation
    context:
      cluster: validation
      user: validation
current-context: validation
users:
  - name: validation
    user:
      token: validation-token
KUBECONFIG
    )"

    jq -n \
      --arg config "${kubeconfig}" \
      --arg expiration "2026-07-22T12:15:00Z" \
      '{config: $config, expiration: $expiration}'
    ;;
  api-error)
    printf 'mock API failure\n' >&2
    exit 42
    ;;
  invalid-json)
    printf '{invalid-json\n'
    ;;
  invalid-kubeconfig)
    jq -n \
      --arg config 'not: [valid' \
      --arg expiration "2026-07-22T12:15:00Z" \
      '{config: $config, expiration: $expiration}'
    ;;
  *)
    printf 'unknown mock mode\n' >&2
    exit 2
    ;;
esac
MOCK

chmod +x "${mock_bin}/aliyun"

call_log="${test_root}/aliyun-arguments"
output_file="${test_root}/kubeconfig"
stdout_file="${test_root}/stdout"
stderr_file="${test_root}/stderr"

PATH="${mock_bin}:${PATH}" \
MOCK_ALIYUN_CALL_LOG="${call_log}" \
MOCK_ALIYUN_MODE=success \
  "${subject}" \
  c-validation123 \
  "${output_file}" \
  >"${stdout_file}" \
  2>"${stderr_file}"

[[ -f "${output_file}" ]] ||
  fail "successful request did not create kubeconfig"

[[ "$(stat -c '%a' "${output_file}")" == "600" ]] ||
  fail "kubeconfig permissions are not 600"

kubectl \
  --kubeconfig "${output_file}" \
  config view \
  --minify \
  >/dev/null

expected_arguments="${test_root}/expected-arguments"

printf '%s\n' \
  cs \
  DescribeClusterUserKubeconfig \
  --ClusterId \
  c-validation123 \
  --TemporaryDurationMinutes \
  15 \
  --PrivateIpAddress \
  false \
  >"${expected_arguments}"

diff -u "${expected_arguments}" "${call_log}"

if grep -Fq 'validation-token' "${stdout_file}" "${stderr_file}"; then
  fail "kubeconfig credential leaked into command output"
fi

existing_file="${test_root}/existing-kubeconfig"
printf 'preserve-me\n' >"${existing_file}"

if PATH="${mock_bin}:${PATH}" \
  MOCK_ALIYUN_CALL_LOG="${call_log}" \
  MOCK_ALIYUN_MODE=success \
  "${subject}" \
  c-validation123 \
  "${existing_file}" \
  >/dev/null 2>&1; then
  fail "existing output file was accepted"
fi

[[ "$(cat "${existing_file}")" == "preserve-me" ]] ||
  fail "existing output file was modified"

for mode in api-error invalid-json invalid-kubeconfig; do
  rejected_output="${test_root}/rejected-${mode}"

  if PATH="${mock_bin}:${PATH}" \
    MOCK_ALIYUN_CALL_LOG="${call_log}" \
    MOCK_ALIYUN_MODE="${mode}" \
    "${subject}" \
    c-validation123 \
    "${rejected_output}" \
    >/dev/null 2>&1; then
    fail "failure mode unexpectedly succeeded: ${mode}"
  fi

  [[ ! -e "${rejected_output}" ]] ||
    fail "failure left kubeconfig behind: ${mode}"
done

printf 'temporary ACS kubeconfig helper validation passed\n'

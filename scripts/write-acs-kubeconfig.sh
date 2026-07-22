#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <cluster-id> <output-file>\n' "$0" >&2
  exit 2
fi

cluster_id="$1"
output_file="$2"
output_parent="$(dirname -- "${output_file}")"
output_name="$(basename -- "${output_file}")"
region_id="${ALIBABA_CLOUD_REGION_ID:-}"

[[ "${cluster_id}" =~ ^[A-Za-z0-9][A-Za-z0-9-]{7,127}$ ]] ||
  fail "invalid ACS cluster ID"

[[ "${region_id}" =~ ^[a-z0-9]+(-[a-z0-9]+)+$ ]] ||
  fail "ALIBABA_CLOUD_REGION_ID is missing or invalid"

[[ -d "${output_parent}" ]] ||
  fail "output directory does not exist: ${output_parent}"

[[ ! -e "${output_file}" && ! -L "${output_file}" ]] ||
  fail "refusing to overwrite output file: ${output_file}"

for command_name in aliyun jq kubectl; do
  command -v "${command_name}" >/dev/null 2>&1 ||
    fail "required command not found: ${command_name}"
done

export ALIBABA_CLOUD_IGNORE_PROFILE=TRUE

umask 077

response_file=""
output_temp=""

cleanup() {
  if [[ -n "${response_file}" ]]; then
    rm -f -- "${response_file}"
  fi

  if [[ -n "${output_temp}" ]]; then
    rm -f -- "${output_temp}"
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

response_file="$(mktemp)"
output_temp="$(
  mktemp "${output_parent}/.${output_name}.tmp.XXXXXX"
)"

aliyun cs DescribeClusterUserKubeconfig \
  --ClusterId "${cluster_id}" \
  --TemporaryDurationMinutes 15 \
  --PrivateIpAddress false \
  >"${response_file}"

jq -er \
  '.config | select(type == "string" and length > 0)' \
  "${response_file}" \
  >"${output_temp}"

expiration="$(
  jq -er \
    '.expiration | select(type == "string" and length > 0)' \
    "${response_file}"
)"

[[ "${expiration}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$ ]] || fail "invalid kubeconfig expiration returned by ACS"

chmod 600 "${output_temp}"

kubectl \
  --kubeconfig "${output_temp}" \
  config view \
  --minify \
  >/dev/null

if ! ln -- "${output_temp}" "${output_file}"; then
  fail "refusing to replace output file: ${output_file}"
fi

rm -f -- "${output_temp}"
output_temp=""

printf \
  'wrote temporary ACS kubeconfig: %s (expires: %s)\n' \
  "${output_file}" \
  "${expiration}"

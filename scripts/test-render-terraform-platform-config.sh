#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for command_name in jq stat; do
  command -v "${command_name}" >/dev/null 2>&1 ||
    fail "required command not found: ${command_name}"
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
subject="${script_dir}/render-terraform-platform-config.sh"
test_root="$(mktemp -d /tmp/portfolio-terraform-config-test.XXXXXX)"

cleanup() {
  case "${test_root}" in
    /tmp/portfolio-terraform-config-test.*)
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

valid_vswitches='{
  "a": {
    "zone_id": "cn-shanghai-e",
    "cidr_block": "10.20.0.0/20"
  },
  "b": {
    "zone_id": "cn-shanghai-f",
    "cidr_block": "10.20.16.0/20"
  }
}'

run_subject() {
  local output_dir="$1"
  shift

  env \
    ALIBABA_CLOUD_REGION_ID=cn-shanghai \
    TERRAFORM_STATE_BUCKET=portfolio-validation-state \
    TERRAFORM_STATE_TABLESTORE_ENDPOINT=https://tfstate.cn-shanghai.ots.aliyuncs.com \
    TERRAFORM_STATE_TABLESTORE_TABLE=terraform_locks \
    TERRAFORM_PLATFORM_VSWITCHES="${valid_vswitches}" \
    "$@" \
    "${subject}" \
    "${output_dir}"
}

expect_failure() {
  local description="$1"
  local output_dir="$2"
  shift 2

  if "$@" >"${test_root}/failure.stdout" 2>"${test_root}/failure.stderr"; then
    fail "${description} unexpectedly succeeded"
  fi

  [[ ! -e "${output_dir}" ]] ||
    fail "${description} left an output directory"
}

valid_output="${test_root}/valid"

run_subject \
  "${valid_output}" \
  TERRAFORM_KUBERNETES_VERSION=1.34.1-aliyun.1 \
  >/dev/null

[[ "$(stat -c '%a' "${valid_output}")" == "700" ]] ||
  fail "output directory permissions are not 700"

for rendered_file in backend.hcl terraform.tfvars.json; do
  [[ "$(stat -c '%a' "${valid_output}/${rendered_file}")" == "600" ]] ||
    fail "${rendered_file} permissions are not 600"
done

grep -Fxq \
  'prefix              = "devops-assessment/platform"' \
  "${valid_output}/backend.hcl" ||
  fail "backend prefix changed"

grep -Fxq \
  'key                 = "terraform.tfstate"' \
  "${valid_output}/backend.hcl" ||
  fail "backend key changed"

jq --exit-status '
  .region == "cn-shanghai" and
  .vswitches.a.zone_id == "cn-shanghai-e" and
  .vswitches.b.cidr_block == "10.20.16.0/20" and
  .kubernetes_version == "1.34.1-aliyun.1" and
  .cluster_api_public_access == true and
  .cluster_deletion_protection == false
' "${valid_output}/terraform.tfvars.json" >/dev/null ||
  fail "rendered Terraform variables are incorrect"

null_version_output="${test_root}/null-version"
run_subject "${null_version_output}" >/dev/null

jq --exit-status \
  '.kubernetes_version == null' \
  "${null_version_output}/terraform.tfvars.json" \
  >/dev/null ||
  fail "empty Kubernetes version did not render as null"

invalid_region_output="${test_root}/invalid-region"
expect_failure \
  "unsupported region" \
  "${invalid_region_output}" \
  env \
  ALIBABA_CLOUD_REGION_ID=cn-hangzhou \
  TERRAFORM_STATE_BUCKET=portfolio-validation-state \
  TERRAFORM_STATE_TABLESTORE_ENDPOINT=https://tfstate.cn-hangzhou.ots.aliyuncs.com \
  TERRAFORM_STATE_TABLESTORE_TABLE=terraform_locks \
  TERRAFORM_PLATFORM_VSWITCHES="${valid_vswitches}" \
  "${subject}" \
  "${invalid_region_output}"

invalid_bucket_output="${test_root}/invalid-bucket"
expect_failure \
  "unsafe bucket" \
  "${invalid_bucket_output}" \
  run_subject \
  "${invalid_bucket_output}" \
  'TERRAFORM_STATE_BUCKET=invalid"bucket'

invalid_endpoint_output="${test_root}/invalid-endpoint"
expect_failure \
  "unsafe Tablestore endpoint" \
  "${invalid_endpoint_output}" \
  run_subject \
  "${invalid_endpoint_output}" \
  TERRAFORM_STATE_TABLESTORE_ENDPOINT=http://tfstate.cn-shanghai.ots.aliyuncs.com

duplicate_vswitches='{
  "a": {
    "zone_id": "cn-shanghai-e",
    "cidr_block": "10.20.0.0/20"
  },
  "b": {
    "zone_id": "cn-shanghai-e",
    "cidr_block": "10.20.0.0/20"
  }
}'

invalid_vswitch_output="${test_root}/invalid-vswitches"
expect_failure \
  "duplicate vSwitches" \
  "${invalid_vswitch_output}" \
  run_subject \
  "${invalid_vswitch_output}" \
  TERRAFORM_PLATFORM_VSWITCHES="${duplicate_vswitches}"

invalid_version_output="${test_root}/invalid-version"
expect_failure \
  "invalid Kubernetes version" \
  "${invalid_version_output}" \
  run_subject \
  "${invalid_version_output}" \
  TERRAFORM_KUBERNETES_VERSION=1.34.1

relative_output="relative-terraform-config"
expect_failure \
  "relative output path" \
  "${relative_output}" \
  run_subject \
  "${relative_output}"

existing_output="${test_root}/existing"
mkdir -- "${existing_output}"

if run_subject "${existing_output}" >/dev/null 2>&1; then
  fail "existing output directory unexpectedly succeeded"
fi

printf 'Terraform platform configuration renderer validation passed\n'

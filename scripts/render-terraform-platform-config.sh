#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: %s OUTPUT_DIR\n' "${0##*/}"
}

if [[ "$#" -ne 1 ]]; then
  usage >&2
  exit 2
fi

for command_name in jq mktemp; do
  command -v "${command_name}" >/dev/null 2>&1 ||
    fail "required command not found: ${command_name}"
done

output_dir="$1"

[[ "${output_dir}" == /* ]] ||
  fail "output directory must be an absolute path"

[[ ! -e "${output_dir}" ]] ||
  fail "output directory already exists: ${output_dir}"

output_parent="$(dirname -- "${output_dir}")"

[[ -d "${output_parent}" ]] ||
  fail "output directory parent does not exist: ${output_parent}"

region_id="${ALIBABA_CLOUD_REGION_ID:-}"
state_bucket="${TERRAFORM_STATE_BUCKET:-}"
tablestore_endpoint="${TERRAFORM_STATE_TABLESTORE_ENDPOINT:-}"
tablestore_table="${TERRAFORM_STATE_TABLESTORE_TABLE:-}"
vswitches_json="${TERRAFORM_PLATFORM_VSWITCHES:-}"
kubernetes_version="${TERRAFORM_KUBERNETES_VERSION:-}"

[[ "${region_id}" == "cn-shanghai" ]] ||
  fail "ALIBABA_CLOUD_REGION_ID must be cn-shanghai"

[[ "${state_bucket}" =~ ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$ ]] ||
  fail "TERRAFORM_STATE_BUCKET is missing or invalid"

endpoint_pattern='^https://[a-z][a-z0-9-]{1,14}[a-z0-9]'
endpoint_pattern+="\\.${region_id}\\.ots\\.aliyuncs\\.com$"

[[ "${tablestore_endpoint}" =~ ${endpoint_pattern} ]] ||
  fail "TERRAFORM_STATE_TABLESTORE_ENDPOINT is missing or invalid"

[[ "${tablestore_table}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,254}$ ]] ||
  fail "TERRAFORM_STATE_TABLESTORE_TABLE is missing or invalid"

if [[ -n "${kubernetes_version}" ]]; then
  [[ "${kubernetes_version}" =~ ^1\.[0-9]+\.[0-9]+-aliyun\.[0-9]+$ ]] ||
    fail "TERRAFORM_KUBERNETES_VERSION is invalid"
fi

canonical_vswitches="$({
  jq \
    --compact-output \
    --exit-status \
    --sort-keys \
    --arg region "${region_id}" \
    '
      def valid_cidr:
        type == "string" and
        test("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/([0-9]|[12][0-9]|3[0-2])$");

      if (
        type == "object" and
        keys == ["a", "b"] and
        all(.[];
          type == "object" and
          keys == ["cidr_block", "zone_id"] and
          .zone_id == ($region + "-" + (.zone_id | split("-") | last)) and
          (.zone_id | test("^[a-z]{2}-[a-z0-9-]+-[a-z]$")) and
          (.cidr_block | valid_cidr)
        ) and
        .a.zone_id != .b.zone_id and
        .a.cidr_block != .b.cidr_block
      ) then
        .
      else
        error("invalid vSwitch configuration")
      end
    ' \
    <<<"${vswitches_json}"
} 2>/dev/null)" ||
  fail "TERRAFORM_PLATFORM_VSWITCHES must define distinct a and b vSwitches"

umask 077
staging_dir="$(
  mktemp -d "${output_parent}/.terraform-platform-config.XXXXXX"
)"

cleanup() {
  if [[ -n "${staging_dir:-}" && -d "${staging_dir}" ]]; then
    case "${staging_dir}" in
      "${output_parent}"/.terraform-platform-config.*)
        rm -rf -- "${staging_dir}"
        ;;
      *)
        printf \
          'ERROR: refusing to remove unexpected path: %s\n' \
          "${staging_dir}" \
          >&2
        ;;
    esac
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

cat >"${staging_dir}/backend.hcl" <<EOF
bucket              = "${state_bucket}"
prefix              = "devops-assessment/platform"
key                 = "terraform.tfstate"
region              = "${region_id}"
tablestore_endpoint = "${tablestore_endpoint}"
tablestore_table    = "${tablestore_table}"
encrypt             = true
acl                 = "private"
EOF

jq \
  --null-input \
  --arg region "${region_id}" \
  --argjson vswitches "${canonical_vswitches}" \
  --arg kubernetes_version "${kubernetes_version}" \
  '
    {
      region: $region,
      vswitches: $vswitches,
      kubernetes_version: (
        if $kubernetes_version == "" then
          null
        else
          $kubernetes_version
        end
      ),
      cluster_api_public_access: true,
      cluster_deletion_protection: false
    }
  ' \
  >"${staging_dir}/terraform.tfvars.json"

chmod 600 \
  "${staging_dir}/backend.hcl" \
  "${staging_dir}/terraform.tfvars.json"

mv -- "${staging_dir}" "${output_dir}"
staging_dir=""

printf 'rendered Terraform platform configuration: %s\n' "${output_dir}"

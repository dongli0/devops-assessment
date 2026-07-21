#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

command -v envsubst >/dev/null 2>&1 ||
  fail "envsubst is required"

required_variables=(
  ALB_VSWITCH_ID_A
  ALB_VSWITCH_ID_B
  ALB_VSWITCH_ZONE_A
  ALB_VSWITCH_ZONE_B
)

for variable in "${required_variables[@]}"; do
  [[ -n "${!variable:-}" ]] ||
    fail "${variable} is required"
done

validate_vswitch_id() {
  local variable="$1"
  local value="${!variable}"

  [[ "${value}" =~ ^vsw-[A-Za-z0-9]+$ ]] ||
    fail "${variable} must be a valid vSwitch ID"
}

validate_vswitch_id ALB_VSWITCH_ID_A
validate_vswitch_id ALB_VSWITCH_ID_B

[[ "${ALB_VSWITCH_ID_A}" != "${ALB_VSWITCH_ID_B}" ]] ||
  fail "ALB vSwitch IDs must be different"

[[ "${ALB_VSWITCH_ZONE_A}" != "${ALB_VSWITCH_ZONE_B}" ]] ||
  fail "ALB vSwitches must be in different zones"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
template="${repo_root}/deploy/platform/alicloud-alb/cluster/albconfig.yaml.tmpl"
render_dir="$(mktemp -d)"
rendered="${render_dir}/albconfig.yaml"

cleanup() {
  rm -rf -- "${render_dir}"
}

trap cleanup EXIT

envsubst '${ALB_VSWITCH_ID_A} ${ALB_VSWITCH_ID_B}' \
  < "${template}" \
  > "${rendered}"

if grep -Eq '\$\{[A-Z][A-Z0-9_]*\}' "${rendered}"; then
  fail "rendered AlbConfig contains an unresolved placeholder"
fi

vswitch_count="$(grep -c 'vSwitchId:' "${rendered}" || true)"

[[ "${vswitch_count}" -eq 2 ]] ||
  fail "rendered AlbConfig must contain exactly two vSwitch IDs"

for vswitch_id in "${ALB_VSWITCH_ID_A}" "${ALB_VSWITCH_ID_B}"; do
  grep -Fq -- "vSwitchId: \"${vswitch_id}\"" "${rendered}" ||
    fail "rendered AlbConfig is missing ${vswitch_id}"
done

cat "${rendered}"

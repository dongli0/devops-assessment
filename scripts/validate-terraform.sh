#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for command_name in git terraform; do
  command -v "${command_name}" >/dev/null 2>&1 ||
    fail "${command_name} is required"
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "${script_dir}" rev-parse --show-toplevel)"
cd -- "${repo_root}"

stacks=(
  infra/bootstrap
  infra/platform
)

validation_tmp="$(mktemp -d /tmp/portfolio-terraform-validation.XXXXXX)"

cleanup() {
  case "${validation_tmp}" in
    /tmp/portfolio-terraform-validation.*)
      if [[ -d "${validation_tmp}" ]]; then
        rm -rf -- "${validation_tmp}"
      fi
      ;;
    *)
      printf 'ERROR: refusing to remove unexpected path: %s\n' \
        "${validation_tmp}" >&2
      ;;
  esac
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

unset \
  TF_DATA_DIR \
  TF_CLI_ARGS \
  TF_CLI_ARGS_init \
  TF_CLI_ARGS_fmt \
  TF_CLI_ARGS_validate

export TF_IN_AUTOMATION=1
export TF_INPUT=0

tracked_violations=()

while IFS= read -r -d '' path; do
  case "${path}" in
    */backend.hcl | \
      *.tfvars | \
      *.tfvars.json | \
      *.tfstate | \
      *.tfstate.* | \
      *.tfplan | \
      */.terraform/* | \
      */override.tf | \
      */override.tf.json | \
      */*_override.tf | \
      */*_override.tf.json | \
      */crash.log | \
      */crash.*.log)
      tracked_violations+=("${path}")
      ;;
  esac
done < <(git ls-files -z -- infra)

if (( ${#tracked_violations[@]} > 0 )); then
  printf 'Generated or sensitive Terraform files are tracked:\n' >&2
  printf '  %s\n' "${tracked_violations[@]}" >&2
  exit 1
fi

ignored_contract=(
  infra/bootstrap/.terraform/validation
  infra/bootstrap/terraform.tfstate
  infra/bootstrap/bootstrap.tfplan
  infra/bootstrap/backend.hcl
  infra/bootstrap/terraform.tfvars
  infra/platform/.terraform/validation
  infra/platform/terraform.tfstate
  infra/platform/platform.tfplan
  infra/platform/backend.hcl
  infra/platform/terraform.tfvars
)

for path in "${ignored_contract[@]}"; do
  git check-ignore --quiet --no-index -- "${path}" ||
    fail "expected Terraform local file is not ignored: ${path}"
done

for stack in "${stacks[@]}"; do
  lock_file="${stack}/.terraform.lock.hcl"

  [[ -f "${lock_file}" ]] ||
    fail "missing provider lock file: ${lock_file}"

  git ls-files --error-unmatch -- "${lock_file}" >/dev/null 2>&1 ||
    fail "provider lock file is not tracked: ${lock_file}"
done

terraform fmt -check -recursive infra

example_dir="${validation_tmp}/examples"
mkdir -p -- "${example_dir}"

examples=(
  "infra/bootstrap/terraform.tfvars.example|bootstrap.tfvars"
  "infra/platform/backend.hcl.example|platform-backend.tfvars"
  "infra/platform/terraform.tfvars.example|platform.tfvars"
)

for mapping in "${examples[@]}"; do
  source_file="${mapping%%|*}"
  target_file="${example_dir}/${mapping##*|}"

  cp -- "${source_file}" "${target_file}"
  terraform fmt -check -diff "${target_file}"
done

for stack in "${stacks[@]}"; do
  stack_name="${stack##*/}"
  stack_data_dir="${validation_tmp}/${stack_name}"
  mkdir -p -- "${stack_data_dir}"

  init_args=(
    -backend=false
    -input=false
    -lockfile=readonly
    -no-color
  )

  if [[ "${TERRAFORM_OFFLINE:-0}" == "1" ]]; then
    plugin_dir="${repo_root}/${stack}/.terraform/providers"

    [[ -d "${plugin_dir}" ]] ||
      fail "offline provider directory is missing: ${plugin_dir}"

    init_args+=("-plugin-dir=${plugin_dir}")
  fi

  TF_DATA_DIR="${stack_data_dir}" \
    terraform -chdir="${stack}" init "${init_args[@]}"

  TF_DATA_DIR="${stack_data_dir}" \
    terraform -chdir="${stack}" validate -no-color

  printf 'validated Terraform stack: %s\n' "${stack_name}"
done

git diff --check

printf 'Terraform code validation passed\n'

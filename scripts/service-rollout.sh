#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
  printf '%s\n' "$1" >&2
  exit 2
}

validate_namespace() {
  [[ "$1" =~ ^portfolio-(dev|test|perf|staging|production)$ ]] ||
    fail "invalid Kubernetes namespace"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command not found: $1"
}

validated_runner_temp() {
  local runner_temp="${RUNNER_TEMP:-}"

  if [[ -z "${runner_temp}" ||
    "${runner_temp}" != /* ||
    "${runner_temp}" == "/" ||
    ! -d "${runner_temp}" ]]; then
    fail "RUNNER_TEMP must be a safe absolute directory"
  fi

  printf '%s\n' "${runner_temp%/}"
}

capture_revisions() {
  [[ "$#" -eq 1 ]] ||
    fail "capture-revisions requires a namespace"

  local kubernetes_namespace="$1"
  local component
  local deployment
  local deployment_json
  local revision
  local template_hash

  validate_namespace "${kubernetes_namespace}"
  require_command kubectl
  require_command jq
  require_command sha256sum

  for component in api web; do
    deployment="portfolio-${component}"

    deployment_json="$(
      kubectl get \
        --namespace "${kubernetes_namespace}" \
        "deployment/${deployment}" \
        --ignore-not-found \
        --output json
    )"

    if [[ -z "${deployment_json}" ]]; then
      printf '%s_exists=false\n' "${component}"
      printf '%s_revision=\n' "${component}"
      printf '%s_template_hash=\n' "${component}"
      continue
    fi

    revision="$(
      jq -er \
        '.metadata.annotations[
          "deployment.kubernetes.io/revision"
        ] |
        select(
          type == "string" and
          test("^[0-9]+$")
        )' \
        <<< "${deployment_json}"
    )"

    template_hash="$(
      jq -cSe \
        '.spec.template |
        select(type == "object")' \
        <<< "${deployment_json}" |
        sha256sum
    )"
    template_hash="${template_hash%% *}"

    [[ "${template_hash}" =~ ^[0-9a-f]{64}$ ]] ||
      fail "failed to hash deployment pod template"

    printf '%s_exists=true\n' "${component}"
    printf '%s_revision=%s\n' "${component}" "${revision}"
    printf '%s_template_hash=%s\n' "${component}" "${template_hash}"
  done
}

wait_for_rollouts() {
  [[ "$#" -eq 1 ]] ||
    fail "wait requires a namespace"

  local kubernetes_namespace="$1"
  local runner_temp
  local api_log
  local web_log
  local api_pid
  local web_pid
  local rollout_failed=false

  validate_namespace "${kubernetes_namespace}"
  require_command kubectl
  runner_temp="$(validated_runner_temp)"

  api_log="${runner_temp}/portfolio-api-rollout.log"
  web_log="${runner_temp}/portfolio-web-rollout.log"

  kubectl rollout status \
    --namespace "${kubernetes_namespace}" \
    --timeout=300s \
    deployment/portfolio-api \
    >"${api_log}" 2>&1 &
  api_pid="$!"

  kubectl rollout status \
    --namespace "${kubernetes_namespace}" \
    --timeout=300s \
    deployment/portfolio-web \
    >"${web_log}" 2>&1 &
  web_pid="$!"

  if ! wait "${api_pid}"; then
    cat "${api_log}" >&2
    rollout_failed=true
  fi

  if ! wait "${web_pid}"; then
    cat "${web_log}" >&2
    rollout_failed=true
  fi

  if [[ "${rollout_failed}" == true ]]; then
    return 1
  fi
}

rollback_workloads() {
  [[ "$#" -eq 7 ]] ||
    fail "rollback requires namespace and six workload state arguments"

  local kubernetes_namespace="$1"
  local api_existed="$2"
  local api_revision="$3"
  local api_template_hash="$4"
  local web_existed="$5"
  local web_revision="$6"
  local web_template_hash="$7"
  local runner_temp
  local rollback_failed=false
  local deployment
  local log_file
  local -a rollback_targets=()
  local -A rollback_pids=()
  local -A rollback_logs=()

  validate_namespace "${kubernetes_namespace}"
  require_command kubectl
  require_command jq
  require_command sha256sum
  runner_temp="$(validated_runner_temp)"

  prepare_rollback() {
    local workload="$1"
    local existed="$2"
    local previous_revision="$3"
    local previous_template_hash="$4"
    local deployment_json
    local current_template_hash

    case "${existed}" in
      true) ;;
      false)
        if [[ -n "${previous_revision}" ||
          -n "${previous_template_hash}" ]]; then
          printf '%s has unexpected previous state\n' "${workload}" >&2
          return 1
        fi

        printf \
          '%s did not exist before this release; no rollback revision is available\n' \
          "${workload}" \
          >&2
        return 0
        ;;
      *)
        printf '%s has an invalid existence flag\n' "${workload}" >&2
        return 1
        ;;
    esac

    if [[ ! "${previous_revision}" =~ ^[0-9]+$ ]]; then
      printf '%s has no valid previous revision\n' "${workload}" >&2
      return 1
    fi

    if [[ ! "${previous_template_hash}" =~ ^[0-9a-f]{64}$ ]]; then
      printf '%s has no valid previous pod template hash\n' "${workload}" >&2
      return 1
    fi

    if ! deployment_json="$(
      kubectl get \
        --namespace "${kubernetes_namespace}" \
        "deployment/${workload}" \
        --output json
    )"; then
      return 1
    fi

    if ! current_template_hash="$(
      jq -cSe \
        '.spec.template |
        select(type == "object")' \
        <<< "${deployment_json}" |
        sha256sum
    )"; then
      return 1
    fi
    current_template_hash="${current_template_hash%% *}"

    if [[ ! "${current_template_hash}" =~ ^[0-9a-f]{64}$ ]]; then
      return 1
    fi

    if [[ "${current_template_hash}" == "${previous_template_hash}" ]]; then
      printf \
        '%s pod template is unchanged; rollback is not required\n' \
        "${workload}" \
        >&2
      return 0
    fi

    if ! kubectl rollout undo \
      --namespace "${kubernetes_namespace}" \
      --to-revision "${previous_revision}" \
      "deployment/${workload}"; then
      return 1
    fi

    rollback_targets+=("${workload}")
  }

  if ! prepare_rollback \
    portfolio-api \
    "${api_existed}" \
    "${api_revision}" \
    "${api_template_hash}"; then
    rollback_failed=true
  fi

  if ! prepare_rollback \
    portfolio-web \
    "${web_existed}" \
    "${web_revision}" \
    "${web_template_hash}"; then
    rollback_failed=true
  fi

  for deployment in "${rollback_targets[@]}"; do
    log_file="${runner_temp}/${deployment}-rollback.log"
    rollback_logs["${deployment}"]="${log_file}"

    kubectl rollout status \
      --namespace "${kubernetes_namespace}" \
      --timeout=240s \
      "deployment/${deployment}" \
      >"${log_file}" 2>&1 &

    rollback_pids["${deployment}"]="$!"
  done

  for deployment in "${rollback_targets[@]}"; do
    if ! wait "${rollback_pids[${deployment}]}"; then
      cat "${rollback_logs[${deployment}]}" >&2
      rollback_failed=true
    fi
  done

  if [[ "${rollback_failed}" == true ]]; then
    return 1
  fi
}

[[ "$#" -ge 1 ]] ||
  fail "a subcommand is required"

subcommand="$1"
shift

case "${subcommand}" in
  capture-revisions)
    capture_revisions "$@"
    ;;
  wait)
    wait_for_rollouts "$@"
    ;;
  rollback)
    rollback_workloads "$@"
    ;;
  *)
    fail "unsupported subcommand"
    ;;
esac

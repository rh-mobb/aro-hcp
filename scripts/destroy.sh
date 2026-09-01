#!/usr/bin/env bash
# Tear down ARO HCP Terraform resources.
#
# OCPBUGS-86702: the RP rejects DELETE of the last node pool. Terraform would
# try that child first. Remove the default pool from state, then destroy: the
# cluster goes before the customer RG, and ARM cascades remaining pools.
# Drop the state-rm once last-pool DELETE is allowed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

NODE_POOL_STATE_ADDRESS="module.cluster.azapi_resource.node_pool"

usage() {
  cat <<EOF
Usage: $(basename "$0")

Removes the default node pool from Terraform state, then destroys remaining
Terraform resources (cluster ARM delete cascades remaining pools).
EOF
}

in_state() {
  local address="$1"
  terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -Fx "${address}" >/dev/null
}

cluster_provisioning_state() {
  az aro hcp cluster show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --query provisioningState -o tsv 2>/dev/null || true
}

wait_for_cluster_gone() {
  local max_wait="${1:-3600}"
  local interval=30
  local elapsed=0
  while cluster_exists; do
    local state
    state="$(cluster_provisioning_state)"
    log "Cluster ${CLUSTER_NAME} still in Azure (provisioningState=${state:-unknown}); waiting ${interval}s"
    sleep "${interval}"
    elapsed=$((elapsed + interval))
    if [[ "${elapsed}" -ge "${max_wait}" ]]; then
      die "Timed out after ${max_wait}s waiting for cluster ${CLUSTER_NAME} to finish deleting"
    fi
  done
}

run_terraform_destroy() {
  local destroy_args=(-auto-approve)
  if [[ -f "${TFVARS}" ]]; then
    local jump_pub=""
    if [[ -n "${CLUSTER:-}" ]]; then
      jump_pub="${ROOT_DIR}/clusters/${CLUSTER}/jump.pub"
    fi
    if [[ -f "${jump_pub}" ]]; then
      TF_VAR_jump_ssh_public_key="$(cat "${jump_pub}")"
      export TF_VAR_jump_ssh_public_key
      export TF_VAR_jump_ssh_private_key_path="${ROOT_DIR}/clusters/${CLUSTER}/jump"
    fi
    export_tf_var_pull_secret_path
    destroy_args+=(-var-file="${TFVARS}")
  fi
  terraform -chdir="${TF_DIR}" destroy "${destroy_args[@]}"
}

cmd_destroy() {
  require_cmd terraform
  require_cmd az
  load_tf

  if [[ -n "${CLUSTER:-}" ]]; then
    export TF_DATA_DIR="${ROOT_DIR}/clusters/${CLUSTER}/.terraform"
  fi
  : "${TF_DATA_DIR:?TF_DATA_DIR is required; run via make cluster.<profile>.destroy}"

  if in_state "${NODE_POOL_STATE_ADDRESS}"; then
    log "Removing ${NODE_POOL_STATE_ADDRESS} from state (OCPBUGS-86702 last-pool delete)"
    terraform -chdir="${TF_DIR}" state rm "${NODE_POOL_STATE_ADDRESS}"
  else
    log "Default node pool not in state; skipping state rm"
  fi

  if cluster_exists && [[ "$(cluster_provisioning_state)" == "Deleting" ]]; then
    log "Cluster already deleting in Azure; waiting before terraform destroy"
    wait_for_cluster_gone
  fi

  log "Destroying Terraform resources"
  local attempt=0
  local max_attempts=40
  local output=""
  while [[ "${attempt}" -lt "${max_attempts}" ]]; do
    set +e
    output="$(run_terraform_destroy 2>&1)"
    local status=$?
    set -e
    if [[ "${status}" -eq 0 ]]; then
      printf '%s\n' "${output}"
      return 0
    fi
    printf '%s\n' "${output}" >&2
    if [[ "${output}" == *"is deleting"* ]] || [[ "${output}" == *"Conflict"* && "${output}" == *"hcpOpenShiftClusters"* ]]; then
      attempt=$((attempt + 1))
      log "Cluster delete in progress (attempt ${attempt}/${max_attempts}); waiting 60s"
      wait_for_cluster_gone 7200
      continue
    fi
    return "${status}"
  done
  die "terraform destroy failed after ${max_attempts} attempts while cluster was deleting"
}

main() {
  require_cmd terraform
  local cmd="${1:-destroy}"
  case "${cmd}" in
    destroy | "") cmd_destroy ;;
    -h | --help | help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "${1:-destroy}"

#!/usr/bin/env bash
# Create, show, update, delete, or list node pools.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <create|show|update|delete|list> [options]

Overrides: NAME= REPLICAS= VM_SIZE= VERSION= CHANNEL=
EOF
}

cmd_create() {
  if [[ "${NAME:-${NODEPOOL_NAME}}" == "${NODEPOOL_NAME}" ]]; then
    log "WARN: default node pool ${NODEPOOL_NAME} is Terraform-managed; prefer make cluster.<name>.apply. CLI create is for extra pools (NAME=...)."
  fi
  local name="${NAME:-${NODEPOOL_NAME}}"
  local replicas="${REPLICAS:-${NODEPOOL_REPLICAS}}"
  local vm_size="${VM_SIZE:-${NODEPOOL_VM_SIZE}}"
  local version="${VERSION:-${NODEPOOL_VERSION:-${CLUSTER_VERSION}}}"
  local channel="${CHANNEL:-${NODEPOOL_CHANNEL}}"

  if nodepool_exists "${name}"; then
    log "Node pool ${name} already exists; skipping create"
    return 0
  fi

  cluster_exists || die "Cluster ${CLUSTER_NAME} does not exist"

  log "Creating node pool ${name}"
  az aro hcp cluster nodepool create \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    --name "${name}" \
    --replicas "${replicas}" \
    --vm-size "${vm_size}" \
    --version "${version}" \
    --channel-group "${channel}"
}

cmd_show() {
  local name="${NAME:-${NODEPOOL_NAME}}"
  az aro hcp cluster nodepool show \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    --name "${name}" \
    -o json
}

cmd_update() {
  local name="${NAME:-${NODEPOOL_NAME}}"
  local replicas="${REPLICAS:-}"
  if [[ -z "${replicas}" ]]; then
    die "Set REPLICAS= for update"
  fi
  az aro hcp cluster nodepool update \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    --name "${name}" \
    --replicas "${replicas}"
}

cmd_delete() {
  local name="${NAME:-${NODEPOOL_NAME}}"
  if ! nodepool_exists "${name}"; then
    log "Node pool ${name} not found; nothing to delete"
    return 0
  fi
  az aro hcp cluster nodepool delete \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    --name "${name}" \
    -y
}

cmd_list() {
  az aro hcp cluster nodepool list \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    -o table
}

main() {
  load_tf
  require_cmd az
  local cmd="${1:-}"
  case "${cmd}" in
    create) cmd_create ;;
    show) cmd_show ;;
    update) cmd_update ;;
    delete) cmd_delete ;;
    list) cmd_list ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"

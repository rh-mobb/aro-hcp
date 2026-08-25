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

usage() {
  cat <<EOF
Usage: $(basename "$0")

Removes the default node pool from Terraform state, then destroys remaining
Terraform resources (cluster ARM delete cascades remaining pools).
EOF
}

in_state() {
  local address="$1"
  terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -qx "${address}"
}

cmd_destroy() {
  require_cmd terraform

  if in_state "azapi_resource.node_pool"; then
    log "Removing azapi_resource.node_pool from state (OCPBUGS-86702 last-pool delete)"
    terraform -chdir="${TF_DIR}" state rm "azapi_resource.node_pool"
  else
    log "Default node pool not in state; skipping state rm"
  fi

  log "Destroying Terraform resources"
  terraform -chdir="${TF_DIR}" destroy -auto-approve
}

main() {
  load_config
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

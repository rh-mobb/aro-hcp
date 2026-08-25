#!/usr/bin/env bash
# Request or revoke admin kubeconfig credentials.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <request|revoke>

Writes kubeconfig to KUBECONFIG_PATH (default: .kube/config).
EOF
}

request_via_cli() {
  ensure_kubeconfig_dir
  az aro hcp cluster request-credential --admin \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --file "${KUBECONFIG_PATH}" \
    --context "${CLUSTER_NAME}" \
    --overwrite-existing
  log "Kubeconfig written to ${KUBECONFIG_PATH}"
}

request_via_rest() {
  local sub_id async_file headers_file
  sub_id="$(subscription_id)"
  async_file="$(mktemp)"
  headers_file="$(mktemp)"
  trap 'rm -f "${async_file}" "${headers_file}"' RETURN

  log "Requesting admin credential via REST (async)"
  az rest \
    --method POST \
    --uri "/subscriptions/${sub_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${CLUSTER_NAME}/requestAdminCredential?api-version=${API_VERSION}" \
    --verbose 2>"${headers_file}" || true

  local async_url location_url
  async_url="$(grep -i "Azure-AsyncOperation" "${headers_file}" | head -1 | sed -n "s/.*'\(https:[^']*\)'.*/\1/p")"
  location_url="$(grep -i "^Location:" "${headers_file}" | head -1 | sed -n "s/.*'\(https:[^']*\)'.*/\1/p")"

  [[ -n "${async_url}" ]] || die "Failed to extract Azure-AsyncOperation URL"
  [[ -n "${location_url}" ]] || die "Failed to extract Location URL"

  local status="InProgress"
  local attempts=0
  while [[ "${status}" != "Succeeded" && "${attempts}" -lt 60 ]]; do
    status="$(az rest --method GET --uri "${async_url}" --query status -o tsv)"
    log "Async operation status: ${status}"
    if [[ "${status}" == "Failed" ]]; then
      die "Admin credential request failed"
    fi
    sleep 10
    attempts=$((attempts + 1))
  done

  ensure_kubeconfig_dir
  az rest --method GET --uri "${location_url}" -o json | jq -r '.kubeconfig' >"${KUBECONFIG_PATH}"
  log "Kubeconfig written to ${KUBECONFIG_PATH} (REST)"
}

cmd_request() {
  cluster_exists || die "Cluster ${CLUSTER_NAME} does not exist"
  if az aro hcp cluster request-credential -h >/dev/null 2>&1; then
    request_via_cli || request_via_rest
  else
    request_via_rest
  fi
}

cmd_revoke() {
  cluster_exists || die "Cluster ${CLUSTER_NAME} does not exist"
  if az aro hcp cluster revoke-credential -h >/dev/null 2>&1; then
    az aro hcp cluster revoke-credential \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${CLUSTER_NAME}"
  else
    local sub_id
    sub_id="$(subscription_id)"
    az rest \
      --method POST \
      --uri "/subscriptions/${sub_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${CLUSTER_NAME}/revokeCredentials?api-version=${API_VERSION}"
  fi
  log "Admin credentials revoked"
}

main() {
  load_config
  require_cmd az
  require_cmd jq
  local cmd="${1:-}"
  case "${cmd}" in
    request) cmd_request ;;
    revoke) cmd_revoke ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"

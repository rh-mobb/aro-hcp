#!/usr/bin/env bash
# Install and verify tooling for ARO HCP deployment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

ARO_HCP_WHEEL_URL="${ARO_HCP_WHEEL_URL:-https://github.com/bennerv/ARO-HCP/releases/download/0.0.2/aro_hcp-1.0.0b2-py3-none-any.whl}"
WHEEL_DIR="${ROOT_DIR}/.cache/wheels"

check_az_version() {
  require_cmd az
  local version
  version="$(az version --query '"azure-cli"' -o tsv)"
  log "Azure CLI version: ${version}"
}

check_tools() {
  require_cmd jq
  require_cmd terraform
  check_az_version
  if command -v oc >/dev/null 2>&1; then
    log "OpenShift CLI: $(oc version --client 2>/dev/null | head -1 || true)"
  else
    log "WARN: oc not found (required for external-auth and kubeconfig validation)"
  fi
}

install_aro_hcp_extension() {
  if az aro hcp -h >/dev/null 2>&1; then
    log "az aro hcp extension already available"
    return 0
  fi

  mkdir -p "${WHEEL_DIR}"
  local wheel="${WHEEL_DIR}/aro_hcp-1.0.0b2-py3-none-any.whl"
  if [[ ! -f "${wheel}" ]]; then
    log "Downloading aro-hcp CLI extension wheel"
    curl -fsSL -o "${wheel}" "${ARO_HCP_WHEEL_URL}"
  fi

  log "Installing az aro hcp extension from ${wheel}"
  az extension add --source "${wheel}" --yes
  az aro hcp -h >/dev/null 2>&1 || die "az aro hcp extension install failed"
  log "az aro hcp extension installed"
}

main() {
  check_tools
  install_aro_hcp_extension
  log "Setup complete"
}

main "$@"

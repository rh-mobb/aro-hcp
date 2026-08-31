#!/usr/bin/env bash
# List enabled ARO HCP versions for a region via a tiny Terraform root
# (hack/versions). Does not use the cluster stack or az aro hcp get-versions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

VERSIONS_DIR="${ROOT_DIR}/hack/versions"

main() {
  require_cmd terraform
  local location="${LOCATION:-}"
  if [[ -z "${location}" ]]; then
    location="$(tfvars_get location || true)"
  fi
  location="${location:-uksouth}"
  log "Listing enabled HCP versions in ${location}"
  terraform -chdir="${VERSIONS_DIR}" init -backend=false -input=false
  terraform -chdir="${VERSIONS_DIR}" apply -auto-approve -input=false \
    -var="location=${location}"
  terraform -chdir="${VERSIONS_DIR}" output
}

main "$@"

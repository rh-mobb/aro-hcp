#!/usr/bin/env bash
# List available OpenShift versions for a region.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

main() {
  load_config
  require_cmd az
  az aro hcp get-versions --location "${LOCATION}" -o table
}

main "$@"

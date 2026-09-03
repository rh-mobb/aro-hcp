#!/usr/bin/env bash
# Write clusters/<profile>/platform.json from terraform output -json platform.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_tf
require_cmd terraform
require_cmd jq

: "${TFVARS:?TFVARS is required}"
out_dir="$(cd "$(dirname "${TFVARS}")" && pwd)"
out_file="${out_dir}/platform.json"

json="$(tf_output_json platform)" || die "terraform output -json platform failed. Run make cluster.${CLUSTER:-<profile>}.apply first."

contract="$(printf '%s' "${json}" | jq -r '.contract_version // empty')"
[[ "${contract}" == "1" ]] || die "platform.contract_version must be 1 (got '${contract:-empty}'). Re-apply this installer."

printf '%s\n' "${json}" | jq . >"${out_file}"
log "Wrote ${out_file}"

#!/usr/bin/env bash
# Jump box helpers: generate SSH key, print sshuttle command.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

JUMP_KEY_PATH="${JUMP_KEY_PATH:-${ROOT_DIR}/config/jump}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <key|show>
EOF
}

cmd_key() {
  local pub="${JUMP_KEY_PATH}.pub"
  if [[ -f "${JUMP_KEY_PATH}" ]]; then
    log "SSH key ${JUMP_KEY_PATH} already exists; skipping"
    return 0
  fi
  mkdir -p "$(dirname "${JUMP_KEY_PATH}")"
  ssh-keygen -t ed25519 -f "${JUMP_KEY_PATH}" -N "" -C "aro-hcp-jump"
  chmod 600 "${JUMP_KEY_PATH}"
  log "Wrote ${JUMP_KEY_PATH} and ${pub}"
}

cmd_show() {
  load_config
  require_cmd terraform
  local ip cmd
  ip="$(tf_output jump_public_ip || true)"
  if [[ -z "${ip}" || "${ip}" == "null" ]]; then
    die "Jump box is not enabled (ENABLE_JUMPBOX=true and make apply). terraform output jump_public_ip is empty"
  fi
  cmd="$(tf_output jump_sshuttle_command)"
  printf '%s\n' "${cmd}"
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    key) cmd_key ;;
    show)
      cmd_show
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"

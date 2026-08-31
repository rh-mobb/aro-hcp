#!/usr/bin/env bash
# Jump box helpers: SSH key, sshuttle command, background tunnel.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

JUMP_KEY_PATH="${JUMP_KEY_PATH:-${ROOT_DIR}/clusters/${CLUSTER:-public}/jump}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <key|show|connect|disconnect|status>

connect     - Start sshuttle in the background (writes clusters/<profile>/sshuttle.pid)
disconnect  - Stop background sshuttle for this cluster profile
status      - Show whether sshuttle is running for this profile
show        - Print foreground sshuttle command
EOF
}

sshuttle_pidfile() {
  if [[ -n "${SSHUTTLE_PIDFILE:-}" ]]; then
    printf '%s\n' "${SSHUTTLE_PIDFILE}"
    return 0
  fi
  : "${CLUSTER:?CLUSTER profile required (run via make cluster.<profile>.sshuttle.connect)}"
  printf '%s\n' "${ROOT_DIR}/clusters/${CLUSTER}/sshuttle.pid"
}

sshuttle_running() {
  local pidfile pid
  pidfile="$(sshuttle_pidfile)"
  [[ -f "${pidfile}" ]] || return 1
  pid="$(<"${pidfile}")"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

require_jumpbox() {
  require_cmd terraform
  local ip
  ip="$(tf_output jump_public_ip || true)"
  if [[ -z "${ip}" || "${ip}" == "null" ]]; then
    die "Jump box is not enabled (enable_jumpbox = true and make cluster.<profile>.apply). terraform output jump_public_ip is empty"
  fi
  [[ -f "${JUMP_KEY_PATH}" ]] || die "Missing ${JUMP_KEY_PATH}. Run: make cluster.${CLUSTER}.jump-key"
}

vnet_address_prefix() {
  local prefix
  prefix="$(resolve_tf address_prefix || true)"
  if [[ -z "${prefix}" || "${prefix}" == "null" ]]; then
    prefix="10.0.0.0/16"
  fi
  printf '%s\n' "${prefix}"
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
  require_jumpbox
  local cmd
  cmd="$(tf_output jump_sshuttle_command)"
  printf '%s\n' "${cmd}"
}

cmd_connect() {
  require_cmd sshuttle
  require_jumpbox
  local pidfile ip user prefix
  pidfile="$(sshuttle_pidfile)"
  if sshuttle_running; then
    log "sshuttle already running (pid $(<"${pidfile}")); ${pidfile}"
    return 0
  fi
  rm -f "${pidfile}"
  ip="$(tf_output jump_public_ip)"
  user="$(tf_output jump_ssh_user)"
  prefix="$(vnet_address_prefix)"
  mkdir -p "$(dirname "${pidfile}")"
  sshuttle -r "${user}@${ip}" --dns --daemon --pidfile "${pidfile}" \
    -e "ssh -o StrictHostKeyChecking=accept-new -i ${JUMP_KEY_PATH}" "${prefix}"
  log "sshuttle started (pid $(<"${pidfile}")); routes ${prefix} via ${user}@${ip}"
}

cmd_disconnect() {
  local pidfile pid
  pidfile="$(sshuttle_pidfile)"
  if [[ ! -f "${pidfile}" ]]; then
    log "sshuttle not running (no ${pidfile})"
    return 0
  fi
  pid="$(<"${pidfile}")"
  if kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}"
    for _ in $(seq 1 10); do
      kill -0 "${pid}" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "${pid}" 2>/dev/null; then
      kill -9 "${pid}" 2>/dev/null || true
    fi
  fi
  rm -f "${pidfile}"
  log "sshuttle stopped"
}

cmd_status() {
  local pidfile
  pidfile="$(sshuttle_pidfile)"
  if sshuttle_running; then
    log "sshuttle running (pid $(<"${pidfile}")); ${pidfile}"
    return 0
  fi
  if [[ -f "${pidfile}" ]]; then
    log "stale pid file ${pidfile}; run disconnect to clean up"
    return 1
  fi
  log "sshuttle not running for cluster profile ${CLUSTER}"
  return 1
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    key) cmd_key ;;
    show) cmd_show ;;
    connect) cmd_connect ;;
    disconnect) cmd_disconnect ;;
    status) cmd_status ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"

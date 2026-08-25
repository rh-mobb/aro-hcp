#!/usr/bin/env bash
# Shared helpers for ARO HCP deployment scripts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${ROOT_DIR}/config/cluster.env}"
TF_DIR="${ROOT_DIR}/terraform"

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
}

load_config() {
  [[ -f "${CONFIG_FILE}" ]] || die "Config not found: ${CONFIG_FILE} (copy config/cluster.env.example)"
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
  : "${LOCATION:?LOCATION required}"
  : "${CLUSTER_NAME:?CLUSTER_NAME required}"
  : "${RESOURCE_GROUP:?RESOURCE_GROUP required}"
  : "${MANAGED_RESOURCE_GROUP:=${CLUSTER_NAME}-managed}"
  : "${KUBECONFIG_PATH:=${ROOT_DIR}/.kube/config}"
  : "${API_VERSION:=2026-06-30-preview}"
  : "${CLUSTER_VERSION:=4.20}"
  : "${CLUSTER_CHANNEL:=stable}"
  : "${NODEPOOL_NAME:=np-1}"
  : "${NODEPOOL_REPLICAS:=2}"
  : "${NODEPOOL_VM_SIZE:=Standard_D4s_v6}"
  : "${NODEPOOL_CHANNEL:=${CLUSTER_CHANNEL}}"
  : "${NODEPOOL_VERSION:=${CLUSTER_VERSION}}"
  : "${EXTERNAL_AUTH_NAME:=entra}"
  : "${APP_DISPLAY_NAME:=${CLUSTER_NAME}-auth}"
}

tf_output() {
  local name="$1"
  terraform -chdir="${TF_DIR}" output -raw "${name}"
}

tf_output_json() {
  local name="${1:-}"
  if [[ -n "${name}" ]]; then
    terraform -chdir="${TF_DIR}" output -json "${name}"
  else
    terraform -chdir="${TF_DIR}" output -json
  fi
}

subscription_id() {
  az account show --query id -o tsv
}

cluster_exists() {
  az aro hcp cluster show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    >/dev/null 2>&1
}

nodepool_exists() {
  local name="${1:-${NODEPOOL_NAME}}"
  az aro hcp cluster nodepool show \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    --name "${name}" \
    >/dev/null 2>&1
}

external_auth_exists() {
  az aro hcp cluster external-auth show \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    --name "${EXTERNAL_AUTH_NAME}" \
    >/dev/null 2>&1
}

ensure_kubeconfig_dir() {
  mkdir -p "$(dirname "${KUBECONFIG_PATH}")"
}

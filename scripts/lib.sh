#!/usr/bin/env bash
# Shared helpers for ARO HCP deployment scripts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform"
CLUSTER="${CLUSTER:-}"
TFVARS="${TFVARS:-}"

if [[ -z "${TFVARS}" && -n "${CLUSTER}" ]]; then
  TFVARS="${ROOT_DIR}/clusters/${CLUSTER}/terraform.tfvars"
fi

if [[ -z "${TFVARS}" ]]; then
  TFVARS="${ROOT_DIR}/clusters/public/terraform.tfvars"
fi

if [[ -n "${CLUSTER:-}" ]]; then
  export TF_DATA_DIR="${ROOT_DIR}/clusters/${CLUSTER}/.terraform"
fi

cluster_tf_data_dir() {
  local cluster="${1:-${CLUSTER}}"
  : "${cluster:?CLUSTER or cluster name required}"
  printf '%s\n' "${ROOT_DIR}/clusters/${cluster}/.terraform"
}

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

# Read a string/number/bool from terraform.tfvars (simple `key = value` lines).
tfvars_get() {
  local key="$1"
  [[ -f "${TFVARS}" ]] || return 1
  awk -v k="${key}" '
    $1 == k && $2 == "=" {
      val = $3
      for (i = 4; i <= NF; i++) val = val " " $i
      gsub(/^[ \t"]+|[ \t",]+$/, "", val)
      print val
      exit
    }
  ' "${TFVARS}"
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

# Prefer terraform output (after apply); fall back to terraform.tfvars (pre-apply).
resolve_tf() {
  local name="$1"
  local val=""
  val="$(terraform -chdir="${TF_DIR}" output -raw "${name}" 2>/dev/null || true)"
  if [[ -n "${val}" && "${val}" != "null" ]]; then
    printf '%s\n' "${val}"
    return 0
  fi
  tfvars_get "${name}"
}

load_tf() {
  # GNU Make may export CLUSTER_NAME=profile dir (e.g. public); always resolve Azure names from state/tfvars.
  if [[ -n "${CLUSTER:-}" && "${CLUSTER_NAME:-}" == "${CLUSTER}" ]]; then
    unset CLUSTER_NAME
  fi
  if [[ -n "${CLUSTER:-}" && -z "${TF_DATA_DIR:-}" ]]; then
    export TF_DATA_DIR="${ROOT_DIR}/clusters/${CLUSTER}/.terraform"
  fi

  CLUSTER_NAME="${CLUSTER_NAME:-$(resolve_tf cluster_name || true)}"
  RESOURCE_GROUP="${RESOURCE_GROUP:-$(resolve_tf resource_group_name || true)}"
  LOCATION="${LOCATION:-$(resolve_tf location || true)}"
  MANAGED_RESOURCE_GROUP="${MANAGED_RESOURCE_GROUP:-$(resolve_tf managed_resource_group_name || true)}"
  CLUSTER_VERSION="${CLUSTER_VERSION:-$(resolve_tf cluster_version || true)}"
  CLUSTER_CHANNEL="${CLUSTER_CHANNEL:-$(resolve_tf cluster_channel || true)}"
  NODEPOOL_NAME="${NODEPOOL_NAME:-$(resolve_tf node_pool_name || true)}"
  NODEPOOL_REPLICAS="${NODEPOOL_REPLICAS:-$(resolve_tf node_pool_replicas || true)}"
  NODEPOOL_VM_SIZE="${NODEPOOL_VM_SIZE:-$(resolve_tf node_pool_vm_size || true)}"
  NODEPOOL_CHANNEL="${NODEPOOL_CHANNEL:-$(resolve_tf node_pool_channel || true)}"
  NODEPOOL_VERSION="${NODEPOOL_VERSION:-$(resolve_tf node_pool_version || true)}"
  API_VISIBILITY="${API_VISIBILITY:-$(resolve_tf api_visibility || true)}"
  INGRESS_VISIBILITY="${INGRESS_VISIBILITY:-$(resolve_tf ingress_visibility || true)}"

  : "${CLUSTER_NAME:?cluster_name required (terraform output or clusters/<name>/terraform.tfvars)}"
  : "${RESOURCE_GROUP:=${CLUSTER_NAME}-rg}"
  : "${LOCATION:?location required (terraform output or clusters/<name>/terraform.tfvars)}"
  : "${MANAGED_RESOURCE_GROUP:=${CLUSTER_NAME}-managed}"
  : "${KUBECONFIG_PATH:=${ROOT_DIR}/.kube/config}"
  : "${API_VERSION:=2026-06-30-preview}"
  : "${CLUSTER_VERSION:=4.22}"
  : "${CLUSTER_CHANNEL:=stable}"
  : "${NODEPOOL_NAME:=np-1}"
  : "${NODEPOOL_REPLICAS:=2}"
  : "${NODEPOOL_VM_SIZE:=Standard_D4s_v6}"
  : "${NODEPOOL_CHANNEL:=${CLUSTER_CHANNEL}}"
  : "${NODEPOOL_VERSION:=${CLUSTER_VERSION}}"
  : "${EXTERNAL_AUTH_NAME:=entra}"
  : "${APP_DISPLAY_NAME:=${CLUSTER_NAME}-auth}"
  : "${API_VISIBILITY:=Public}"
  : "${INGRESS_VISIBILITY:=Public}"
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

# Expand ~ and export TF_VAR_pull_secret_path as an absolute file path.
# No-op when PULL_SECRET_PATH is unset. Dies if the file is missing.
export_tf_var_pull_secret_path() {
  local p="${PULL_SECRET_PATH:-}"
  [[ -n "${p}" ]] || return 0
  p="${p/#\~/${HOME}}"
  [[ -f "${p}" ]] || die "Missing pull secret file ${p} (PULL_SECRET_PATH)"
  TF_VAR_pull_secret_path="$(cd "$(dirname "${p}")" && pwd)/$(basename "${p}")"
  export TF_VAR_pull_secret_path
}

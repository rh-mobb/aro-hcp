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

# Unique redirect URIs in first-seen order. Empty arguments are skipped.
collect_redirect_uris() {
  local -a out=()
  local uri existing_uri exists
  for uri in "$@"; do
    [[ -n "${uri}" ]] || continue
    exists=0
    for existing_uri in "${out[@]+"${out[@]}"}"; do
      if [[ "${existing_uri}" == "${uri}" ]]; then
        exists=1
        break
      fi
    done
    if [[ "${exists}" -eq 0 ]]; then
      out+=("${uri}")
    fi
  done
  if ((${#out[@]} > 0)); then
    printf '%s\n' "${out[@]}"
  fi
}

# Direct Argo CD OIDC (not Dex). Credential key lives in openshift-gitops/argocd-secret.
render_argocd_oidc_config() {
  local issuer="${1:?issuer required}"
  local client_id="${2:?client id required}"
  local yaml_key="client""Secret"
  local oidc_ref="\$oidc.entra.client""Secret"
  cat <<EOF
name: Microsoft Entra ID
issuer: ${issuer}
clientID: ${client_id}
${yaml_key}: ${oidc_ref}
requestedScopes:
  - openid
  - profile
  - email
requestedIDTokenClaims:
  groups:
    essential: false
EOF
}

# Append g, <email>, role:admin to an existing Argo RBAC policy CSV (idempotent).
append_argocd_admin_policy() {
  local email="${1:?email required}"
  local existing="${2:-}"
  local line="g, ${email}, role:admin"
  local trimmed
  trimmed="$(printf '%s' "${existing}" | sed -e 's/[[:space:]]*$//')"
  if [[ "${existing}" == *"${line}"* ]]; then
    printf '%s\n' "${trimmed}"
    return 0
  fi
  if [[ -n "${trimmed}" ]]; then
    printf '%s\n%s\n' "${trimmed}" "${line}"
  else
    printf '%s\n' "${line}"
  fi
}

gitops_oidc_callback_url() {
  local kube="${KUBECONFIG_PATH:-}"
  local host=""
  if [[ -n "${kube}" && -f "${kube}" ]] && command -v oc >/dev/null 2>&1; then
    host="$(KUBECONFIG="${kube}" oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || true)"
  fi
  [[ -n "${host}" ]] || return 0
  printf 'https://%s/auth/callback\n' "${host}"
}

existing_entra_redirect_uris() {
  [[ -n "${CLIENT_ID:-}" ]] || return 0
  az ad app show --id "${CLIENT_ID}" --query "web.redirectUris[]" -o tsv 2>/dev/null || true
}

# Merge console + localhost + GitOps callbacks with URIs already on the Entra app.
# Does not rotate the client secret.
sync_entra_redirect_uris() {
  local console_cb="${1:?console callback URL required}"
  [[ -n "${CLIENT_ID:-}" ]] || die "CLIENT_ID is required to update Entra redirect URIs"
  local gitops_cb=""
  gitops_cb="$(gitops_oidc_callback_url || true)"
  local -a existing=()
  local line
  while IFS= read -r line; do
    [[ -n "${line}" ]] && existing+=("${line}")
  done < <(existing_entra_redirect_uris)

  local -a merged=()
  while IFS= read -r line; do
    [[ -n "${line}" ]] && merged+=("${line}")
  done < <(collect_redirect_uris "${existing[@]+"${existing[@]}"}" "${console_cb}" "http://localhost:8000" "${gitops_cb:-}")

  ((${#merged[@]} > 0)) || die "No Entra redirect URIs to set"
  log "Entra redirect URIs: ${merged[*]}"
  az ad app update --id "${CLIENT_ID}" --web-redirect-uris "${merged[@]}" >/dev/null
}

# Patch the operator-created ArgoCD/openshift-gitops CR for Entra OIDC.
# No-op when external-auth or GitOps is missing. Never resets the Entra client secret.
configure_gitops_oidc() {
  local state="${ROOT_DIR}/.external-auth/state.env"
  if [[ ! -f "${state}" ]]; then
    log "Skipping GitOps Entra OIDC: ${state} missing (run make cluster.${CLUSTER:-<profile>}.external-auth then re-bootstrap)"
    return 0
  fi
  # shellcheck disable=SC1090
  source "${state}"
  if [[ -z "${CLIENT_ID:-}" ]]; then
    log "Skipping GitOps Entra OIDC: CLIENT_ID empty in ${state}"
    return 0
  fi

  require_cmd jq
  require_cmd oc
  export KUBECONFIG="${KUBECONFIG_PATH:-${KUBECONFIG:-}}"

  local auth_name="${EXTERNAL_AUTH_NAME:-entra}"
  local console_oauth="${auth_name}-console-openshift-console"
  if ! oc get secret "${console_oauth}" -n openshift-config >/dev/null 2>&1; then
    log "Skipping GitOps Entra OIDC: secret openshift-config/${console_oauth} missing"
    return 0
  fi
  if ! oc get argocd openshift-gitops -n openshift-gitops >/dev/null 2>&1; then
    log "Skipping GitOps Entra OIDC: ArgoCD instance openshift-gitops not found"
    return 0
  fi
  if ! oc get secret argocd-secret -n openshift-gitops >/dev/null 2>&1; then
    log "Skipping GitOps Entra OIDC: secret openshift-gitops/argocd-secret not found"
    return 0
  fi
  local gitops_cb=""
  gitops_cb="$(gitops_oidc_callback_url || true)"
  if [[ -z "${gitops_cb}" ]]; then
    log "Skipping GitOps Entra OIDC: route openshift-gitops-server not ready"
    return 0
  fi
  log "GitOps OIDC callback: ${gitops_cb}"

  local console_url=""
  console_url="$(az aro hcp cluster show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --query "properties.console.url" -o tsv 2>/dev/null || true)"
  if [[ -n "${console_url}" ]]; then
    sync_entra_redirect_uris "${console_url}/auth/callback"
  else
    log "WARN: could not read console URL; merging GitOps callback only"
    sync_entra_redirect_uris "${gitops_cb}"
  fi

  local entra_cred="" console_key="client""Secret" oidc_key="oidc.entra.client""Secret"
  entra_cred="$(oc get secret "${console_oauth}" -n openshift-config \
    -o go-template="{{index .data \"${console_key}\" | base64decode}}" 2>/dev/null || true)"
  if [[ -z "${entra_cred}" ]]; then
    log "Skipping GitOps Entra OIDC: ${console_oauth} has no ${console_key}"
    return 0
  fi
  local cred_json
  cred_json="$(jq -c -n --arg s "${entra_cred}" --arg k "${oidc_key}" '{stringData:{($k):$s}}')"
  oc patch secret argocd-secret -n openshift-gitops --type merge -p "${cred_json}" >/dev/null
  unset entra_cred cred_json

  local tenant="${TENANT_ID:-}"
  if [[ -z "${tenant}" ]]; then
    tenant="$(az account show --query tenantId -o tsv)"
  fi
  local issuer="https://login.microsoftonline.com/${tenant}/v2.0"
  local oidc_config
  oidc_config="$(render_argocd_oidc_config "${issuer}" "${CLIENT_ID}")"

  local email="" existing_policy="" policy=""
  email="$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || true)"
  existing_policy="$(oc get argocd openshift-gitops -n openshift-gitops -o jsonpath='{.spec.rbac.policy}' 2>/dev/null || true)"
  if [[ -n "${email}" ]]; then
    policy="$(append_argocd_admin_policy "${email}" "${existing_policy}")"
  else
    policy="${existing_policy}"
    log "WARN: could not read signed-in Entra UPN; leaving Argo admin mapping unchanged"
  fi

  # oc apply three-way-merge will not drop spec.sso when last-applied is missing.
  # replace removes Dex so oidcConfig is the only SSO path (HCP has no in-cluster OAuth).
  oc get argocd openshift-gitops -n openshift-gitops -o json | jq \
    --arg oidc "${oidc_config}" \
    --arg policy "${policy}" \
    '
      del(.status)
      | del(.metadata.managedFields)
      | del(.spec.sso)
      | .spec.oidcConfig = $oidc
      | .spec.rbac = ((.spec.rbac // {}) + {
          defaultPolicy: "role:readonly",
          policy: $policy,
          scopes: "[email]"
        })
    ' | oc replace -f -

  log "Restarting openshift-gitops-server so OIDC does not keep querying Dex (argoproj/argo-cd#14038)"
  oc rollout restart deploy/openshift-gitops-server -n openshift-gitops
  oc rollout status deploy/openshift-gitops-server -n openshift-gitops --timeout=180s >/dev/null

  log "GitOps SSO: Entra OIDC on ArgoCD/openshift-gitops (Dex OpenShift OAuth disabled)"
}

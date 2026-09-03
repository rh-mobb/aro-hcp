#!/usr/bin/env bash
# Bootstrap OpenShift GitOps (OLM Classic) and plant the root Argo Application.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

GITOPS_DIR="${ROOT_DIR}/gitops"
GITOPS_REPO="${GITOPS_REPO:-https://github.com/rh-mobb/validated-pattern-aro-hcp.git}"
GITOPS_REVISION="${GITOPS_REVISION:-main}"
# Argo Application path prefix. Default matches this repo. A cluster-config
# repo (e.g. validated-pattern-aro-hcp-cluster-config) uses overlays/public|private|aro-virt.
GITOPS_SOURCE_ROOT="${GITOPS_SOURCE_ROOT:-gitops/overlays}"
GITOPS_WAIT_SECONDS="${GITOPS_WAIT_SECONDS:-900}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${ROOT_DIR}/.kube/config}"

overlay_name() {
  if [[ -n "${GITOPS_OVERLAY:-}" ]]; then
    printf '%s\n' "${GITOPS_OVERLAY}"
    return
  fi
  if [[ -n "${CLUSTER:-}" && -d "${GITOPS_DIR}/overlays/${CLUSTER}" ]]; then
    printf '%s\n' "${CLUSTER}"
    return
  fi
  case "${API_VISIBILITY:-}" in
    Private) printf '%s\n' private ;;
    "")
      if [[ -z "${CLUSTER:-}" ]]; then
        printf '%s\n' public
      fi
      ;;
    *) printf '%s\n' public ;;
  esac
}

kustomize_build() {
  local path="$1"
  if command -v oc >/dev/null 2>&1; then
    oc kustomize "${path}"
  elif command -v kubectl >/dev/null 2>&1; then
    kubectl kustomize "${path}"
  else
    die "oc or kubectl is required to build Kustomize (gitops/)"
  fi
}

overlay_git_path() {
  local overlay="${1:?overlay name required}"
  printf '%s/%s\n' "${GITOPS_SOURCE_ROOT}" "${overlay}"
}

render_root_application() {
  local overlay="$1"
  local src="${GITOPS_DIR}/argocd/root-application.yaml"
  awk -v repo="${GITOPS_REPO}" -v rev="${GITOPS_REVISION}" -v gpath="$(overlay_git_path "${overlay}")" '
    $1 == "repoURL:" { printf "    repoURL: %s\n", repo; next }
    $1 == "targetRevision:" { printf "    targetRevision: %s\n", rev; next }
    $1 == "path:" { printf "    path: %s\n", gpath; next }
    { print }
  ' "${src}"
}

assert_api_reachable() {
  export KUBECONFIG="${KUBECONFIG_PATH}"
  if oc whoami >/dev/null 2>&1; then
    return 0
  fi
  local hint=""
  if [[ "${API_VISIBILITY:-Public}" == "Private" ]]; then
    hint=" Private API: run make cluster.${CLUSTER:-<profile>}.sshuttle.connect first."
  fi
  die "Cannot reach the cluster API (oc whoami failed). Run make cluster.${CLUSTER:-<profile>}.kubeconfig.${hint}"
}

# HCP: do not patch openshift-config/pull-secret. HCCO merges kube-system/additional-pull-secret
# with the HostedCluster pull secret and syncs kubelet via global-pull-secret-syncer.
PULL_SECRET_TMP=""
PULL_SECRET_FILE=""
PULL_SECRET_SOURCE=""
cleanup_pull_secret_tmp() {
  if [[ -n "${PULL_SECRET_TMP:-}" && -f "${PULL_SECRET_TMP}" ]]; then
    rm -f "${PULL_SECRET_TMP}"
  fi
}
trap cleanup_pull_secret_tmp EXIT

resolve_pull_secret_file() {
  local src="${PULL_SECRET_PATH:-}"
  src="${src/#\~/${HOME}}"
  PULL_SECRET_SOURCE=""
  PULL_SECRET_FILE=""
  if [[ -n "${src}" ]]; then
    [[ -f "${src}" ]] || die "PULL_SECRET_PATH=${src} does not exist"
    PULL_SECRET_FILE="${src}"
    PULL_SECRET_SOURCE="${src}"
    return 0
  fi

  local vault name tmp
  vault="${KEY_VAULT_NAME:-$(resolve_tf key_vault_name || true)}"
  name="${PULL_SECRET_KEY_VAULT_SECRET_NAME:-$(resolve_tf pull_secret_key_vault_secret_name || true)}"
  name="${name:-redhat-pull-secret}"
  if [[ -z "${vault}" || "${vault}" == "null" ]]; then
    die "HCP OperatorHub needs kube-system/additional-pull-secret for registry.redhat.io. Set PULL_SECRET_PATH to a dockerconfigjson file (https://console.redhat.com/openshift/downloads), or apply with PULL_SECRET_PATH so Terraform stores it in Key Vault."
  fi
  require_cmd az
  tmp="$(mktemp)"
  if ! az keyvault secret show --vault-name "${vault}" --name "${name}" --query value -o tsv >"${tmp}" 2>/dev/null; then
    rm -f "${tmp}"
    die "HCP OperatorHub needs kube-system/additional-pull-secret for registry.redhat.io. Key Vault ${vault}/${name} is missing. Set PULL_SECRET_PATH to a dockerconfigjson file and re-apply (Terraform writes the secret), or pass PULL_SECRET_PATH to bootstrap."
  fi
  if [[ ! -s "${tmp}" ]]; then
    rm -f "${tmp}"
    die "Key Vault ${vault}/${name} is empty. Set PULL_SECRET_PATH to a dockerconfigjson file and re-apply."
  fi
  PULL_SECRET_TMP="${tmp}"
  PULL_SECRET_FILE="${tmp}"
  PULL_SECRET_SOURCE="Key Vault ${vault}/${name}"
}

ensure_additional_pull_secret() {
  if oc get secret additional-pull-secret -n kube-system >/dev/null 2>&1; then
    log "kube-system/additional-pull-secret already present"
    return 0
  fi
  resolve_pull_secret_file
  log "Applying kube-system/additional-pull-secret from ${PULL_SECRET_SOURCE}"
  oc create secret generic additional-pull-secret \
    -n kube-system \
    --type=kubernetes.io/dockerconfigjson \
    --from-file=".dockerconfigjson=${PULL_SECRET_FILE}" \
    --dry-run=client -o yaml | oc apply -f -
}

cmd_ensure_pull_secret() {
  require_cmd oc
  load_tf
  export KUBECONFIG="${KUBECONFIG_PATH}"
  ensure_additional_pull_secret
}

wait_for_global_pull_secret() {
  local deadline=$((SECONDS + GITOPS_WAIT_SECONDS))
  log "Waiting for kube-system/global-pull-secret (HCCO merge)"
  while ((SECONDS < deadline)); do
    if oc get secret global-pull-secret -n kube-system >/dev/null 2>&1; then
      log "global-pull-secret present"
      return 0
    fi
    sleep 5
  done
  die "Timed out waiting for kube-system/global-pull-secret. Check additional-pull-secret JSON and DaemonSet global-pull-secret-syncer."
}

wait_for_csv_succeeded() {
  local ns="$1"
  local sub="$2"
  local deadline=$((SECONDS + GITOPS_WAIT_SECONDS))
  local csv=""
  log "Waiting for Subscription ${ns}/${sub} CSV to Succeeded (timeout ${GITOPS_WAIT_SECONDS}s)"
  while ((SECONDS < deadline)); do
    csv="$(oc get subscription "${sub}" -n "${ns}" -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
    if [[ -n "${csv}" ]]; then
      local phase
      phase="$(oc get csv "${csv}" -n "${ns}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
      if [[ "${phase}" == "Succeeded" ]]; then
        log "CSV ${csv} Succeeded"
        return 0
      fi
    fi
    sleep 10
  done
  die "Timed out waiting for ${ns}/${sub} CSV Succeeded"
}

PLATFORM_METADATA_NS="${PLATFORM_METADATA_NS:-openshift-gitops}"
PLATFORM_METADATA_NAME="${PLATFORM_METADATA_NAME:-aro-platform-metadata}"

render_platform_metadata() {
  local cluster tenant client vault_uri vault_name secret_name
  cluster="$(resolve_tf cluster_name || true)"
  tenant="$(resolve_tf tenant_id || true)"
  client="$(resolve_tf eso_client_id || true)"
  vault_uri="$(resolve_tf key_vault_uri || true)"
  vault_name="$(resolve_tf key_vault_name || true)"
  secret_name="$(resolve_tf pull_secret_key_vault_secret_name || true)"
  secret_name="${secret_name:-redhat-pull-secret}"

  cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${PLATFORM_METADATA_NAME}
  namespace: ${PLATFORM_METADATA_NS}
  labels:
    app.kubernetes.io/name: aro-platform-metadata
data:
  clusterName: ${cluster}
  azureTenantId: ${tenant}
  esoClientId: ${client}
  keyVaultUri: ${vault_uri}
  keyVaultName: ${vault_name}
  pullSecretKeyVaultSecretName: ${secret_name}
EOF
}

publish_platform_metadata() {
  local client
  client="$(resolve_tf eso_client_id || true)"
  if [[ -z "${client}" || "${client}" == "null" ]]; then
    die "terraform output eso_client_id is empty. Re-run make cluster.${CLUSTER:-<profile>}.apply so the ESO identity exists, then bootstrap."
  fi
  log "Publishing ${PLATFORM_METADATA_NS}/${PLATFORM_METADATA_NAME}"
  render_platform_metadata | oc apply -f -
}

wait_for_argocd() {
  local deadline=$((SECONDS + GITOPS_WAIT_SECONDS))
  log "Waiting for Argo CD instance openshift-gitops"
  while ((SECONDS < deadline)); do
    if oc get argocd openshift-gitops -n openshift-gitops >/dev/null 2>&1; then
      if oc get deploy openshift-gitops-server -n openshift-gitops >/dev/null 2>&1; then
        oc wait --for=condition=available deploy/openshift-gitops-server \
          -n openshift-gitops --timeout=60s >/dev/null 2>&1 && return 0
      fi
    fi
    sleep 10
  done
  die "Timed out waiting for Argo CD (openshift-gitops) to be available"
}

cmd_bootstrap() {
  if [[ "${GITOPS_DRY_RUN:-}" != "1" ]]; then
    require_cmd oc
    load_tf
    export KUBECONFIG="${KUBECONFIG_PATH}"
    [[ -f "${KUBECONFIG_PATH}" ]] || die "Missing ${KUBECONFIG_PATH}. Run make cluster.${CLUSTER:-<profile>}.kubeconfig"
  fi

  local overlay
  overlay="$(overlay_name)"
  local overlay_dir="${GITOPS_DIR}/overlays/${overlay}"
  if [[ -z "${overlay}" || ! -d "${overlay_dir}" ]]; then
    die "Unknown GitOps overlay '${overlay:-${CLUSTER:-}}' (expected ${overlay_dir}). Set GITOPS_OVERLAY=public, private, or aro-virt."
  fi

  if [[ "${GITOPS_DRY_RUN:-}" == "1" ]]; then
    kustomize_build "${GITOPS_DIR}/bootstrap"
    echo "---"
    kustomize_build "${overlay_dir}"
    echo "---"
    render_platform_metadata
    echo "---"
    render_root_application "${overlay}"
    echo "---"
    echo "# Argo CD Entra OIDC (applied when external-auth + GitOps route exist; not in git)"
    render_argocd_oidc_config "https://login.microsoftonline.com/\${tenantId}/v2.0" "CLIENT_ID"
    return 0
  fi

  assert_api_reachable
  ensure_additional_pull_secret
  wait_for_global_pull_secret
  oc delete pods -n openshift-marketplace --field-selector=status.phase=Pending --ignore-not-found >/dev/null 2>&1 || true

  log "Applying GitOps operator (gitops/bootstrap)"
  oc apply -k "${GITOPS_DIR}/bootstrap"
  wait_for_csv_succeeded openshift-gitops-operator openshift-gitops-operator
  wait_for_argocd

  log "Publishing platform metadata for GitOps (ESO workload identity)"
  publish_platform_metadata

  log "Applying overlay gitops/overlays/${overlay}"
  oc apply -k "${overlay_dir}"

  log "Planting root Application (repo=${GITOPS_REPO} revision=${GITOPS_REVISION} path=$(overlay_git_path "${overlay}"))"
  render_root_application "${overlay}" | oc apply -f -

  configure_gitops_oidc

  log "GitOps bootstrap complete. Argo CD syncs $(overlay_git_path "${overlay}") (prune=false)."
  log "Do not install these operators again from Software Catalog (Classic would fight this Subscription)."
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [bootstrap|ensure-pull-secret]

Install OpenShift GitOps, apply gitops/overlays/<profile>, plant the root Argo Application.

Environment:
  CLUSTER              Profile directory under clusters/ (may not match an overlay name)
  GITOPS_OVERLAY       Overlay directory (public, private, aro-virt, or a custom overlay)
  GITOPS_REPO          Git URL (default: https://github.com/rh-mobb/validated-pattern-aro-hcp.git)
  GITOPS_REVISION      Branch/tag/commit (default: main)
  GITOPS_SOURCE_ROOT   Argo path prefix (default: gitops/overlays). Use overlays for validated-pattern-aro-hcp-cluster-config.
  GITOPS_DRY_RUN=1     Print kustomize, platform-metadata ConfigMap, Application YAML, and Entra oidcConfig; do not talk to the cluster
  KUBECONFIG_PATH      Default: .kube/config
  PULL_SECRET_PATH     dockerconfigjson file → kube-system/additional-pull-secret (overrides Key Vault)
  KEY_VAULT_NAME       Override terraform output key_vault_name
  PULL_SECRET_KEY_VAULT_SECRET_NAME  Override terraform output (default redhat-pull-secret)
EOF
}

main() {
  local cmd="${1:-bootstrap}"
  case "${cmd}" in
    bootstrap) cmd_bootstrap ;;
    ensure-pull-secret) cmd_ensure_pull_secret ;;
    -h | --help | help) usage ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"

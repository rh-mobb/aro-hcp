#!/usr/bin/env bash
# Configure Microsoft Entra ID external authentication for ARO HCP.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

STATE_DIR="${ROOT_DIR}/.external-auth"
STATE_FILE="${STATE_DIR}/state.env"

usage() {
  cat <<EOF
Usage: $(basename "$0") <create|show|delete|login|rbac-user|rbac-group>

create  - Entra app + external-auth + console secret
show    - Show external-auth configuration
delete  - Remove external-auth, console secret, Entra app
login   - oc login via oc-oidc exec plugin
rbac-user  - ClusterRoleBinding for current Entra user (email)
rbac-group - ClusterRoleBinding for Entra group (GROUP_ID= required)
EOF
}

save_state() {
  mkdir -p "${STATE_DIR}"
  cat >"${STATE_FILE}" <<EOF
CLIENT_ID=${CLIENT_ID}
APP_OBJECT_ID=${APP_OBJECT_ID:-}
EOF
}

load_state() {
  [[ -f "${STATE_FILE}" ]] || return 1
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
}

console_callback_url() {
  az aro hcp cluster show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --query "properties.console.url" -o tsv
}

create_entra_app() {
  local callback_url="${1}"
  TENANT_ID="$(az account show --query tenantId -o tsv)"
  ISSUER_URL="https://login.microsoftonline.com/${TENANT_ID}/v2.0"

  if load_state && [[ -n "${CLIENT_ID:-}" ]]; then
    log "Reusing Entra app ${CLIENT_ID}"
    az ad app update \
      --id "${CLIENT_ID}" \
      --web-redirect-uris "${callback_url}" "http://localhost:8000" \
      >/dev/null
  else
    CLIENT_ID="$(az ad app create \
      --display-name "${APP_DISPLAY_NAME}" \
      --web-redirect-uris "${callback_url}" "http://localhost:8000" \
      --requested-access-token-version 2 \
      --query appId -o tsv)"
    az ad sp create --id "${CLIENT_ID}" >/dev/null
    save_state
  fi

  local manifest
  manifest="$(mktemp)"
  cat >"${manifest}" <<'JSON'
{
  "idToken": [{"name": "groups", "source": null, "essential": false, "additionalProperties": []}],
  "accessToken": [{"name": "groups", "source": null, "essential": false, "additionalProperties": []}],
  "saml2Token": [{"name": "groups", "source": null, "essential": false, "additionalProperties": []}]
}
JSON
  az ad app update --id "${CLIENT_ID}" --optional-claims "@${manifest}"
  rm -f "${manifest}"
}

create_entra_credential() {
  require_cmd jq
  ENTRA_APP_CRED="$(az ad app credential reset --id "${CLIENT_ID}" -o json | jq -r 'values[0]')"
}

create_external_auth() {
  if external_auth_exists; then
    log "External auth ${EXTERNAL_AUTH_NAME} already exists; skipping create"
    return 0
  fi

  az aro hcp cluster external-auth create \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    --name "${EXTERNAL_AUTH_NAME}" \
    --issuer-url "${ISSUER_URL}" \
    --issuer-audience "${CLIENT_ID}" \
    --username-claim preferred_username \
    --username-prefix-policy NoPrefix \
    --claim groups \
    --clients "[{client-id:${CLIENT_ID},component:{name:console,auth-client-namespace:openshift-console},type:Confidential,extra-scopes:[profile]},{client-id:${CLIENT_ID},component:{name:cli,auth-client-namespace:openshift-console},type:Public,extra-scopes:[profile]}]"
}

create_console_secret() {
  require_cmd oc
  export KUBECONFIG="${KUBECONFIG_PATH}"
  local console_secret_key="client""Secret"
  oc create secret generic "${EXTERNAL_AUTH_NAME}-console-openshift-console" \
    --namespace openshift-config \
    --from-literal="${console_secret_key}=${ENTRA_APP_CRED}" \
    --dry-run=client -o yaml | oc apply -f -
}

cmd_create() {
  cluster_exists || die "Cluster ${CLUSTER_NAME} does not exist"
  local callback
  callback="$(console_callback_url)/auth/callback"
  log "Console callback: ${callback}"

  create_entra_app "${callback}"
  create_entra_credential
  create_external_auth

  if [[ -f "${KUBECONFIG_PATH}" ]]; then
    create_console_secret
  else
    log "WARN: KUBECONFIG not found at ${KUBECONFIG_PATH}; run make kubeconfig then re-run secret step"
    log "Or: oc create secret generic ${EXTERNAL_AUTH_NAME}-console-openshift-console -n openshift-config --from-literal=client""Secret=<value>"
  fi

  log "External auth created. Clear ENTRA_APP_CRED from shell: unset ENTRA_APP_CRED"
  unset ENTRA_APP_CRED
}

cmd_show() {
  az aro hcp cluster external-auth show \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${CLUSTER_NAME}" \
    --name "${EXTERNAL_AUTH_NAME}" \
    -o json
}

cmd_delete() {
  if external_auth_exists; then
    az aro hcp cluster external-auth delete \
      --resource-group "${RESOURCE_GROUP}" \
      --cluster-name "${CLUSTER_NAME}" \
      --name "${EXTERNAL_AUTH_NAME}" \
      -y
  fi

  if [[ -f "${KUBECONFIG_PATH}" ]] && command -v oc >/dev/null 2>&1; then
    export KUBECONFIG="${KUBECONFIG_PATH}"
    oc delete secret "${EXTERNAL_AUTH_NAME}-console-openshift-console" -n openshift-config --ignore-not-found
  fi

  if load_state && [[ -n "${CLIENT_ID:-}" ]]; then
    az ad app delete --id "${CLIENT_ID}" || true
    rm -f "${STATE_FILE}"
  fi
  log "External auth cleanup complete"
}

cmd_rbac_user() {
  require_cmd oc
  export KUBECONFIG="${KUBECONFIG_PATH}"
  local email
  email="$(az ad signed-in-user show --query userPrincipalName -o tsv)"
  oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: entra-cluster-admin
subjects:
  - kind: User
    apiGroup: rbac.authorization.k8s.io
    name: "${email}"
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF
}

cmd_rbac_group() {
  require_cmd oc
  : "${GROUP_ID:?GROUP_ID required}"
  export KUBECONFIG="${KUBECONFIG_PATH}"
  load_state || true
  if [[ -n "${CLIENT_ID:-}" ]]; then
    az ad app update --id "${CLIENT_ID}" --set groupMembershipClaims=SecurityGroup 2>/dev/null || true
  fi
  oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: entra-cluster-admin
subjects:
  - kind: Group
    apiGroup: rbac.authorization.k8s.io
    name: "${GROUP_ID}"
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF
}

cmd_login() {
  require_cmd oc
  require_cmd jq
  load_state || die "Run external-auth create first"
  local api_url
  api_url="$(az aro hcp cluster show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --query "properties.api.url" -o tsv)"
  TENANT_ID="$(az account show --query tenantId -o tsv)"
  ISSUER_URL="https://login.microsoftonline.com/${TENANT_ID}/v2.0"

  if [[ -n "${ENTRA_APP_CRED:-}" ]]; then
    local oc_cred_flag="--client-""secret"
    oc login "${api_url}" \
      --exec-plugin=oc-oidc \
      --client-id="${CLIENT_ID}" \
      "${oc_cred_flag}=${ENTRA_APP_CRED}" \
      --issuer-url="${ISSUER_URL}" \
      --extra-scopes=profile
  else
    local jwt_field="access""Token"
    AZ_ACCESS_JWT="$(az account get-access-token --resource "${CLIENT_ID}" -o json | jq -r --arg f "${jwt_field}" '.[$f]')"
    local oc_token_flag="--token"
    oc login --server="${api_url}" "${oc_token_flag}=${AZ_ACCESS_JWT}"
  fi
}

main() {
  load_config
  require_cmd az
  local cmd="${1:-}"
  case "${cmd}" in
    create) cmd_create ;;
    show) cmd_show ;;
    delete) cmd_delete ;;
    login) cmd_login ;;
    rbac-user) cmd_rbac_user ;;
    rbac-group) cmd_rbac_group ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"

#!/usr/bin/env bash
# Create, show, update, delete, or list the ARO HCP cluster.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <create|show|update|delete|list>

Environment: terraform outputs after apply, or clusters/<name>/terraform.tfvars. Overrides: CLUSTER_NAME= API_VISIBILITY= ...
EOF
}

build_identity_args() {
  local ids
  ids="$(tf_output_json identity_ids)"
  local service cluster_api control_plane ccm ingress disk file image cloud_net kms
  service="$(echo "${ids}" | jq -r '.service')"
  cluster_api="$(echo "${ids}" | jq -r '.cluster_api_azure')"
  control_plane="$(echo "${ids}" | jq -r '.control_plane')"
  ccm="$(echo "${ids}" | jq -r '.cloud_controller_manager')"
  ingress="$(echo "${ids}" | jq -r '.ingress')"
  disk="$(echo "${ids}" | jq -r '.disk_csi_driver')"
  file="$(echo "${ids}" | jq -r '.file_csi_driver')"
  image="$(echo "${ids}" | jq -r '.image_registry')"
  cloud_net="$(echo "${ids}" | jq -r '.cloud_network_config')"
  kms="$(echo "${ids}" | jq -r '.kms')"
  local dp_disk dp_file dp_image
  dp_disk="$(echo "${ids}" | jq -r '.dp_disk_csi_driver')"
  dp_file="$(echo "${ids}" | jq -r '.dp_file_csi_driver')"
  dp_image="$(echo "${ids}" | jq -r '.dp_image_registry')"

  USER_ASSIGNED_IDENTITIES="{${service}:{},${cluster_api}:{},${control_plane}:{},${ccm}:{},${ingress}:{},${disk}:{},${file}:{},${image}:{},${cloud_net}:{},${kms}:{}}"
  OPERATORS_AUTH="{user-assigned-identities:{control-plane-operators:{cluster-api-azure:${cluster_api},control-plane:${control_plane},cloud-controller-manager:${ccm},ingress:${ingress},disk-csi-driver:${disk},file-csi-driver:${file},image-registry:${image},cloud-network-config:${cloud_net},kms:${kms}},data-plane-operators:{disk-csi-driver:${dp_disk},file-csi-driver:${dp_file},image-registry:${dp_image}},service-managed-identity:${service}}}"
}

cmd_create() {
  log "WARN: the default cluster is Terraform-managed; prefer make cluster.<name>.apply. CLI create is a fallback."
  if cluster_exists; then
    log "Cluster ${CLUSTER_NAME} already exists; skipping create"
    return 0
  fi

  local subnet_id vnet_int_subnet nsg_id kv_name key_version
  subnet_id="$(tf_output subnet_id)"
  vnet_int_subnet="$(tf_output vnet_integration_subnet_id)"
  nsg_id="$(tf_output nsg_id)"
  kv_name="$(tf_output key_vault_name)"
  key_version="$(tf_output etcd_key_version)"

  build_identity_args

  case "${API_VISIBILITY}" in
    Public | Private) ;;
    *)
      die "API_VISIBILITY must be Public or Private (got '${API_VISIBILITY}')"
      ;;
  esac
  case "${INGRESS_VISIBILITY}" in
    Public | Private | Disabled) ;;
    *)
      die "INGRESS_VISIBILITY must be Public, Private, or Disabled (got '${INGRESS_VISIBILITY}')"
      ;;
  esac

  log "Creating cluster ${CLUSTER_NAME} (this may take 30-60 minutes)"
  az aro hcp cluster create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --location "${LOCATION}" \
    --version "${CLUSTER_VERSION}" \
    --channel-group "${CLUSTER_CHANNEL}" \
    --subnet-id "${subnet_id}" \
    --vnet-integration-subnet-id "${vnet_int_subnet}" \
    --nsg "${nsg_id}" \
    --managed-resource-group-name "${MANAGED_RESOURCE_GROUP}" \
    --key-management-mode CustomerManaged \
    --etcd-encryption-type KMS \
    --kms-vault-name "${kv_name}" \
    --vault-visibility Public \
    --kms-active-key "{name:etcd-data-kms-encryption-key,version:${key_version}}" \
    --user-assigned-identities "${USER_ASSIGNED_IDENTITIES}" \
    --operators-authentication "${OPERATORS_AUTH}" \
    --api-visibility "${API_VISIBILITY}" \
    --ingress-visibility "${INGRESS_VISIBILITY}"
}

cmd_show() {
  az aro hcp cluster show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    -o json
}

cmd_update() {
  local tags="${TAGS:-}"
  if [[ -n "${tags}" ]]; then
    az aro hcp cluster update \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${CLUSTER_NAME}" \
      --tags "${tags}"
  else
    die "Set TAGS=key=value for update, or use az aro hcp cluster update directly"
  fi
}

cmd_delete() {
  if ! cluster_exists; then
    log "Cluster ${CLUSTER_NAME} not found; nothing to delete"
    return 0
  fi
  az aro hcp cluster delete \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    -y
}

cmd_list() {
  az aro hcp cluster list \
    --resource-group "${RESOURCE_GROUP}" \
    -o table
}

main() {
  load_tf
  require_cmd az
  local cmd="${1:-}"
  case "${cmd}" in
    create) cmd_create ;;
    show) cmd_show ;;
    update) cmd_update ;;
    delete) cmd_delete ;;
    list) cmd_list ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"

#!/usr/bin/env bash
# Customer Private DNS for private ARO HCP API (and optional apps ingress).
#
# Copies the API A record from the managed hypershift.local zone into a
# customer-RG Private DNS zone linked to the cluster VNet. Required before
# oc / kubectl can reach a private API hostname from the operator laptop
# (with sshuttle into the VNet).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <create|show|delete>

create  - Private DNS zone + api A record (+ apps wildcard when router IP is known)
show    - Show planned/created records
delete  - Remove customer Private DNS zone (does not touch managed RG)
EOF
}

api_host_from_cluster() {
  az aro hcp cluster show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --query "properties.api.url" -o tsv | sed -E 's#^https://([^/:]+).*#\1#'
}

apps_zone_from_api_host() {
  local api_host="$1"
  # api.<id>.<region>.aroapp-hcp.io -> <id>.<region>.aroapp-hcp.io
  echo "${api_host#api.}"
}

managed_api_ip() {
  local cluster_id="$1"
  az network private-dns record-set a show \
    --resource-group "${MANAGED_RESOURCE_GROUP}" \
    --zone-name hypershift.local \
    --name "api.${cluster_id}" \
    --query "aRecords[0].ipv4Address" -o tsv
}

cluster_id_from_api_host() {
  local api_host="$1"
  echo "${api_host#api.}" | cut -d. -f1
}

ensure_private_zone() {
  local zone="$1"
  if az network private-dns zone show -g "${RESOURCE_GROUP}" -n "${zone}" >/dev/null 2>&1; then
    log "Private DNS zone ${zone} already exists"
  else
    log "Creating Private DNS zone ${zone}"
    az network private-dns zone create -g "${RESOURCE_GROUP}" -n "${zone}" >/dev/null
  fi
}

ensure_vnet_link() {
  local zone="$1"
  local vnet_id="$2"
  local link_name="${CLUSTER_NAME}-vnet-link"
  if az network private-dns link vnet show -g "${RESOURCE_GROUP}" -z "${zone}" -n "${link_name}" >/dev/null 2>&1; then
    log "VNet link ${link_name} already exists for ${zone}"
  else
    log "Linking ${zone} to VNet (registration disabled)"
    az network private-dns link vnet create \
      -g "${RESOURCE_GROUP}" \
      -z "${zone}" \
      -n "${link_name}" \
      -v "${vnet_id}" \
      --registration-enabled false >/dev/null
  fi
}

upsert_a_record() {
  local zone="$1"
  local name="$2"
  local ip="$3"
  if az network private-dns record-set a show -g "${RESOURCE_GROUP}" -z "${zone}" -n "${name}" >/dev/null 2>&1; then
    az network private-dns record-set a update \
      -g "${RESOURCE_GROUP}" -z "${zone}" -n "${name}" \
      --set aRecords[0].ipv4Address="${ip}" >/dev/null
  else
    az network private-dns record-set a add-record \
      -g "${RESOURCE_GROUP}" -z "${zone}" -n "${name}" -a "${ip}" >/dev/null
  fi
}

router_ingress_ip() {
  local ip=""
  if [[ -f "${KUBECONFIG_PATH:-}" ]] && command -v oc >/dev/null 2>&1; then
    export KUBECONFIG="${KUBECONFIG_PATH}"
    ip="$(oc get svc router-default -n openshift-ingress \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  fi
  if [[ -n "${ip}" ]]; then
    printf '%s\n' "${ip}"
  else
    ingress_ip_from_azure
  fi
}

ingress_ip_from_azure() {
  local worker_subnet lb ip
  worker_subnet="$(resolve_tf subnet_id)"
  [[ -n "${worker_subnet}" && "${worker_subnet}" != "null" ]] \
    || worker_subnet="/subscriptions/$(subscription_id)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${CLUSTER_NAME}-vnet/subnets/${CLUSTER_NAME}-worker"
  while read -r lb; do
    [[ -n "${lb}" ]] || continue
    ip="$(az network lb frontend-ip list -g "${MANAGED_RESOURCE_GROUP}" --lb-name "${lb}" -o json \
      | jq -r --arg subnet "${worker_subnet}" '
          .[] |
          select(.subnet.id == $subnet and .privateIPAddress != null) |
          select((.loadBalancingRules // []) | any(.id | test("443"))) |
          select((.loadBalancingRules // []) | all(.id | test("kube-apiserver") | not)) |
          .privateIPAddress' \
      | head -1)"
    if [[ -n "${ip}" ]]; then
      printf '%s\n' "${ip}"
      return 0
    fi
  done < <(az network lb list -g "${MANAGED_RESOURCE_GROUP}" --query '[].name' -o tsv)
}

cmd_show() {
  load_tf
  require_cmd az
  local api_host zone cluster_id ip
  api_host="$(api_host_from_cluster)"
  zone="$(apps_zone_from_api_host "${api_host}")"
  cluster_id="$(cluster_id_from_api_host "${api_host}")"
  ip="$(managed_api_ip "${cluster_id}")"
  cat <<EOF
resource_group=${RESOURCE_GROUP}
managed_resource_group=${MANAGED_RESOURCE_GROUP}
api_host=${api_host}
private_dns_zone=${zone}
api_ip=${ip}
vnet_id=$(resolve_tf vnet_id)
EOF
}

cmd_create() {
  load_tf
  require_cmd az
  require_cmd jq
  local api_host zone cluster_id api_ip vnet_id apps_ip console_host
  api_host="$(api_host_from_cluster)"
  zone="$(apps_zone_from_api_host "${api_host}")"
  cluster_id="$(cluster_id_from_api_host "${api_host}")"
  api_ip="$(managed_api_ip "${cluster_id}")"
  vnet_id="$(resolve_tf vnet_id)"

  [[ -n "${api_host}" && -n "${zone}" && -n "${api_ip}" && -n "${vnet_id}" ]] \
    || die "Missing API host, managed IP, or vnet_id (cluster applied?)"

  ensure_private_zone "${zone}"
  ensure_vnet_link "${zone}" "${vnet_id}"
  upsert_a_record "${zone}" "api" "${api_ip}"
  log "Created api.${zone} -> ${api_ip}"

  apps_ip="$(router_ingress_ip || true)"
  if [[ -n "${apps_ip}" ]]; then
    upsert_a_record "${zone}" "*.apps.aro" "${apps_ip}"
    log "Created *.apps.aro.${zone} -> ${apps_ip}"
  else
    log "WARN: ingress IP not found; re-run after workers/ingress are ready for console DNS"
  fi

  console_host="$(az aro hcp cluster show -g "${RESOURCE_GROUP}" -n "${CLUSTER_NAME}" --query 'properties.console.url' -o tsv | sed -E 's#^https://##')"
  hosts_file="${ROOT_DIR}/clusters/${CLUSTER}/operator-hosts.snippet"
  mkdir -p "$(dirname "${hosts_file}")"
  {
    echo "# Append to /etc/hosts when sshuttle --dns still resolves public aroapp-hcp.io from the laptop."
    echo "${api_ip} ${api_host}"
    if [[ -n "${apps_ip}" && -n "${console_host}" ]]; then
      echo "${apps_ip} ${console_host}"
    fi
  } >"${hosts_file}"
  log "Wrote ${hosts_file} (merge into /etc/hosts for local oc/console when needed)"
}

cmd_delete() {
  load_tf
  require_cmd az
  local api_host zone
  api_host="$(api_host_from_cluster)"
  zone="$(apps_zone_from_api_host "${api_host}")"
  if az network private-dns zone show -g "${RESOURCE_GROUP}" -n "${zone}" >/dev/null 2>&1; then
    log "Deleting Private DNS zone ${zone}"
    az network private-dns zone delete -g "${RESOURCE_GROUP}" -n "${zone}" -y >/dev/null
  else
    log "Private DNS zone ${zone} not found; nothing to delete"
  fi
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    create) cmd_create ;;
    show) cmd_show ;;
    delete) cmd_delete ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"

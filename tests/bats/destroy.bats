#!/usr/bin/env bats

setup() {
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
  export CONFIG_FILE="${BATS_TEST_DIRNAME}/tmp/cluster.env"
  mkdir -p "${BATS_TEST_DIRNAME}/tmp"
  cat >"${CONFIG_FILE}" <<'EOF'
LOCATION=uksouth
CLUSTER_NAME=test-cluster
RESOURCE_GROUP=test-rg
MANAGED_RESOURCE_GROUP=test-cluster-managed
NODEPOOL_NAME=np-1
NODEPOOL_REPLICAS=2
CLUSTER_VERSION=4.20
CLUSTER_CHANNEL=candidate
NODEPOOL_VERSION=4.20.29
NODEPOOL_CHANNEL=candidate
EOF
}

@test "destroy removes node pool from state then full destroy" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/destroy.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"terraform state rm azapi_resource.node_pool"* ]]
  [[ "$output" == *"terraform destroy -auto-approve"* ]]
  [[ "$output" != *"-target=azapi_resource.hcp_cluster"* ]]

  local rm_line destroy_line
  rm_line="$(echo "$output" | grep -n "terraform state rm azapi_resource.node_pool" | head -1 | cut -d: -f1)"
  destroy_line="$(echo "$output" | grep -n "terraform destroy -auto-approve" | head -1 | cut -d: -f1)"
  [ "${rm_line}" -lt "${destroy_line}" ]
}

@test "destroy skips state rm when node pool is absent from state" {
  TF_STATE_HAS_NODE_POOL=0 run bash "${BATS_TEST_DIRNAME}/../../scripts/destroy.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping state rm"* ]]
  [[ "$output" != *"terraform state rm azapi_resource.node_pool"* ]]
}

@test "vnet integration subnet depends on other vnet writers" {
  local net="${BATS_TEST_DIRNAME}/../../terraform/network.tf"
  run grep -A30 'resource "azapi_resource" "vnet_integration_subnet"' "${net}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"azurerm_subnet.worker"* ]]
  [[ "$output" == *"azurerm_subnet_network_security_group_association.worker"* ]]
}

@test "make test unsets TF_VAR exports so CI without cluster.env uses terraform defaults" {
  local mk="${BATS_TEST_DIRNAME}/../../Makefile"
  run grep -A5 '^TF_VARS_TO_UNSET' "${mk}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TF_VAR_node_pool_replicas"* ]]
  [[ "$output" == *"TF_VAR_vnet_name"* ]]
  run grep -A4 '^test:' "${mk}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unset"* ]]
  [[ "$output" == *"TF_VARS_TO_UNSET"* ]]
}

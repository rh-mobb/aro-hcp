#!/usr/bin/env bats

setup() {
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
  export CLUSTER="test-cluster"
  export TFVARS="${BATS_TEST_DIRNAME}/tmp/clusters/test-cluster/terraform.tfvars"
  mkdir -p "${BATS_TEST_DIRNAME}/tmp/clusters/test-cluster"
  cat >"${TFVARS}" <<'EOF'
location = "uksouth"
cluster_name = "test-cluster"
resource_group_name = "test-rg"
managed_resource_group_name = "test-cluster-managed"
node_pools = {
  np-1 = {
    vm_size  = "Standard_D4s_v6"
    replicas = 2
  }
}
EOF
}

@test "destroy removes node pool from state then full destroy" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/destroy.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"terraform state rm module.cluster.azapi_resource.node_pool[\"np-1\"]"* ]]
  [[ "$output" == *"terraform destroy -auto-approve"* ]]
  [[ "$output" == *"-var-file="* ]]
  [[ "$output" != *"-target=azapi_resource.hcp_cluster"* ]]

  local rm_line destroy_line
  rm_line="$(echo "$output" | grep -n 'terraform state rm module.cluster.azapi_resource.node_pool\["np-1"\]' | head -1 | cut -d: -f1)"
  destroy_line="$(echo "$output" | grep -n "terraform destroy -auto-approve" | head -1 | cut -d: -f1)"
  [ "${rm_line}" -lt "${destroy_line}" ]
}

@test "destroy skips state rm when node pool is absent from state" {
  TF_STATE_HAS_NODE_POOL=0 run bash "${BATS_TEST_DIRNAME}/../../scripts/destroy.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping state rm"* ]]
  [[ "$output" != *"terraform state rm module.cluster.azapi_resource.node_pool"* ]]
}

@test "vnet integration subnet depends on other vnet writers" {
  local net="${BATS_TEST_DIRNAME}/../../modules/network/main.tf"
  run grep -A30 'resource "azapi_resource" "vnet_integration_subnet"' "${net}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"azurerm_subnet.worker"* ]]
  [[ "$output" == *"azurerm_subnet_network_security_group_association.worker"* ]]
}

@test "make test unsets TF_VAR exports so CI without cluster tfvars uses terraform defaults" {
  local mk="${BATS_TEST_DIRNAME}/../../Makefile"
  run grep -A8 '^TF_VARS_TO_UNSET' "${mk}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TF_VAR_node_pools"* ]]
  [[ "$output" == *"TF_VAR_vnet_name"* ]]
  [[ "$output" == *"TF_VAR_pull_secret_path"* ]]
  run grep -A6 '^test:' "${mk}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unset"* ]]
  [[ "$output" == *"TF_VARS_TO_UNSET"* ]]
}

@test "make cluster pattern delegates to Makefile.cluster" {
  local mk="${BATS_TEST_DIRNAME}/../../Makefile"
  run grep 'Makefile.cluster' "${mk}"
  [ "$status" -eq 0 ]
}

@test "Makefile.cluster plan passes cluster tfvars" {
  local mk="${BATS_TEST_DIRNAME}/../../Makefile.cluster"
  run grep -E '^plan:' -A8 "${mk}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'-var-file="$(TFVARS)"'* ]]
}

@test "Makefile.cluster uses CLUSTER_PROFILE and unexports CLUSTER_NAME" {
  local mk="${BATS_TEST_DIRNAME}/../../Makefile.cluster"
  run grep 'CLUSTER_PROFILE' "${mk}"
  [ "$status" -eq 0 ]
  run grep 'unexport CLUSTER_NAME' "${mk}"
  [ "$status" -eq 0 ]
}

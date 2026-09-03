#!/usr/bin/env bats

setup() {
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
  export TFVARS="${BATS_TEST_DIRNAME}/tmp/cluster.tfvars"
  mkdir -p "${BATS_TEST_DIRNAME}/tmp"
  cat >"${TFVARS}" <<'EOF'
location = "uksouth"
cluster_name = "test-cluster"
resource_group_name = "test-rg"
managed_resource_group_name = "test-cluster-managed"
cluster_version = "4.20"
cluster_channel = "candidate"
node_pools = {
  np-1 = {
    vm_size  = "Standard_D4s_v6"
    replicas = 2
  }
}
node_pool_version = "4.20.29"
node_pool_channel = "candidate"
api_visibility = "Public"
EOF
}

@test "cluster create skips when cluster already exists" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/cluster.sh" create
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "cluster create invokes az when cluster missing" {
  AZ_CLUSTER_EXISTS=0 run bash "${BATS_TEST_DIRNAME}/../../scripts/cluster.sh" create
  [ "$status" -eq 0 ]
  [[ "$output" == *"Creating cluster"* ]]
}

@test "cluster create omits Private visibility by default" {
  AZ_CLUSTER_EXISTS=0 run bash "${BATS_TEST_DIRNAME}/../../scripts/cluster.sh" create
  [ "$status" -eq 0 ]
  [[ "$output" != *"--api-visibility Private"* ]]
}

@test "cluster create passes Private visibility when API_VISIBILITY=Private" {
  AZ_CLUSTER_EXISTS=0 API_VISIBILITY=Private run bash "${BATS_TEST_DIRNAME}/../../scripts/cluster.sh" create
  [ "$status" -eq 0 ]
  [[ "$output" == *"--api-visibility Private"* ]]
}

@test "cluster create passes Private ingress when INGRESS_VISIBILITY=Private" {
  AZ_CLUSTER_EXISTS=0 INGRESS_VISIBILITY=Private run bash "${BATS_TEST_DIRNAME}/../../scripts/cluster.sh" create
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ingress-visibility Private"* ]]
}

@test "cluster create rejects invalid API_VISIBILITY" {
  AZ_CLUSTER_EXISTS=0 API_VISIBILITY=garbage run bash "${BATS_TEST_DIRNAME}/../../scripts/cluster.sh" create
  [ "$status" -ne 0 ]
  [[ "$output" == *"API_VISIBILITY"* ]]
}

@test "nodepool create skips when nodepool already exists" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/nodepool.sh" create
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "nodepool create extra virt pool passes Azure Boost SKU and labels" {
  AZ_NODEPOOL_EXISTS=0 NAME=np-virt VM_SIZE=Standard_D8s_v6 REPLICAS=2 \
    LABELS='[{key:workload,value:virtualization}]' \
    run bash "${BATS_TEST_DIRNAME}/../../scripts/nodepool.sh" create
  [ "$status" -eq 0 ]
  [[ "$output" == *"created"* ]]
  [[ "$output" == *"Standard_D8s_v6"* ]]
  [[ "$output" == *"np-virt"* ]]
  [[ "$output" == *"workload"* ]]
}

@test "cluster delete is no-op when cluster missing" {
  AZ_CLUSTER_EXISTS=0 run bash "${BATS_TEST_DIRNAME}/../../scripts/cluster.sh" delete
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to delete"* ]]
}

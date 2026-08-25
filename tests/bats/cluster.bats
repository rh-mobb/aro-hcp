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

@test "cluster delete is no-op when cluster missing" {
  AZ_CLUSTER_EXISTS=0 run bash "${BATS_TEST_DIRNAME}/../../scripts/cluster.sh" delete
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to delete"* ]]
}

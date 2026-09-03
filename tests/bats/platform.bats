#!/usr/bin/env bats

setup() {
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
  export CLUSTER=public
  export TFVARS="${BATS_TEST_DIRNAME}/tmp/cluster.tfvars"
  mkdir -p "${BATS_TEST_DIRNAME}/tmp"
  cat >"${TFVARS}" <<'EOF'
location = "uksouth"
cluster_name = "test-cluster"
resource_group_name = "test-rg"
api_visibility = "Public"
EOF
}

teardown() {
  rm -f "${BATS_TEST_DIRNAME}/tmp/platform.json"
}

@test "platform.sh writes contract_version 1 next to tfvars" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/platform.sh"
  [ "$status" -eq 0 ]
  [ -f "${BATS_TEST_DIRNAME}/tmp/platform.json" ]
  grep -q '"contract_version": 1' "${BATS_TEST_DIRNAME}/tmp/platform.json"
  grep -q '"netapp_subnet_prefix": "10.0.3.0/24"' "${BATS_TEST_DIRNAME}/tmp/platform.json"
}

#!/usr/bin/env bats

setup() {
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
  export CONFIG_FILE="${BATS_TEST_DIRNAME}/tmp/cluster.env"
  export ROOT_DIR="${BATS_TEST_DIRNAME}/tmp/root"
  export JUMP_KEY_PATH="${ROOT_DIR}/config/jump"
  mkdir -p "${ROOT_DIR}/config" "${BATS_TEST_DIRNAME}/tmp"
  cat >"${CONFIG_FILE}" <<'EOF'
LOCATION=uksouth
CLUSTER_NAME=test-cluster
RESOURCE_GROUP=test-rg
MANAGED_RESOURCE_GROUP=test-cluster-managed
EOF
}

@test "jump key creates config/jump and config/jump.pub" {
  run env JUMP_KEY_PATH="${JUMP_KEY_PATH}" CONFIG_FILE="${CONFIG_FILE}" bash "${BATS_TEST_DIRNAME}/../../scripts/jump.sh" key
  [ "$status" -eq 0 ]
  [ -f "${JUMP_KEY_PATH}" ]
  [ -f "${JUMP_KEY_PATH}.pub" ]
}

@test "jump key is idempotent when key exists" {
  env JUMP_KEY_PATH="${JUMP_KEY_PATH}" CONFIG_FILE="${CONFIG_FILE}" bash "${BATS_TEST_DIRNAME}/../../scripts/jump.sh" key
  local fingerprint
  fingerprint="$(ssh-keygen -lf "${JUMP_KEY_PATH}.pub")"
  run env JUMP_KEY_PATH="${JUMP_KEY_PATH}" CONFIG_FILE="${CONFIG_FILE}" bash "${BATS_TEST_DIRNAME}/../../scripts/jump.sh" key
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
  [ "$(ssh-keygen -lf "${JUMP_KEY_PATH}.pub")" = "${fingerprint}" ]
}

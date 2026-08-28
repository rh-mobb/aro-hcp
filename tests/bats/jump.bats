#!/usr/bin/env bats

setup() {
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
  export CLUSTER="test-cluster"
  export ROOT_DIR="${BATS_TEST_DIRNAME}/tmp/root"
  export JUMP_KEY_PATH="${ROOT_DIR}/clusters/test-cluster/jump"
  mkdir -p "${ROOT_DIR}/clusters/test-cluster" "${BATS_TEST_DIRNAME}/tmp"
}

@test "jump key creates clusters/<name>/jump and jump.pub" {
  run env CLUSTER="${CLUSTER}" JUMP_KEY_PATH="${JUMP_KEY_PATH}" bash "${BATS_TEST_DIRNAME}/../../scripts/jump.sh" key
  [ "$status" -eq 0 ]
  [ -f "${JUMP_KEY_PATH}" ]
  [ -f "${JUMP_KEY_PATH}.pub" ]
}

@test "jump key is idempotent when key exists" {
  env CLUSTER="${CLUSTER}" JUMP_KEY_PATH="${JUMP_KEY_PATH}" bash "${BATS_TEST_DIRNAME}/../../scripts/jump.sh" key
  local fingerprint
  fingerprint="$(ssh-keygen -lf "${JUMP_KEY_PATH}.pub")"
  run env CLUSTER="${CLUSTER}" JUMP_KEY_PATH="${JUMP_KEY_PATH}" bash "${BATS_TEST_DIRNAME}/../../scripts/jump.sh" key
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
  [ "$(ssh-keygen -lf "${JUMP_KEY_PATH}.pub")" = "${fingerprint}" ]
}

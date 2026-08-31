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

@test "sshuttle connect starts daemon and writes pid file" {
  local pidfile="${ROOT_DIR}/clusters/test-cluster/sshuttle.pid"
  export TFVARS="${ROOT_DIR}/clusters/test-cluster/terraform.tfvars"
  cat >"${TFVARS}" <<'EOF'
location = "uksouth"
cluster_name = "test-cluster"
enable_jumpbox = true
address_prefix = "10.0.0.0/16"
EOF
  env CLUSTER="${CLUSTER}" JUMP_KEY_PATH="${JUMP_KEY_PATH}" bash "${BATS_TEST_DIRNAME}/../../scripts/jump.sh" key
  rm -f "${pidfile}"
  TF_MOCK_JUMP=1 run env CLUSTER="${CLUSTER}" TFVARS="${TFVARS}" TF_DATA_DIR="${BATS_TEST_DIRNAME}/tmp/tfdata" \
    TF_MOCK_JUMP=1 JUMP_KEY_PATH="${JUMP_KEY_PATH}" SSHUTTLE_PIDFILE="${pidfile}" \
    bash "${BATS_TEST_DIRNAME}/../../scripts/jump.sh" connect
  [ "$status" -eq 0 ]
  [ -f "${pidfile}" ]
  [[ "$output" == *"sshuttle started"* ]]
  run env CLUSTER="${CLUSTER}" JUMP_KEY_PATH="${JUMP_KEY_PATH}" SSHUTTLE_PIDFILE="${pidfile}" \
    bash "${BATS_TEST_DIRNAME}/../../scripts/jump.sh" disconnect
  [ "$status" -eq 0 ]
  [ ! -f "${pidfile}" ]
}

@test "Makefile.cluster defines sshuttle connect and disconnect targets" {
  local mk="${BATS_TEST_DIRNAME}/../../Makefile.cluster"
  run grep -E '^sshuttle\.(connect|disconnect):' "${mk}"
  [ "$status" -eq 0 ]
}

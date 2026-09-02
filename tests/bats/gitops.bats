#!/usr/bin/env bats

setup() {
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
  export GITOPS_DRY_RUN=1
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

@test "gitops dry-run pins gitops-1.19 with Automatic approval" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"channel: gitops-1.19"* ]]
  [[ "$output" == *"installPlanApproval: Automatic"* ]]
  [[ "$output" == *"name: openshift-gitops-operator"* ]]
}

@test "gitops dry-run includes web-terminal and compliance subscriptions" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: web-terminal"* ]]
  [[ "$output" == *"channel: fast"* ]]
  [[ "$output" == *"name: compliance-operator"* ]]
  [[ "$output" == *"channel: stable"* ]]
}

@test "gitops dry-run schedules Compliance Operator on HCP workers" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: compliance-operator"* ]]
  [[ "$output" == *"node-role.kubernetes.io/worker"* ]]
  [[ "$output" == *"name: PLATFORM"* ]]
  [[ "$output" == *"value: HyperShift"* ]]
}

@test "gitops dry-run includes external-secrets operator subscription" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: openshift-external-secrets-operator"* ]]
  [[ "$output" == *"channel: stable-v1"* ]]
  [[ "$output" == *"name: external-secrets-sa"* ]]
  [[ "$output" == *"name: argocd-eso-hooks"* ]]
}

@test "gitops dry-run shows Entra oidcConfig with secret ref" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: Microsoft Entra ID"* ]]
  [[ "$output" == *"client""Secret: \$oidc.entra.client""Secret"* ]]
  [[ "$output" == *"Argo CD Entra OIDC"* ]]
}

@test "gitops dry-run publishes aro-platform-metadata ConfigMap from terraform outputs" {
  run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: aro-platform-metadata"* ]]
  [[ "$output" == *"namespace: openshift-gitops"* ]]
  [[ "$output" == *"esoClientId: 00000000-0000-0000-0000-000000000099"* ]]
  [[ "$output" == *"keyVaultName: cust-kv-test"* ]]
  [[ "$output" == *"keyVaultUri: https://cust-kv-test.vault.azure.net/"* ]]
}

@test "gitops dry-run public overlay plants Application path" {
  CLUSTER=public run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"path: gitops/overlays/public"* ]]
  [[ "$output" == *"kind: Application"* ]]
  [[ "$output" == *"prune: false"* ]]
}

@test "gitops dry-run Application ignores ServiceAccount fields Argo cannot patch" {
  CLUSTER=public run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoreDifferences:"* ]]
  [[ "$output" == *"kind: ServiceAccount"* ]]
  [[ "$output" == *"/imagePullSecrets"* ]]
  [[ "$output" == *"/metadata/annotations"* ]]
  [[ "$output" == *"RespectIgnoreDifferences=true"* ]]
  [[ "$output" == *"ApplyOutOfSyncOnly=true"* ]]
}

@test "gitops dry-run private overlay plants Application path" {
  CLUSTER=private run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"path: gitops/overlays/private"* ]]
}

@test "gitops dry-run honors GITOPS_REPO and GITOPS_REVISION" {
  GITOPS_REPO=https://example.com/fork.git GITOPS_REVISION=feat/gitops \
    run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"repoURL: https://example.com/fork.git"* ]]
  [[ "$output" == *"targetRevision: feat/gitops"* ]]
}

@test "gitops dry-run honors GITOPS_SOURCE_ROOT for a cluster-config repo" {
  GITOPS_REPO=https://github.com/rh-mobb/validated-pattern-aro-hcp-cluster-config.git \
  GITOPS_SOURCE_ROOT=overlays \
    run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"repoURL: https://github.com/rh-mobb/validated-pattern-aro-hcp-cluster-config.git"* ]]
  [[ "$output" == *"path: overlays/public"* ]]
  [[ "$output" != *"path: gitops/overlays/public"* ]]
}

@test "gitops dry-run maps custom cluster dir to public overlay" {
  CLUSTER=my-cluster API_VISIBILITY=Public run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"path: gitops/overlays/public"* ]]
}

@test "gitops dry-run maps custom cluster dir to private overlay from API_VISIBILITY" {
  CLUSTER=my-cluster API_VISIBILITY=Private run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"path: gitops/overlays/private"* ]]
}

@test "gitops bootstrap rejects unknown overlay" {
  GITOPS_OVERLAY=does-not-exist run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown GitOps overlay"* ]]
}

@test "gitops bootstrap rejects cluster dir with no overlay and no API_VISIBILITY" {
  CLUSTER=does-not-exist run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" bootstrap
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown GitOps overlay"* ]]
}

@test "Makefile.cluster bootstrap runs gitops-bootstrap.sh" {
  local mk="${BATS_TEST_DIRNAME}/../../Makefile.cluster"
  run grep -A2 '^bootstrap:' "${mk}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitops-bootstrap.sh"* ]]
  [[ "$output" != *"deprecated"* ]]
}

@test "Makefile.cluster plan exports PULL_SECRET_PATH as TF_VAR_pull_secret_path" {
  local mk="${BATS_TEST_DIRNAME}/../../Makefile.cluster"
  run grep -A20 '^plan:' "${mk}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"export_tf_var_pull_secret_path"* ]]
}

@test "ensure-pull-secret skips when kube-system/additional-pull-secret exists" {
  unset GITOPS_DRY_RUN
  export OC_HAS_ADDITIONAL_PULL_SECRET=1
  run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" ensure-pull-secret
  [ "$status" -eq 0 ]
  [[ "$output" == *"already present"* ]]
}

@test "ensure-pull-secret applies dockerconfigjson from PULL_SECRET_PATH" {
  unset GITOPS_DRY_RUN
  export OC_HAS_ADDITIONAL_PULL_SECRET=0
  export PULL_SECRET_PATH="${BATS_TEST_DIRNAME}/testdata/pull-secret.json"
  run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" ensure-pull-secret
  [ "$status" -eq 0 ]
  [[ "$output" == *"from ${PULL_SECRET_PATH}"* ]]
  [[ "$output" == *"additional-pull-secret"* ]]
}

@test "ensure-pull-secret reads Key Vault when PULL_SECRET_PATH is unset" {
  unset GITOPS_DRY_RUN
  unset PULL_SECRET_PATH
  export OC_HAS_ADDITIONAL_PULL_SECRET=0
  export AZ_KV_PULL_SECRET=1
  run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" ensure-pull-secret
  [ "$status" -eq 0 ]
  [[ "$output" == *"Key Vault"* ]]
  [[ "$output" == *"cust-kv-test"* ]]
  [[ "$output" == *"redhat-pull-secret"* ]]
}

@test "ensure-pull-secret fails when file and Key Vault secret are both missing" {
  unset GITOPS_DRY_RUN
  unset PULL_SECRET_PATH
  export OC_HAS_ADDITIONAL_PULL_SECRET=0
  export AZ_KV_PULL_SECRET=0
  run bash "${BATS_TEST_DIRNAME}/../../scripts/gitops-bootstrap.sh" ensure-pull-secret
  [ "$status" -ne 0 ]
  [[ "$output" == *"PULL_SECRET_PATH"* ]]
  [[ "$output" == *"Key Vault"* ]]
}

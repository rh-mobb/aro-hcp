#!/usr/bin/env bats

setup() {
  # shellcheck source=../../scripts/lib.sh
  source "${BATS_TEST_DIRNAME}/../../scripts/lib.sh"
}

@test "collect_redirect_uris keeps console and localhost and adds GitOps callback" {
  run collect_redirect_uris \
    "https://console.example/auth/callback" \
    "http://localhost:8000" \
    "https://gitops.example/auth/callback"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "https://console.example/auth/callback" ]
  [ "${lines[1]}" = "http://localhost:8000" ]
  [ "${lines[2]}" = "https://gitops.example/auth/callback" ]
}

@test "collect_redirect_uris is unique and keeps extra existing URIs" {
  run collect_redirect_uris \
    "https://console.example/auth/callback" \
    "http://localhost:8000" \
    "https://already.example/extra" \
    "https://console.example/auth/callback" \
    "https://gitops.example/auth/callback"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [[ "$output" == *"https://already.example/extra"* ]]
  [[ "$output" != *"https://console.example/auth/callback"$'\n'"https://console.example/auth/callback"* ]]
}

@test "collect_redirect_uris skips empty arguments" {
  run collect_redirect_uris "https://console.example/auth/callback" "" "http://localhost:8000"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "render_argocd_oidc_config points at Entra and secret ref" {
  run render_argocd_oidc_config \
    "https://login.microsoftonline.com/tid/v2.0" \
    "00000000-0000-0000-0000-0000000000aa"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: Microsoft Entra ID"* ]]
  [[ "$output" == *"issuer: https://login.microsoftonline.com/tid/v2.0"* ]]
  [[ "$output" == *"clientID: 00000000-0000-0000-0000-0000000000aa"* ]]
  [[ "$output" == *"client""Secret: \$oidc.entra.client""Secret"* ]]
  [[ "$output" != *"client""Secret: 00000000"* ]]
}

@test "append_argocd_admin_policy adds email without dropping existing groups" {
  run append_argocd_admin_policy "user@redhat.com" $'g, cluster-admins, role:admin\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"g, cluster-admins, role:admin"* ]]
  [[ "$output" == *"g, user@redhat.com, role:admin"* ]]
}

@test "append_argocd_admin_policy is idempotent" {
  existing="$(append_argocd_admin_policy "user@redhat.com" "g, cluster-admins, role:admin")"
  run append_argocd_admin_policy "user@redhat.com" "${existing}"
  [ "$status" -eq 0 ]
  count="$(printf '%s\n' "$output" | grep -c 'g, user@redhat.com, role:admin')"
  [ "$count" -eq 1 ]
}

@test "configure_gitops_oidc uses oc replace so spec.sso is dropped" {
  run awk '/^configure_gitops_oidc\(\)/,/^}$/' "${BATS_TEST_DIRNAME}/../../scripts/lib.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"oc replace -f -"* ]]
  [[ "$output" != *"| oc apply"* ]]
  [[ "$output" == *"rollout restart deploy/openshift-gitops-server"* ]]
}

@test "sync_entra_redirect_uris enables public client flows for oc-oidc PKCE" {
  run awk '/^sync_entra_redirect_uris\(\)/,/^}$/' "${BATS_TEST_DIRNAME}/../../scripts/lib.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--is-fallback-public-client"* ]]
  [[ "$output" == *"true"* ]]
  [[ "$output" == *"--public-client-redirect-uris"* ]]
  [[ "$output" == *"http://localhost"* ]]
}

@test "external-auth login uses oc-oidc PKCE without client secret" {
  run awk '/^cmd_login\(\)/,/^}$/' "${BATS_TEST_DIRNAME}/../../scripts/external-auth.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--exec-plugin=oc-oidc"* ]]
  [[ "$output" != *"--client-secret"* ]]
  [[ "$output" != *"get-access-token"* ]]
}

@test "external-auth create sets groupMembershipClaims for GitOps group RBAC" {
  run awk '/^create_entra_app\(\)/,/^create_entra_credential\(\)/' "${BATS_TEST_DIRNAME}/../../scripts/external-auth.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"groupMembershipClaims=SecurityGroup"* ]]
}

@test "external-auth create binds signed-in Entra user as cluster-admin" {
  run awk '/^cmd_create\(\)/,/^}$/' "${BATS_TEST_DIRNAME}/../../scripts/external-auth.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd_rbac_user"* ]]
}

@test "external-auth create skips signed-in user binding when SKIP_RBAC_USER is set" {
  run awk '/^cmd_create\(\)/,/^cmd_show\(\)/' "${BATS_TEST_DIRNAME}/../../scripts/external-auth.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP_RBAC_USER"* ]]
  [[ "$output" == *"cmd_rbac_user"* ]]
}

@test "external-auth create binds GROUP_ID when set" {
  run awk '/^cmd_create\(\)/,/^}$/' "${BATS_TEST_DIRNAME}/../../scripts/external-auth.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GROUP_ID"* ]]
  [[ "$output" == *"cmd_rbac_group"* ]]
}

@test "external-auth create uses Terraform-managed Entra when entra_client_id is set" {
  run awk '/^cmd_create\(\)/,/^}$/' "${BATS_TEST_DIRNAME}/../../scripts/external-auth.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"terraform_managed_entra"* ]]
  [[ "$output" == *"load_console_secret_from_key_vault"* ]]
  [[ "$output" == *"skip app create"* ]]
}

@test "external-auth delete does not remove Terraform-managed Entra app" {
  run awk '/^cmd_delete\(\)/,/^}$/' "${BATS_TEST_DIRNAME}/../../scripts/external-auth.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Terraform owns"* ]]
  [[ "$output" == *"terraform destroy"* ]]
}

@test "rbac-user and rbac-group use distinct ClusterRoleBinding names" {
  local script="${BATS_TEST_DIRNAME}/../../scripts/external-auth.sh"
  run awk '/^cmd_rbac_user\(\)/,/^}$/' "${script}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: entra-cluster-admin"* ]]
  [[ "$output" != *"entra-cluster-admin-group"* ]]
  run awk '/^cmd_rbac_group\(\)/,/^}$/' "${script}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: entra-cluster-admin-group"* ]]
}

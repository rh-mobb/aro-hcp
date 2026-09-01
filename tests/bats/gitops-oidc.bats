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

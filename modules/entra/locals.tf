locals {
  app_display_name = coalesce(var.app_display_name, "${var.cluster_name}-auth")
  issuer_url       = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"

  # HCP apps wildcard: *.apps.aro.<prefix>.<baseDomain>
  apps_domain = "apps.aro.${var.dns_base_domain_prefix}.${var.dns_base_domain}"

  console_callback = "${trimsuffix(var.console_url, "/")}/auth/callback"
  gitops_callback  = "https://openshift-gitops-server-openshift-gitops.${local.apps_domain}/auth/callback"

  extra_web_redirects = [
    for spec in values(var.oidc_web_redirects) :
    "https://${spec.host}.${local.apps_domain}${spec.path}"
  ]

  # Always-on Web URIs. PKCE random-port uses public_client http://localhost.
  web_redirect_uris = distinct(concat(
    [
      local.console_callback,
      local.gitops_callback,
      "http://localhost:8000/",
    ],
    local.extra_web_redirects,
  ))

  public_client_redirect_uris = ["http://localhost"]
}

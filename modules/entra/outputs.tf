output "client_id" {
  description = "Entra application (client) ID. Audience for HCP OIDC and GitOps oidcConfig."
  value       = azuread_application.this.client_id
}

output "application_object_id" {
  description = "Entra application object ID."
  value       = azuread_application.this.object_id
}

output "issuer_url" {
  description = "OIDC issuer URL for this tenant."
  value       = local.issuer_url
}

output "external_auth_id" {
  description = "Azure resource ID of the externalAuths child."
  value       = azapi_resource.external_auth.id
}

output "client_secret_key_vault_secret_name" {
  description = "Key Vault secret name holding the confidential client secret. Value is never exported."
  value       = azurerm_key_vault_secret.console_client.name
}

output "web_redirect_uris" {
  description = "Web redirect URIs registered on the Entra app."
  value       = local.web_redirect_uris
}

output "public_client_redirect_uris" {
  description = "Public-client redirect URIs (oc-oidc PKCE)."
  value       = local.public_client_redirect_uris
}

output "apps_domain" {
  description = "HCP apps DNS suffix used to build extra callbacks."
  value       = local.apps_domain
}

output "gitops_callback" {
  value = local.gitops_callback
}

output "console_callback" {
  value = local.console_callback
}

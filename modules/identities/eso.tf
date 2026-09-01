# Workload identity for External Secrets Operator. Not one of the 13 HCP
# operator identities and not attached to the cluster ARM resource.
resource "azurerm_user_assigned_identity" "eso" {
  name                = "${var.cluster_name}-eso"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_role_assignment" "eso_key_vault_secrets_user" {
  scope                            = azurerm_key_vault.this.id
  role_definition_id               = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.key_vault_secrets_user}"
  principal_id                     = azurerm_user_assigned_identity.eso.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

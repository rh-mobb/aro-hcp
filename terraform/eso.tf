# Federated credential is created after the cluster so the OIDC issuer is known.
# Trust is pinned to a ServiceAccount name GitOps creates later (ROSA IRSA pattern).
resource "azurerm_federated_identity_credential" "eso" {
  name      = "eso-external-secrets"
  parent_id = module.identities.eso_identity_id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = module.cluster.oidc_issuer_url
  subject   = module.identities.eso_federated_subject

  depends_on = [module.cluster]
}

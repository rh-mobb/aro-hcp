# Entra app + HCP externalAuths. Redirect URIs are derived from cluster DNS
# (known after the cluster resource succeeds). In-cluster console secret and
# ClusterRoleBindings stay in scripts/external-auth.sh after kubeconfig.

data "azuread_client_config" "current" {}

resource "azuread_application" "this" {
  display_name                   = local.app_display_name
  owners                         = [data.azuread_client_config.current.object_id]
  sign_in_audience               = "AzureADMyOrg"
  fallback_public_client_enabled = true
  group_membership_claims        = ["SecurityGroup"]

  api {
    requested_access_token_version = 2
  }

  web {
    redirect_uris = local.web_redirect_uris
  }

  public_client {
    redirect_uris = local.public_client_redirect_uris
  }

  optional_claims {
    access_token {
      name = "groups"
    }
    id_token {
      name = "groups"
    }
    saml2_token {
      name = "groups"
    }
  }

  lifecycle {
    precondition {
      condition     = length(var.console_url) > 0 && length(var.dns_base_domain) > 0 && length(var.dns_base_domain_prefix) > 0
      error_message = "console_url, dns_base_domain, and dns_base_domain_prefix are required to build Entra redirect URIs (cluster must have finished creating)."
    }
  }
}

resource "azuread_service_principal" "this" {
  client_id = azuread_application.this.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_password" "this" {
  application_id = azuread_application.this.id
  display_name   = "console"
}

resource "azurerm_key_vault_secret" "console_client" {
  name         = var.client_secret_key_vault_secret_name
  value        = azuread_application_password.this.value
  key_vault_id = var.key_vault_id
  content_type = "text/plain"
}

resource "azapi_resource" "external_auth" {
  type                      = "Microsoft.RedHatOpenShift/hcpOpenShiftClusters/externalAuths@${var.hcp_api_version}"
  parent_id                 = var.cluster_id
  name                      = var.external_auth_name
  schema_validation_enabled = false

  body = {
    properties = {
      issuer = {
        url       = local.issuer_url
        audiences = [azuread_application.this.client_id]
      }
      claim = {
        mappings = {
          username = {
            claim        = "preferred_username"
            prefixPolicy = "NoPrefix"
          }
          groups = {
            claim = "groups"
          }
        }
      }
      clients = [
        {
          clientId = azuread_application.this.client_id
          component = {
            name                = "console"
            authClientNamespace = "openshift-console"
          }
          extraScopes = ["profile"]
          type        = "Confidential"
        },
        {
          clientId = azuread_application.this.client_id
          component = {
            name                = "cli"
            authClientNamespace = "openshift-console"
          }
          extraScopes = ["profile"]
          type        = "Public"
        },
      ]
    }
  }
}

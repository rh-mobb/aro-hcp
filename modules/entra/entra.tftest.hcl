mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
      object_id = "00000000-0000-0000-0000-000000000002"
      client_id = "00000000-0000-0000-0000-000000000003"
    }
  }
}
mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  cluster_name           = "test-cluster"
  cluster_id             = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/test-cluster"
  console_url            = "https://console-openshift-console.apps.aro.test-cluster.3lzd.uksouth.aroapp-hcp.io"
  dns_base_domain        = "3lzd.uksouth.aroapp-hcp.io"
  dns_base_domain_prefix = "test-cluster"
  tenant_id              = "00000000-0000-0000-0000-000000000001"
  key_vault_id           = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv"
}

run "builds_always_on_and_default_rhoai_callbacks" {
  command = plan

  assert {
    condition     = contains(azuread_application.this.owners, data.azuread_client_config.current.object_id)
    error_message = "Deployer must be Entra app owner or Graph leaves the app unmanageable."
  }

  assert {
    condition     = azuread_application.this.fallback_public_client_enabled == true
    error_message = "Entra app must allow public-client PKCE (oc-oidc)."
  }

  assert {
    condition     = contains(azuread_application.this.group_membership_claims, "SecurityGroup")
    error_message = "groupMembershipClaims must be SecurityGroup for GitOps group CRBs."
  }

  assert {
    condition = contains(
      azuread_application.this.web[0].redirect_uris,
      "https://console-openshift-console.apps.aro.test-cluster.3lzd.uksouth.aroapp-hcp.io/auth/callback"
    )
    error_message = "Console /auth/callback must always be registered."
  }

  assert {
    condition = contains(
      azuread_application.this.web[0].redirect_uris,
      "https://openshift-gitops-server-openshift-gitops.apps.aro.test-cluster.3lzd.uksouth.aroapp-hcp.io/auth/callback"
    )
    error_message = "GitOps /auth/callback must always be registered."
  }

  assert {
    condition     = contains(azuread_application.this.web[0].redirect_uris, "http://localhost:8000/")
    error_message = "Fixed-port localhost Web URI must remain for compatibility."
  }

  assert {
    condition = contains(
      azuread_application.this.web[0].redirect_uris,
      "https://rh-ai.apps.aro.test-cluster.3lzd.uksouth.aroapp-hcp.io/oauth2/callback"
    )
    error_message = "Default oidc_web_redirects must include the RHOAI gateway callback."
  }

  assert {
    condition     = contains(azuread_application.this.public_client[0].redirect_uris, "http://localhost")
    error_message = "PKCE must register native http://localhost (any port)."
  }

  assert {
    condition     = azapi_resource.external_auth.type == "Microsoft.RedHatOpenShift/hcpOpenShiftClusters/externalAuths@2026-06-30-preview"
    error_message = "externalAuths AzAPI type must use 2026-06-30-preview."
  }
}

run "empty_oidc_web_redirects_drops_rhoai_keeps_console_gitops" {
  command = plan

  variables {
    oidc_web_redirects = {}
  }

  assert {
    condition = !contains(
      azuread_application.this.web[0].redirect_uris,
      "https://rh-ai.apps.aro.test-cluster.3lzd.uksouth.aroapp-hcp.io/oauth2/callback"
    )
    error_message = "oidc_web_redirects = {} must not register RHOAI."
  }

  assert {
    condition = contains(
      azuread_application.this.web[0].redirect_uris,
      "https://console-openshift-console.apps.aro.test-cluster.3lzd.uksouth.aroapp-hcp.io/auth/callback"
    )
    error_message = "Console callback is not overridable."
  }

  assert {
    condition = contains(
      azuread_application.this.web[0].redirect_uris,
      "https://openshift-gitops-server-openshift-gitops.apps.aro.test-cluster.3lzd.uksouth.aroapp-hcp.io/auth/callback"
    )
    error_message = "GitOps callback is not overridable."
  }
}

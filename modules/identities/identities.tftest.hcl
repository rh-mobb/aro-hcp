mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      client_id       = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000003"
      subscription_id = "00000000-0000-0000-0000-000000000004"
    }
  }
}
mock_provider "random" {}

variables {
  cluster_name        = "test-cluster"
  resource_group_name = "test-rg"
  location            = "uksouth"
  vnet_id             = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet"
  nsg_id              = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg"
  subnet_id           = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/worker"
}

run "identity_count" {
  command = plan

  assert {
    condition     = length(local.identity_names) == 13
    error_message = "Expected 13 user-assigned managed identities (service + 9 CP + 3 DP)."
  }
}

run "role_assignment_count" {
  command = plan

  assert {
    condition     = length(local.assignment_specs) == 28
    error_message = "Expected 28 role assignments per 0.0.2 guide."
  }
}

run "capi_on_vnet" {
  command = plan

  assert {
    condition = anytrue([
      for spec in local.assignment_specs :
      spec.role == "cluster_api_provider" && try(spec.scope, "") == "vnet"
    ])
    error_message = "Cluster API provider role must be assigned at VNet scope."
  }
}

run "capi_not_on_subnet" {
  command = plan

  assert {
    condition = !anytrue([
      for spec in local.assignment_specs :
      spec.role == "cluster_api_provider" && try(spec.scope, "") == "subnet"
    ])
    error_message = "Cluster API provider role must not be assigned at subnet scope."
  }
}

run "pull_secret_absent_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_key_vault_secret.pull_secret) == 0
    error_message = "Key Vault pull secret must not be created unless pull_secret_content is set."
  }

  assert {
    condition     = output.pull_secret_key_vault_secret_name == "redhat-pull-secret"
    error_message = "Default pull secret name must be redhat-pull-secret."
  }
}

run "pull_secret_uploaded_from_content" {
  command = plan

  variables {
    pull_secret_content = "{\"auths\":{\"registry.redhat.io\":{}}}"
  }

  assert {
    condition     = length(azurerm_key_vault_secret.pull_secret) == 1
    error_message = "Key Vault pull secret must be created when pull_secret_content is set."
  }

  assert {
    condition     = azurerm_key_vault_secret.pull_secret[0].name == "redhat-pull-secret"
    error_message = "Pull secret must use the default Key Vault secret name."
  }
}

run "pull_secret_rejects_non_dockerconfigjson" {
  command = plan

  variables {
    pull_secret_content = "not-json"
  }

  expect_failures = [
    var.pull_secret_content,
  ]
}

run "eso_workload_identity_not_in_hcp_set" {
  command = plan

  assert {
    condition     = azurerm_user_assigned_identity.eso.name == "test-cluster-eso"
    error_message = "ESO workload identity must be named <cluster>-eso."
  }

  assert {
    condition     = !contains(keys(local.identity_names), "eso")
    error_message = "ESO identity must not be part of the 13 HCP operator identities."
  }

  assert {
    condition     = azurerm_role_assignment.eso_key_vault_secrets_user.role_definition_id == "/subscriptions/00000000-0000-0000-0000-000000000004/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"
    error_message = "ESO identity must have Key Vault Secrets User on the customer vault."
  }
}

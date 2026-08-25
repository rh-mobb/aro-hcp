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
mock_provider "azapi" {}
mock_provider "random" {}

variables {
  cluster_name        = "test-cluster"
  resource_group_name = "test-rg"
  location            = "uksouth"
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

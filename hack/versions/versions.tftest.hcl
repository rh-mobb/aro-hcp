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

mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        enabled = [
          { name = "4.22.9", channelGroup = "stable" },
          { name = "4.22.10", channelGroup = "stable" },
        ]
      }
    }
  }
}

variables {
  location = "australiaeast"
}

run "lists_enabled_patches_and_streams" {
  command = plan

  assert {
    condition     = contains(local.patches["stable"], "4.22.10")
    error_message = "Enabled patches must include 4.22.10 from the ARM list."
  }

  assert {
    condition     = contains(local.streams["stable"], "4.22")
    error_message = "Enabled streams must include 4.22 from patch names."
  }
}

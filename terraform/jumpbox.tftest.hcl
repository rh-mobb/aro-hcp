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
  enable_jumpbox      = false
}

run "jumpbox_off_by_default" {
  command = plan

  assert {
    condition     = length(module.jumpbox) == 0
    error_message = "Jump box module must be disabled by default."
  }
}

run "jumpbox_enabled" {
  command = plan

  variables {
    enable_jumpbox         = true
    jump_ssh_source_prefix = "203.0.113.10/32"
    # Valid ed25519 pubkey (azurerm validates key material during plan)
    jump_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB9ZPmSkVDQJ1HKpG4edUDTVSxf5OMQmRlk3uwkJ0zd/ test"
  }

  assert {
    condition     = length(module.jumpbox) == 1
    error_message = "Jump box module must be created when enable_jumpbox is true."
  }

  # Child module resources are not addressable from root tests; assert via outputs.
  assert {
    condition     = module.jumpbox[0].subnet_address_prefix == "10.0.2.0/28"
    error_message = "Jump subnet must be 10.0.2.0/28."
  }

  assert {
    condition     = module.jumpbox[0].vm_size == "Standard_D2s_v6"
    error_message = "Jump VM size must be Standard_D2s_v6."
  }

  assert {
    condition     = contains(module.jumpbox[0].nsg_ssh_source_prefixes, "203.0.113.10/32")
    error_message = "Jump NSG must allow SSH 22 from jump_ssh_source_prefix."
  }
}

run "jumpbox_requires_source_prefix" {
  command = plan

  variables {
    enable_jumpbox      = true
    jump_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB9ZPmSkVDQJ1HKpG4edUDTVSxf5OMQmRlk3uwkJ0zd/ test"
  }

  expect_failures = [
    terraform_data.jumpbox_prereqs[0],
  ]
}

run "jumpbox_requires_public_key" {
  command = plan

  variables {
    enable_jumpbox         = true
    jump_ssh_source_prefix = "203.0.113.10/32"
  }

  expect_failures = [
    terraform_data.jumpbox_prereqs[0],
  ]
}

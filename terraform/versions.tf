terraform {
  required_version = ">= 1.9.0"

  # Per-cluster state path via: terraform init -reconfigure -backend-config="path=../clusters/<name>/infrastructure.tfstate"
  backend "local" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.1"
    }
  }
}

terraform {
  required_version = ">=1.3.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "1.13.1"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

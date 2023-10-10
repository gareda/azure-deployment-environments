terraform {
  required_version = ">=1.3.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "1.9.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

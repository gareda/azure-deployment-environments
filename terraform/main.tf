data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = "${local.name}rg-01"
  location = "West Europe"
  tags     = {}
}

resource "azurerm_key_vault" "kv" {
  name                      = "${local.name}kv"
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  tags                      = azurerm_resource_group.rg.tags
  tenant_id                 = data.azurerm_client_config.current.tenant_id
  sku_name                  = "standard"
  enable_rbac_authorization = true
  purge_protection_enabled  = false
}

resource "azurerm_role_assignment" "key_vault_administrator" {
  scope                = azurerm_key_vault.kv.id
  principal_id         = data.azurerm_client_config.current.object_id
  role_definition_name = "Key Vault Administrator"
}

resource "azurerm_key_vault_secret" "github_personal_access_token" {
  depends_on   = [azurerm_role_assignment.key_vault_administrator]
  key_vault_id = azurerm_key_vault.kv.id
  name         = "GitHubPersonalAccessToken"
  value        = var.github_personal_access_token
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${local.name}vnet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = azurerm_resource_group.rg.tags
  address_space       = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "databox" {
  name                                      = "databox"
  resource_group_name                       = azurerm_virtual_network.vnet.resource_group_name
  virtual_network_name                      = azurerm_virtual_network.vnet.name
  address_prefixes                          = [cidrsubnet(azurerm_virtual_network.vnet.address_space[0], 0, 0)]
  private_endpoint_network_policies_enabled = true
}

resource "azapi_resource" "dct" {
  name      = "${local.name}dct"
  type      = "Microsoft.DevCenter/devcenters@${local.api_version}"
  parent_id = azurerm_resource_group.rg.id
  location  = azurerm_resource_group.rg.location
  tags      = azurerm_resource_group.rg.tags

  identity {
    type         = "SystemAssigned"
    identity_ids = []
  }
}

resource "azurerm_role_assignment" "owner" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  principal_id         = azapi_resource.dct.identity[0].principal_id
  role_definition_name = "Owner"
}

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = azurerm_key_vault_secret.github_personal_access_token.resource_versionless_id
  principal_id         = azapi_resource.dct.identity[0].principal_id
  role_definition_name = "Key Vault Secrets User"
}

resource "azapi_resource" "nc" {
  name      = "${local.name}nc"
  type      = "Microsoft.DevCenter/networkConnections@${local.api_version}"
  parent_id = azapi_resource.dct.id
  location  = azurerm_resource_group.rg.location
  tags      = azurerm_resource_group.rg.tags
  body = {
    properties = {
      domainJoinType              = "AzureADJoin"
      networkingResourceGroupName = "${local.name}rg-01"
      subnetId                    = azurerm_subnet.databox.id
    }
  }
}

resource "azapi_resource" "microsoft_example" {
  name      = "MicrosoftExample"
  type      = "Microsoft.DevCenter/devcenters/catalogs@${local.api_version}"
  parent_id = azapi_resource.dct.id
  body = {
    properties = {
      gitHub = {
        uri              = "https://github.com/Azure/deployment-environments.git"
        branch           = "main"
        path             = "/Environments"
        secretIdentifier = azurerm_key_vault_secret.github_personal_access_token.id
      }
    }
  }
}

resource "azapi_resource" "cumtom_example" {
  name      = "CustomExample"
  type      = "Microsoft.DevCenter/devcenters/catalogs@${local.api_version}"
  parent_id = azapi_resource.dct.id
  body = {
    properties = {
      gitHub = {
        uri              = "https://github.com/gareda/azure-deployment-environments.git"
        branch           = "main"
        path             = "/templates"
        secretIdentifier = azurerm_key_vault_secret.github_personal_access_token.id
      }
    }
  }
}

resource "azapi_resource" "development" {
  name      = "development"
  type      = "Microsoft.DevCenter/devcenters/environmentTypes@${local.api_version}"
  parent_id = azapi_resource.dct.id
  tags      = azurerm_resource_group.rg.tags
}

resource "azapi_resource" "production" {
  name      = "production"
  type      = "Microsoft.DevCenter/devcenters/environmentTypes@${local.api_version}"
  parent_id = azapi_resource.dct.id
  tags      = azurerm_resource_group.rg.tags
}

resource "azapi_resource" "project_01" {
  name      = "project01"
  type      = "Microsoft.DevCenter/projects@${local.api_version}"
  parent_id = azurerm_resource_group.rg.id
  location  = azurerm_resource_group.rg.location
  tags      = azurerm_resource_group.rg.tags
  body = {
    properties = {
      devCenterId = azapi_resource.dct.id
    }
  }
}

resource "azapi_resource" "project_02" {
  name      = "project02"
  type      = "Microsoft.DevCenter/projects@${local.api_version}"
  parent_id = azurerm_resource_group.rg.id
  location  = azurerm_resource_group.rg.location
  tags      = azurerm_resource_group.rg.tags
  body = {
    properties = {
      devCenterId = azapi_resource.dct.id
    }
  }
}

resource "azapi_resource" "project_01_development" {
  name      = azapi_resource.development.name
  type      = "Microsoft.DevCenter/projects/environmentTypes@${local.api_version}"
  parent_id = azapi_resource.project_01.id
  location  = azurerm_resource_group.rg.location

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      deploymentTargetId = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
      status             = "Enabled"
      creatorRoleAssignment = {
        roles = {
          "b24988ac-6180-42a0-ab88-20f7382dd24c" : {} # Contributor
        }
      }
    }
  }
}

resource "azapi_resource" "project_01_production" {
  name      = azapi_resource.production.name
  type      = "Microsoft.DevCenter/projects/environmentTypes@${local.api_version}"
  location  = azurerm_resource_group.rg.location
  parent_id = azapi_resource.project_01.id

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      deploymentTargetId = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
      status             = "Enabled"
      creatorRoleAssignment = {
        roles = {
          "b24988ac-6180-42a0-ab88-20f7382dd24c" : {} # Contributor
        }
      }
    }
  }
}

resource "azapi_resource" "project_02_production" {
  name      = azapi_resource.production.name
  type      = "Microsoft.DevCenter/projects/environmentTypes@${local.api_version}"
  location  = azurerm_resource_group.rg.location
  parent_id = azapi_resource.project_02.id

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      deploymentTargetId = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
      status             = "Enabled"
      creatorRoleAssignment = {
        roles = {
          "b24988ac-6180-42a0-ab88-20f7382dd24c" : {} # Contributor
        }
      }
    }
  }
}

data "azurerm_client_config" "current" {}

#################### RESOURCE GROUP
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group

resource "azurerm_resource_group" "rg" {
  name     = local.name
  location = "West Europe"
  tags     = {}
}

#################### KEY VAULT
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret

resource "azurerm_key_vault" "kv" {
  name                      = "${local.name}-kv"
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

#################### VIRTUAL NETWORK
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet

resource "azurerm_virtual_network" "vnet" {
  name                = "${local.name}-vnet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = azurerm_resource_group.rg.tags
  address_space       = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "databox" {
  name                              = "databox"
  resource_group_name               = azurerm_virtual_network.vnet.resource_group_name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = [cidrsubnet(azurerm_virtual_network.vnet.address_space[0], 0, 0)]
  private_endpoint_network_policies = "Enabled"
}

#################### DEV CENTER
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dev_center
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment

resource "azurerm_dev_center" "dct" {
  name                = "${local.name}-dct"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = azurerm_resource_group.rg.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "owner" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  principal_id         = azurerm_dev_center.dct.identity[0].principal_id
  role_definition_name = "Owner"
}

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = azurerm_key_vault_secret.github_personal_access_token.resource_versionless_id
  principal_id         = azurerm_dev_center.dct.identity[0].principal_id
  role_definition_name = "Key Vault Secrets User"
}

# resource "azapi_resource" "nc" {
#   name      = "${local.name}-nc"
#   type      = "Microsoft.DevCenter/networkConnections@${local.api_version}"
#   parent_id = azurerm_dev_center.dct.id
#   location  = azurerm_resource_group.rg.location
#   tags      = azurerm_resource_group.rg.tags

#   body = {
#     properties = {
#       domainJoinType              = "AzureADJoin"
#       networkingResourceGroupName = "${local.name}rg-01"
#       subnetId                    = azurerm_subnet.databox.id
#     }
#   }
# }

resource "azurerm_dev_center_catalog" "microsoft_example" {
  name                = "MicrosoftExample"
  resource_group_name = azurerm_dev_center.dct.resource_group_name
  dev_center_id       = azurerm_dev_center.dct.id

  catalog_github {
    uri               = "https://github.com/Azure/deployment-environments.git"
    branch            = "main"
    path              = "/Environments"
    key_vault_key_url = azurerm_key_vault_secret.github_personal_access_token.versionless_id
  }
}

resource "azurerm_dev_center_catalog" "cumtom_example" {
  name                = "CustomExample"
  resource_group_name = azurerm_dev_center.dct.resource_group_name
  dev_center_id       = azurerm_dev_center.dct.id

  catalog_github {
    uri               = "https://github.com/gareda/azure-deployment-environments.git"
    branch            = "main"
    path              = "/templates"
    key_vault_key_url = azurerm_key_vault_secret.github_personal_access_token.versionless_id
  }
}

resource "azapi_resource" "development" {
  name      = "development"
  type      = "Microsoft.DevCenter/devcenters/environmentTypes@${local.api_version}"
  parent_id = azurerm_dev_center.dct.id
  tags      = azurerm_resource_group.rg.tags
}

resource "azapi_resource" "production" {
  name      = "production"
  type      = "Microsoft.DevCenter/devcenters/environmentTypes@${local.api_version}"
  parent_id = azurerm_dev_center.dct.id
  tags      = azurerm_resource_group.rg.tags
}

resource "azurerm_dev_center_project" "project_01" {
  name                = "project01"
  dev_center_id       = azurerm_dev_center.dct.id
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = azurerm_resource_group.rg.tags
}

resource "azurerm_dev_center_project" "project_02" {
  name                = "project02"
  dev_center_id       = azurerm_dev_center.dct.id
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = azurerm_resource_group.rg.tags
}

resource "azapi_resource" "project_01_development" {
  name      = azapi_resource.development.name
  type      = "Microsoft.DevCenter/projects/environmentTypes@${local.api_version}"
  parent_id = azurerm_dev_center_project.project_01.id
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
  parent_id = azurerm_dev_center_project.project_01.id

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
  parent_id = azurerm_dev_center_project.project_02.id

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

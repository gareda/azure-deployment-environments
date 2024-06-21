data "azurerm_client_config" "current" {}

#################### RESOURCE GROUP
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group

resource "azurerm_resource_group" "rg" {
  name     = local.name
  location = "North Europe"
  tags     = {}
}

#################### KEY VAULT
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret

resource "azurerm_key_vault" "kv" {
  name                      = "${local.name}-kv-01"
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
  name                = "${local.name}-vnet-01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = azurerm_resource_group.rg.tags
  address_space       = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "dev_box_networking" {
  name                 = "dev-box-networking"
  resource_group_name  = azurerm_virtual_network.vnet.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [cidrsubnet(azurerm_virtual_network.vnet.address_space[0], 0, 0)]
}

#################### AZURE CONTAINER REGISTRY
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry

resource "azurerm_container_registry" "cr" {
  name                = "${replace(local.name, "-", "")}cr01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = azurerm_resource_group.rg.tags
  sku                 = "Basic"
}

#################### DEV CENTER
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dev_center
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment

resource "azurerm_dev_center" "dct" {
  name                = "${local.name}-dct-01"
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

#################### DEV CENTER - DEV BOX CONFIGURATION
# https://learn.microsoft.com/en-us/azure/templates/microsoft.devcenter/networkconnections
# https://learn.microsoft.com/en-us/azure/templates/microsoft.devcenter/devcenters/attachednetworks
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/shared_image_gallery
# https://learn.microsoft.com/en-us/azure/templates/microsoft.devcenter/devcenters/galleries
# https://learn.microsoft.com/en-us/azure/templates/microsoft.devcenter/devcenters/devboxdefinitions

resource "azapi_resource" "nc" {
  name      = "${local.name}-nc-01"
  type      = "Microsoft.DevCenter/networkConnections@${local.api_version}"
  parent_id = azurerm_resource_group.rg.id
  location  = azurerm_resource_group.rg.location
  tags      = azurerm_resource_group.rg.tags

  body = {
    properties = {
      domainJoinType              = "AzureADJoin"
      networkingResourceGroupName = "${local.name}-network"
      subnetId                    = azurerm_subnet.dev_box_networking.id
    }
  }
}

resource "azapi_resource" "dct_connect_nc" {
  name      = "${local.name}-nc-01"
  type      = "Microsoft.DevCenter/devcenters/attachednetworks@${local.api_version}"
  parent_id = azurerm_dev_center.dct.id

  body = {
    properties = {
      networkConnectionId = azapi_resource.nc.id
    }
  }
}

resource "azurerm_shared_image_gallery" "shg" {
  name                = "${replace(local.name, "-", "")}shg01"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = azurerm_resource_group.rg.tags
}

resource "azapi_resource" "dct_connect_shg" {
  name      = "${replace(local.name, "-", "")}shg01"
  type      = "Microsoft.DevCenter/devcenters/galleries@${local.api_version}"
  parent_id = azurerm_dev_center.dct.id

  body = {
    properties = {
      galleryResourceId = azurerm_shared_image_gallery.shg.id
    }
  }
}

resource "azapi_resource" "dbd_visual_studio" {
  name      = "visual-studio"
  type      = "Microsoft.DevCenter/devcenters/devboxdefinitions@${local.api_version}"
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_dev_center.dct.id

  body = {
    properties = {
      imageReference = {
        id = "${azurerm_dev_center.dct.id}/galleries/default/images/microsoftvisualstudio_visualstudioplustools_vs-2022-ent-general-win11-m365-gen2"
      },
      sku = {
        name = "general_i_8c32gb256ssd_v2"
      },
      hibernateSupport = "Disabled"
    }
  }
}

resource "azapi_resource" "dbd_sandbox" {
  name      = "sandbox"
  type      = "Microsoft.DevCenter/devcenters/devboxdefinitions@${local.api_version}"
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_dev_center.dct.id

  body = {
    properties = {
      imageReference = {
        id = "${azurerm_dev_center.dct.id}/galleries/default/images/microsoftwindowsdesktop_windows-ent-cpc_win11-22h2-ent-cpc-os"
      },
      sku = {
        name = "general_i_8c32gb256ssd_v2"
      },
      hibernateSupport = "Disabled"
    }
  }
}

#################### DEV CENTER - ENVIRONMENT CONFIGURATION
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dev_center_catalogs

resource "azurerm_dev_center_catalog" "azure_examples" {
  name                = "AzureExamples"
  resource_group_name = azurerm_dev_center.dct.resource_group_name
  dev_center_id       = azurerm_dev_center.dct.id

  catalog_github {
    uri               = "https://github.com/Azure/deployment-environments.git"
    branch            = "main"
    path              = "/Environments"
    key_vault_key_url = azurerm_key_vault_secret.github_personal_access_token.versionless_id
  }
}

resource "azurerm_dev_center_catalog" "microsoft_task_examples" {
  name                = "MicrosoftExamples"
  resource_group_name = azurerm_dev_center.dct.resource_group_name
  dev_center_id       = azurerm_dev_center.dct.id

  catalog_github {
    uri               = "https://github.com/microsoft/devcenter-catalog.git"
    branch            = "main"
    path              = "/Tasks"
    key_vault_key_url = azurerm_key_vault_secret.github_personal_access_token.versionless_id
  }
}

resource "azurerm_dev_center_catalog" "cumtom_example" {
  name                = "CustomExamples"
  resource_group_name = azurerm_dev_center.dct.resource_group_name
  dev_center_id       = azurerm_dev_center.dct.id

  catalog_github {
    uri               = "https://github.com/gareda/azure-deployment-environments.git"
    branch            = "main"
    path              = "/templates"
    key_vault_key_url = azurerm_key_vault_secret.github_personal_access_token.versionless_id
  }
}

resource "azapi_resource" "develop" {
  name      = "develop"
  type      = "Microsoft.DevCenter/devcenters/environmentTypes@${local.api_version}"
  parent_id = azurerm_dev_center.dct.id
  tags      = azurerm_resource_group.rg.tags
}

resource "azapi_resource" "sandbox" {
  name      = "sandbox"
  type      = "Microsoft.DevCenter/devcenters/environmentTypes@${local.api_version}"
  parent_id = azurerm_dev_center.dct.id
  tags      = azurerm_resource_group.rg.tags
}

#################### DEV CENTER - PROJECTS
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dev_center_project
# https://learn.microsoft.com/en-us/azure/templates/microsoft.devcenter/projects/environmenttypes

resource "azurerm_dev_center_project" "madrid" {
  name                       = "${azurerm_resource_group.rg.name}-madrid"
  dev_center_id              = azurerm_dev_center.dct.id
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  tags                       = azurerm_resource_group.rg.tags
  maximum_dev_boxes_per_user = 2
}

resource "azurerm_dev_center_project" "malaga" {
  name                       = "${azurerm_resource_group.rg.name}-malaga"
  dev_center_id              = azurerm_dev_center.dct.id
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  tags                       = azurerm_resource_group.rg.tags
  maximum_dev_boxes_per_user = 1
}

resource "azapi_resource" "madrid_develop" {
  name      = azapi_resource.develop.name
  type      = "Microsoft.DevCenter/projects/environmentTypes@${local.api_version}"
  parent_id = azurerm_dev_center_project.madrid.id
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

resource "azapi_resource" "madrid_sandbox" {
  name      = azapi_resource.sandbox.name
  type      = "Microsoft.DevCenter/projects/environmentTypes@${local.api_version}"
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_dev_center_project.madrid.id

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

resource "azapi_resource" "malaga_develop" {
  name      = azapi_resource.develop.name
  type      = "Microsoft.DevCenter/projects/environmentTypes@${local.api_version}"
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_dev_center_project.malaga.id

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

#################### DEV CENTER - PROJECTS - MANAGE
# https://learn.microsoft.com/en-us/azure/templates/microsoft.devcenter/projects/pools

resource "azapi_resource" "visual_studio_external" {
  name      = "vs-external-network"
  type      = "Microsoft.DevCenter/projects/pools@${local.api_version}"
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_dev_center_project.madrid.id

  body = {
    properties = {
      displayName           = "Visual Studio External"
      devBoxDefinitionName  = azapi_resource.dbd_visual_studio.name
      networkConnectionName = azapi_resource.nc.name
      licenseType           = "Windows_Client"
      localAdministrator    = "Enabled"
      singleSignOnStatus    = "Enabled"
    }
  }

  lifecycle {
    ignore_changes = [tags["hidden-title"]]
  }
}

resource "azapi_resource" "visual_studio_internal" {
  name      = "vs-internal-network"
  type      = "Microsoft.DevCenter/projects/pools@${local.api_version}"
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_dev_center_project.madrid.id

  body = {
    properties = {
      displayName           = "Visual Studio Internal"
      devBoxDefinitionName  = azapi_resource.dbd_visual_studio.name
      networkConnectionName = azapi_resource.nc.name
      licenseType           = "Windows_Client"
      localAdministrator    = "Enabled"
      singleSignOnStatus    = "Enabled"
    }
  }

  lifecycle {
    ignore_changes = [tags["hidden-title"]]
  }
}

resource "azapi_resource" "sandbox_external" {
  name      = "sb-external-network"
  type      = "Microsoft.DevCenter/projects/pools@${local.api_version}"
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_dev_center_project.madrid.id

  body = {
    properties = {
      displayName           = "Sandbox External"
      devBoxDefinitionName  = azapi_resource.dbd_sandbox.name
      networkConnectionName = azapi_resource.nc.name
      licenseType           = "Windows_Client"
      localAdministrator    = "Enabled"
      singleSignOnStatus    = "Enabled"
    }
  }

  lifecycle {
    ignore_changes = [tags["hidden-title"]]
  }
}

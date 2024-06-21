resource "azurerm_resource_group" "rg_01" {
  name     = "test"
  location = "Spain Central"
  tags     = {}
}

resource "azurerm_virtual_network" "vnet_01" {
  name                = "test"
  resource_group_name = azurerm_resource_group.rg_01.name
  location            = azurerm_resource_group.rg_01.location
  tags                = azurerm_resource_group.rg_01.tags
  address_space       = ["10.0.0.0/29"]
}

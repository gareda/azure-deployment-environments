var name = skip(resourceGroup().name, 17)
var location = resourceGroup().location

param sku string
param gpt string

resource log 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${name}-log'
  location: location

  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: '${name}-appi'
  location: location
  kind: 'web'

  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: log.id
  }
}

resource cr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  #disable-next-line BCP334
  name: '${replace(name, '-', '')}cr'
  location: location

  sku: {
    name: sku
  }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${name}-kv'
  location: location

  properties: {
    tenantId: subscription().tenantId
    accessPolicies: []
    enableRbacAuthorization: true

    sku: {
      family: 'A'
      name: 'standard'
    }
  }
}

resource st 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  #disable-next-line BCP334
  name: '${replace(name, '-', '')}st'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}

resource mlw 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: '${name}-mlw'
  location: location

  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    applicationInsights: appi.id
    containerRegistry: cr.id
    keyVault: kv.id
    storageAccount: st.id
  }
}

resource ai 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = if (gpt != 'None') {
  name: '${name}-ai'
  location: 'eastus'
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
}

resource dplm 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = if (gpt != 'None') {
  parent: ai
  name: 'gpt-4o'
  sku: {
    name: 'Standard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-05-13'
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
    currentCapacity: 10
    raiPolicyName: 'Microsoft.Default'
  }
}

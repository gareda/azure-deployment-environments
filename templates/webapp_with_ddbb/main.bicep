var name = resourceGroup().name
var location = resourceGroup().location

param sku string
param database string

resource asp 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: '${name}asp'
  location: location
  sku: {
    name: sku
  }
}

resource app 'Microsoft.Web/sites@2022-09-01' = {
  name: '${name}app'
  location: location
  properties: {
    serverFarmId: asp.id
  }
}

resource mysql 'Microsoft.DBforMySQL/flexibleServers@2023-06-30' = if (database == 'MySql') {
  name: '${name}mysqlfs'
  location: location

  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }

  properties: {
    version: '8.0.21'
    administratorLogin: 'adminmysql'
    administratorLoginPassword: 'P4$$w0rd1234'

    backup: {
      backupRetentionDays: 30
    }
  }
}

resource postgre 'Microsoft.DBforPostgreSQL/flexibleServers@2022-12-01' = if (database == 'PostgreSQL') {
  name: '${name}postgrefs'
  location: location

  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }

  properties: {
    version: '15'
    administratorLogin: 'adminpostgre'
    administratorLoginPassword: 'P4$$w0rd1234'

    storage: {
      storageSizeGB: 32
    }

    backup: {
      backupRetentionDays: 30
    }    
  }
}

var name = 'poc-we-dnsrsv-s-'
var location = resourceGroup().location
var zones = [
  'privatelink.azurewebsites.net'
  'privatelink.blob.core.windows.net'
  'privatelink.database.windows.net'
  'privatelink.mysql.database.azure.com'
  'privatelink.postgres.database.azure.com'
]

resource vnet 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: '${name}vnet'
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ '10.0.4.0/26' ] }
    subnets: [ {
        name: 'DnsPrivateResolverInbound'
        properties: {
          addressPrefix: '10.0.4.0/27'
          delegations: [ {
              name: 'Microsoft.Network/dnsResolvers'
              properties: { serviceName: 'Microsoft.Network/dnsResolvers' }
            }
          ]
        }
      }, {
        name: 'DnsPrivateResolverOutbound'
        properties: {
          addressPrefix: '10.0.4.32/27'
          delegations: [ {
              name: 'Microsoft.Network/dnsResolvers'
              properties: { serviceName: 'Microsoft.Network/dnsResolvers' }
            }
          ]
        }
      } ]
  }

  resource dnspr_inbound 'subnets' existing = {
    name: 'DnsPrivateResolverInbound'
  }

  resource dnspr_outbound 'subnets' existing = {
    name: 'DnsPrivateResolverOutbound'
  }
}

resource rt 'Microsoft.Network/routeTables@2023-04-01' = {
  name: '${name}rt'
  location: location
  properties: {
    disableBgpRoutePropagation: true
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: '${name}nsg'
  location: location
  properties: {
    securityRules: [ {
        name: 'DomainNameSystem'
        properties: {
          priority: 100
          direction: 'Inbound'
          protocol: 'TCP'
          access: 'Allow'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: dnspr::inbound.properties.ipConfigurations[0].privateIpAddress
          destinationPortRange: '53'
        }
      }, {
        name: 'DenyAll'
        properties: {
          priority: 4096
          direction: 'Inbound'
          protocol: '*'
          access: 'Deny'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      } ]
  }
}

resource dnspr 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: '${name}dnspr'
  location: location
  properties: { virtualNetwork: { id: vnet.id } }

  resource inbound 'inboundEndpoints' = {
    name: 'Azure'
    location: location
    properties: { ipConfigurations: [ { subnet: { id: vnet::dnspr_inbound.id } } ] }
  }

  resource outbound 'outboundEndpoints' = {
    name: 'Local'
    location: location
    properties: { subnet: { id: vnet::dnspr_outbound.id } }
  }
}

resource dnsfr 'Microsoft.Network/dnsForwardingRulesets@2022-07-01' = {
  name: '${name}dnsfr'
  location: location
  properties: {
    dnsResolverOutboundEndpoints: [ { id: dnspr::outbound.id } ]
  }

  resource plainconcepts 'forwardingRules' = {
    name: 'plainconcepts'
    properties: {
      domainName: 'plainconcepts.com.'
      forwardingRuleState: 'Enabled'
      targetDnsServers: [ {
          ipAddress: '10.0.0.4'
          port: 53
        } ]
    }
  }

  resource dnsfr_link 'virtualNetworkLinks' = {
    name: '${name}vnet-link'
    properties: { virtualNetwork: { id: vnet.id } }
  }
}

resource dns_zones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zone in zones: {
  name: zone
  location: 'global'
}]

resource azurewebsites_net_link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone, i) in zones: {
  name: '${name}vnet-link'
  location: 'global'
  parent: dns_zones[i]
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnet.id }
  }
}]

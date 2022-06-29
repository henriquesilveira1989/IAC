param project string 
param env string 
param location string


var name_vnet = 'vnet-${project}-${env}'
var name_snet = 'subnet-${project}-${env}'

// Creates a virtual network
@description('Tags to add to the resources')
param tags object = {}
//@description('Group ID of the network security group')
//param networkSecurityGroupId string = ''
@description('Virtual network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'
@description('Subnet address prefix')
param SubnetPrefix string = '10.0.0.0/24'
param SubnetPrivateEndpointPrefix string = '10.0.1.0/24'

// Start of VNET and Subnet Script //
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2020-07-01' = {
  name: name_vnet
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      { 
        name: name_snet
        properties: {
          addressPrefix: SubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        //  networkSecurityGroup: {
        //    id: networkSecurityGroupId
        //  }
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: SubnetPrivateEndpointPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          
        }
      }
    ]
  }
}


// End of VNET and Subnet Script //

// Start of SQL Server Script //

var servername = 'sqlsrv-${project}-${env}10'
var dbname = 'sqldb-${env}2'

resource sqlserver 'Microsoft.Sql/servers@2019-06-01-preview' = {
  location: location
  name: servername
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    administratorLogin: 'c5admin'
    administratorLoginPassword: 'DPL@admin123'
  }
}

resource sqldatabase 'Microsoft.Sql/servers/databases@2020-08-01-preview' = {
  name:  '${sqlserver.name}/${dbname}'
  location: location
  sku: {
    name: 'Basic'
  }
}
// End of SQL Server Script //

// Start of ADF Script //
var nameadf = 'adf-${project}-${env}10'

resource adf 'Microsoft.DataFactory/factories@2018-06-01'= {
  name: nameadf
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties:{

  }
  }

// END of ADF Script //

// Start of Storage Account Script //

param containerNames array = [
  'raw'
  'clean'
  'transformed'
]

var namesta = 'sta${project}${env}'

resource storage 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: namesta
  location: location 
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS' 
  }
  properties: {
    accessTier: 'Hot'
    isHnsEnabled:true
    networkAcls: {
      
      bypass:'None'
      defaultAction: 'Deny'

    }
  } 
}

resource blob 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = [for name in containerNames: {
  name: '${storage.name}/default/${name}'
}]

// End of Storage Account Script //

// Start of Key Vault Script //
var namekv = 'kv-${project}-${env}'

resource keyvault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: namekv
  location: location
  
  properties :{
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
  }
}

// End of Key Vault Script //

// Start of Synapse Script

resource blob2 'Microsoft.Storage/storageAccounts/blobServices@2021-02-01' = {
  name:  '${storage.name}/default'
}

resource containera 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-02-01' = {
  name: '${storage.name}/default/synapsedl'
  properties: {
    publicAccess: 'None'
  }
  dependsOn:[
    blob
  ]
} 
var namesynapse = 'synapse-${project}-${env}'


resource synapseWS 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: namesynapse
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
    
  }
  tags: {
    Env: env
    ringValue: 'r1'
  }
  properties: {
    sqlAdministratorLogin: 'c5admin'
    defaultDataLakeStorage: {
      resourceId: storage.id
      accountUrl: storage.properties.primaryEndpoints.dfs //'https://x.dfs.core.windows.net'
      filesystem: 'synapsedl'
      
    }
    managedVirtualNetwork: 'default'
    managedVirtualNetworkSettings: {
      preventDataExfiltration: true
    }
    trustedServiceBypassEnabled: true
    
  }
}

// End of Synapse Script



// Private DnsZones and Private EndPoint Script //

var azureSqlPrivateDnsZone = 'privatelink.database.windows.net'
var keyVaultPrivateDnsZone = 'privatelink.vaultcore.azure.net'
var SynapsePrivateDnsZone = 'privatelink.azuresynapse.net'
var StorageAccountPrivateDnsZone = 'privatelink.blob.core.windows.net'
var DataFactoryPrivateDnsZone = 'privatelink.datafactory.azure.net'

var privateDnsZoneNames = [
  azureSqlPrivateDnsZone
  keyVaultPrivateDnsZone
  SynapsePrivateDnsZone
  StorageAccountPrivateDnsZone
  DataFactoryPrivateDnsZone
]


resource privateDnsZones 'Microsoft.Network/privateDnsZones@2018-09-01' = [for privateDnsZoneName in privateDnsZoneNames: {
  name: privateDnsZoneName
  location: 'global'
  dependsOn: [
    virtualNetwork
     ]
}]

resource virtualNetworkLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (privateDnsZoneName, i) in privateDnsZoneNames: {
  parent: privateDnsZones[i]
  location: 'global'
  name: 'link-to-${virtualNetwork.name}'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}]


resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2020-06-01' = {
  name: '${sqlserver.name}-sql-pe'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: virtualNetwork.properties.subnets[1].id
       }
    privateLinkServiceConnections: [
      {
        name: '${sqlserver.name}-sql-pe-conn'
        properties: {
          privateLinkServiceId: sqlserver.id
          groupIds: [
            'sqlserver'
          ]
        }
      }
    ]
  }
 
  resource privateDnsZoneGroup 'privateDnsZoneGroups@2020-03-01' = {
    name: 'dnsgroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', azureSqlPrivateDnsZone)
          }
        }
      ]
    }
  }
}

resource stgPrivateEndpoint 'Microsoft.Network/privateEndpoints@2020-06-01' = {
  name: '${storage.name}-stg-pe'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: virtualNetwork.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${storage.name}-stg-pe-conn'
        properties: {
          privateLinkServiceId: storage.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
 
  resource privateDnsZoneGroup 'privateDnsZoneGroups@2020-03-01' = {
    name: 'dnsgroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', StorageAccountPrivateDnsZone)
          }
        }
      ]
    }
  }
}

resource ADFPrivateEndpoint 'Microsoft.Network/privateEndpoints@2020-06-01' = {
  name: '${adf.name}-adf-pe'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: virtualNetwork.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${adf.name}-adf-pe-conn'
        properties: {
          privateLinkServiceId: adf.id
          groupIds: [
            'dataFactory'
          ]
        }
      }
    ]
  }
 
  resource privateDnsZoneGroup 'privateDnsZoneGroups@2020-03-01' = {
    name: 'dnsgroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', DataFactoryPrivateDnsZone)
          }
        }
      ]
    }
  }
}

resource SynapsePrivateEndpoint 'Microsoft.Network/privateEndpoints@2020-06-01' = {
  name: '${synapseWS.name}-saws-pe'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: virtualNetwork.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${synapseWS.name}-saws-pe-conn'
        properties: {
          privateLinkServiceId: synapseWS.id
          groupIds: [
            'Dev'
          ]
        }
      }
    ]
  }

  resource privateDnsZoneGroup 'privateDnsZoneGroups@2020-03-01' = {
    name: 'dnsgroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', SynapsePrivateDnsZone)
          }
        }
      ]
    }
  }
}

resource KeyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2020-06-01' = {
  name: '${keyvault.name}-kv-pe'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: virtualNetwork.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${keyvault.name}-kv-pe-conn'
        properties: {
          privateLinkServiceId: keyvault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
 
  resource privateDnsZoneGroup 'privateDnsZoneGroups@2020-03-01' = {
    name: 'dnsgroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', keyVaultPrivateDnsZone)
          }
        }
      ]
    }
  }
}

// ============================================================================
// main.bicep - SQL CES Fabric Infrastructure
// ============================================================================
// Deploys:
//   - User-Assigned Managed Identity (for SQL database authentication)
//   - Virtual Network with Private Endpoint subnet
//   - Private DNS Zone (privatelink.database.windows.net) linked to VNet
//   - SQL Server (Entra ID only) with:
//       - Elastic Pool (Standard 200 eDTU)
//       - Databases: tenant_db_alpha, tenant_db_beta
//       - Private Endpoint for secure connectivity
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('Azure region for all resources.')
param location string

@description('Naming prefix for all resources (2-10 characters).')
@minLength(2)
@maxLength(10)
param namePrefix string

@description('Address space for the virtual network.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for the private endpoint subnet.')
param privateEndpointSubnetPrefix string = '10.0.1.0/24'

@description('Entra ID administrator login name (display name of the group or user).')
param entraAdminLogin string

@description('Entra ID administrator object ID (SID).')
param entraAdminSid string

@description('Entra ID tenant ID. Defaults to the current tenant.')
param entraAdminTenantId string = tenant().tenantId

@description('Tags to apply to all resources.')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================

var sqlServerName = '${namePrefix}-sql-server'
var elasticPoolName = '${namePrefix}-elastic-pool'
var vnetName = '${namePrefix}-vnet'
var privateEndpointSubnetName = 'snet-private-endpoints'
var uamiName = '${namePrefix}-uami-sql'
var privateDnsZoneName = 'privatelink${environment().suffixes.sqlServerHostname}'

// ============================================================================
// User-Assigned Managed Identity
// ============================================================================

module userAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'deploy-uami'
  params: {
    name: uamiName
    location: location
    tags: tags
  }
}

// ============================================================================
// Virtual Network
// ============================================================================

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.5.2' = {
  name: 'deploy-vnet'
  params: {
    name: vnetName
    location: location
    addressPrefixes: [
      vnetAddressPrefix
    ]
    subnets: [
      {
        name: privateEndpointSubnetName
        addressPrefix: privateEndpointSubnetPrefix
      }
    ]
    tags: tags
  }
}

// ============================================================================
// Private DNS Zone
// ============================================================================

module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  name: 'deploy-private-dns-zone'
  params: {
    name: privateDnsZoneName
    location: 'global'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetwork.outputs.resourceId
        registrationEnabled: false
      }
    ]
    tags: tags
  }
}

// ============================================================================
// SQL Server with Elastic Pool, Databases, and Private Endpoint
// ============================================================================

module sqlServer 'br/public:avm/res/sql/server:0.12.0' = {
  name: 'deploy-sql-server'
  params: {
    name: sqlServerName
    location: location

    // Enable Security Alert Policy (Defender for SQL)
    securityAlertPolicies: [
      {
        name: 'Default'
        emailAccountAdmins: true
        state: 'Enabled'
      }
    ]

    // Entra ID only authentication (no SQL auth)
    administrators: {
      azureADOnlyAuthentication: true
      login: entraAdminLogin
      sid: entraAdminSid
      principalType: 'Group'
      tenantId: entraAdminTenantId
    }

    // Server-level managed identity
    managedIdentities: {
      userAssignedResourceIds: [
        userAssignedIdentity.outputs.resourceId
      ]
    }
    primaryUserAssignedIdentityId: userAssignedIdentity.outputs.resourceId

    // Disable public network access — private endpoint only
    publicNetworkAccess: 'Disabled'

    // Elastic Pool — Standard 200 eDTU (DTU model)
    elasticPools: [
      {
        name: elasticPoolName
        availabilityZone: 'NoPreference' // No specific zone
        sku: {
          name: 'StandardPool'
          tier: 'Standard'
          capacity: 200
        }
        maxSizeBytes: 53687091200 // 50 GB - valid for Standard 200 eDTU
        zoneRedundant: false
        perDatabaseSettings: {
          minCapacity: '0'
          maxCapacity: '100' // Max DTU per database (must be >= 10 for Standard)
        }
      }
    ]

    // Databases in the elastic pool with user-assigned managed identity
    databases: [
      {
        name: 'tenant_db_alpha'
        availabilityZone: 'NoPreference' // No specific zone
        sku: {
          name: 'ElasticPool'
          tier: 'Standard'
        }
        elasticPoolResourceId: resourceId(
          'Microsoft.Sql/servers/elasticPools',
          sqlServerName,
          elasticPoolName
        )
        maxSizeBytes: 2147483648 // 2 GB - explicit size for Standard tier
        zoneRedundant: false
      }
      {
        name: 'tenant_db_beta'
        availabilityZone: 'NoPreference' // No specific zone
        sku: {
          name: 'ElasticPool'
          tier: 'Standard'
        }
        elasticPoolResourceId: resourceId(
          'Microsoft.Sql/servers/elasticPools',
          sqlServerName,
          elasticPoolName
        )
        maxSizeBytes: 2147483648 // 2 GB - explicit size for Standard tier
        zoneRedundant: false
      }
    ]

    // Private Endpoint on the SQL Server
    privateEndpoints: [
      {
        subnetResourceId: virtualNetwork.outputs.subnetResourceIds[0]
        service: 'sqlServer'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDnsZone.outputs.resourceId
            }
          ]
        }
        tags: tags
      }
    ]

    tags: tags
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The resource ID of the SQL Server.')
output sqlServerResourceId string = sqlServer.outputs.resourceId

@description('The fully qualified domain name of the SQL Server.')
output sqlServerFqdn string = sqlServer.outputs.fullyQualifiedDomainName

@description('The resource ID of the virtual network.')
output vnetResourceId string = virtualNetwork.outputs.resourceId

@description('The resource ID of the private DNS zone.')
output privateDnsZoneResourceId string = privateDnsZone.outputs.resourceId

@description('The resource ID of the user-assigned managed identity.')
output uamiResourceId string = userAssignedIdentity.outputs.resourceId

@description('The client ID of the user-assigned managed identity.')
output uamiClientId string = userAssignedIdentity.outputs.clientId

@description('The principal ID of the user-assigned managed identity.')
output uamiPrincipalId string = userAssignedIdentity.outputs.principalId

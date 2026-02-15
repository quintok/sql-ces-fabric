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

@description('Address prefix for the container instances subnet.')
param containerSubnetPrefix string = '10.0.2.0/24'

@description('Deploy the load generator container instance. Set to true after pushing the container image.')
param deployLoadGenerator bool = false

@description('Container image for the load generator (e.g., myregistry.azurecr.io/loadgen:latest).')
param loadGeneratorImage string = ''

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
var containerSubnetName = 'snet-containers'
var uamiName = '${namePrefix}-uami-sql'
var acrName = 'acr${uniqueString(resourceGroup().id)}' // 16 chars, alphanumeric, globally unique
var aciName = '${namePrefix}-loadgen'
var privateDnsZoneName = 'privatelink${environment().suffixes.sqlServerHostname}'
var logAnalyticsName = '${namePrefix}-log-analytics'
var appInsightsName = '${namePrefix}-app-insights'

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
// Log Analytics Workspace (for container diagnostics)
// ============================================================================

module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.9.0' = {
  name: 'deploy-log-analytics'
  params: {
    name: logAnalyticsName
    location: location
    skuName: 'PerGB2018'
    dataRetention: 30
    tags: tags
  }
}

// ============================================================================
// Application Insights (for load generator telemetry)
// ============================================================================

module applicationInsights 'br/public:avm/res/insights/component:0.4.2' = {
  name: 'deploy-app-insights'
  params: {
    name: appInsightsName
    location: location
    workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    kind: 'web'
    applicationType: 'web'
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
      {
        name: containerSubnetName
        addressPrefix: containerSubnetPrefix
        // Delegation required for Azure Container Instances
        delegation: 'Microsoft.ContainerInstance/containerGroups'
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
// Azure Container Registry (for load generator image)
// ============================================================================

module containerRegistry 'modules/container-registry.bicep' = {
  name: 'deploy-acr'
  params: {
    name: acrName
    location: location
    sku: 'Basic'
    adminUserEnabled: true
    tags: tags
  }
}

// Grant managed identity AcrPull role on ACR (required for ACI to pull images)
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, acrName, uamiName, 'acrpull')
  scope: containerRegistryResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: userAssignedIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

// Reference to deployed ACR for role assignment scope
resource containerRegistryResource 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
  dependsOn: [containerRegistry]
}

// ============================================================================
// Load Generator Container Instance (conditional)
// ============================================================================

module loadGenerator 'modules/container-instance.bicep' = if (deployLoadGenerator && !empty(loadGeneratorImage)) {
  name: 'deploy-loadgen'
  dependsOn: [acrPullRoleAssignment] // Wait for ACR pull permission
  params: {
    name: aciName
    location: location
    subnetResourceId: virtualNetwork.outputs.subnetResourceIds[1] // Container subnet
    userAssignedIdentityResourceId: userAssignedIdentity.outputs.resourceId
    sqlServerFqdn: sqlServer.outputs.fullyQualifiedDomainName
    databases: 'tenant_db_alpha,tenant_db_beta'
    containerImage: loadGeneratorImage
    acrServer: containerRegistry.outputs.loginServer
    minDelaySeconds: '1'
    maxDelaySeconds: '5'
    appInsightsConnectionString: applicationInsights.outputs.connectionString
    logAnalyticsWorkspaceId: logAnalyticsWorkspace.outputs.resourceId
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
@description('The login server URL of the container registry.')
output acrLoginServer string = containerRegistry.outputs.loginServer

@description('The name of the container registry.')
output acrName string = containerRegistry.outputs.name

@description('The Application Insights connection string.')
output appInsightsConnectionString string = applicationInsights.outputs.connectionString

@description('The Log Analytics workspace ID.')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.outputs.resourceId

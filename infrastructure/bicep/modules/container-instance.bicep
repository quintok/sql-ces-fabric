// ============================================================================
// container-instance.bicep - Load Generator Container Instance
// ============================================================================
// Deploys an Azure Container Instance into a VNet subnet with managed identity
// for SQL authentication. The container runs the synthetic load generator.
// ============================================================================

@description('Name of the container group.')
param name string

@description('Azure region for the container group.')
param location string

@description('Resource ID of the subnet for container deployment.')
param subnetResourceId string

@description('Resource ID of the user-assigned managed identity.')
param userAssignedIdentityResourceId string

@description('SQL Server fully qualified domain name.')
param sqlServerFqdn string

@description('Comma-separated list of database names to target.')
param databases string = 'tenant_db_alpha,tenant_db_beta'

@description('Container image to deploy (include registry).')
param containerImage string

@description('ACR login server (e.g., myacr.azurecr.io).')
param acrServer string

@description('Minimum delay between operations in seconds.')
param minDelaySeconds string = '1'

@description('Maximum delay between operations in seconds.')
param maxDelaySeconds string = '5'

@description('Application Insights connection string for telemetry.')
param appInsightsConnectionString string = ''

@description('Log Analytics workspace resource ID for container diagnostics.')
param logAnalyticsWorkspaceId string = ''

@description('Tags to apply to resources.')
param tags object = {}

// ============================================================================
// Container Group
// ============================================================================

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityResourceId}': {}
    }
  }
  properties: {
    osType: 'Linux'
    restartPolicy: 'Always'
    
    // Use managed identity to pull from ACR
    imageRegistryCredentials: [
      {
        server: acrServer
        identity: userAssignedIdentityResourceId
      }
    ]
    
    // VNet integration
    subnetIds: [
      {
        id: subnetResourceId
      }
    ]
    
    containers: [
      {
        name: 'loadgen'
        properties: {
          image: containerImage
          resources: {
            requests: {
              cpu: 1
              memoryInGB: 1
            }
          }
          environmentVariables: [
            {
              name: 'SQL_SERVER'
              value: sqlServerFqdn
            }
            {
              name: 'DATABASES'
              value: databases
            }
            {
              name: 'MIN_DELAY_SECONDS'
              value: minDelaySeconds
            }
            {
              name: 'MAX_DELAY_SECONDS'
              value: maxDelaySeconds
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: reference(userAssignedIdentityResourceId, '2023-01-31').clientId
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsightsConnectionString
            }
          ]
        }
      }
    ]
    
    // Diagnostics - send container logs to Log Analytics
    diagnostics: !empty(logAnalyticsWorkspaceId) ? {
      logAnalytics: {
        workspaceId: reference(logAnalyticsWorkspaceId, '2022-10-01').customerId
        workspaceKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
        logType: 'ContainerInstanceLogs'
      }
    } : null
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource ID of the container group.')
output resourceId string = containerGroup.id

@description('Name of the container group.')
output name string = containerGroup.name

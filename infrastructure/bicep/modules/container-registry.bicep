// ============================================================================
// container-registry.bicep - Azure Container Registry
// ============================================================================
// Deploys an Azure Container Registry for storing the load generator container.
// ============================================================================

@description('Name of the container registry (must be globally unique, alphanumeric only).')
param name string

@description('Azure region for the registry.')
param location string

@description('SKU for the container registry.')
@allowed(['Basic', 'Standard', 'Premium'])
param sku string = 'Basic'

@description('Enable admin user for simple authentication (dev/test only).')
param adminUserEnabled bool = true

@description('Tags to apply to resources.')
param tags object = {}

// ============================================================================
// Container Registry
// ============================================================================

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: adminUserEnabled
    publicNetworkAccess: 'Enabled' // Required for pushing images; can lock down later
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource ID of the container registry.')
output resourceId string = containerRegistry.id

@description('Login server URL of the container registry.')
output loginServer string = containerRegistry.properties.loginServer

@description('Name of the container registry.')
output name string = containerRegistry.name

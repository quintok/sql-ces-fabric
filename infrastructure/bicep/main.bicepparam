using './main.bicep'

// ============================================================================
// Deployment Parameters — SQL CES Fabric Infrastructure
// ============================================================================
// Update the placeholder values below before deploying.
// ============================================================================

param location = 'australiaeast'

param namePrefix = 'ces'

param vnetAddressPrefix = '10.0.0.0/16'

param privateEndpointSubnetPrefix = '10.0.1.0/24'

param containerSubnetPrefix = '10.0.2.0/24'

// Load Generator — controlled via GitHub Actions workflow inputs
// Set deployLoadGenerator=true in workflow dispatch to deploy ACI
// Image is auto-discovered from ACR by the workflow
param deployLoadGenerator = false
param loadGeneratorImage = ''

// Entra ID administrator — replace with your Entra security group details
param entraAdminLogin = '<entra-admin-group-display-name>'

param entraAdminSid = '<entra-admin-group-object-id>'

// Uncomment and set if different from the deploying tenant
// param entraAdminTenantId = '<tenant-id>'

param tags = {
  Environment: 'Development'
  Project: 'sql-ces-fabric'
  ManagedBy: 'Bicep'
}

// ============================================================================
// Microsoft Fabric Capacity (F2 SKU)
// ============================================================================
// Set deployFabricCapacity=true and provide admin email(s) to provision
// an F2 Fabric capacity for binding workspaces.
// Note: F2 is the smallest SKU (~$262/month when running).
// Naming rules: 3-63 chars, lowercase alphanumeric only, must start with letter.
// ============================================================================
param deployFabricCapacity = false
param fabricAdminMembers = [
  // '<your-email@domain.com>'
]
// GUID without hyphens (hyphens not allowed in Fabric capacity names)
param fabricCapacityName = 'e743ea18139a49389cc04d8af013fa5f'

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

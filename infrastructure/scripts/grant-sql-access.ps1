<#
.SYNOPSIS
    Grant the managed identity SQL access to the tenant databases.

.DESCRIPTION
    After deploying infrastructure, the managed identity needs to be added as a 
    database user with appropriate permissions in each tenant database. This script
    generates the T-SQL commands to run.

.PARAMETER ManagedIdentityName
    Name of the user-assigned managed identity.

.PARAMETER Databases
    Array of database names to configure. Defaults to tenant_db_alpha and tenant_db_beta.

.EXAMPLE
    ./grant-sql-access.ps1 -ManagedIdentityName "ces-uami-sql"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ManagedIdentityName,

    [Parameter(Mandatory = $false)]
    [string[]]$Databases = @("tenant_db_alpha", "tenant_db_beta")
)

Write-Host "SQL Access Grant Script" -ForegroundColor Cyan
Write-Host "=======================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Run the following T-SQL commands against each database." -ForegroundColor Yellow
Write-Host "Connect using an Entra ID admin account." -ForegroundColor Yellow
Write-Host ""

foreach ($db in $Databases) {
    Write-Host "-- Database: $db" -ForegroundColor Green
    Write-Host @"
USE [$db];
GO

-- Create user from managed identity
CREATE USER [$ManagedIdentityName] FROM EXTERNAL PROVIDER;
GO

-- Grant permissions for load generator
ALTER ROLE db_datareader ADD MEMBER [$ManagedIdentityName];
ALTER ROLE db_datawriter ADD MEMBER [$ManagedIdentityName];
ALTER ROLE db_ddladmin ADD MEMBER [$ManagedIdentityName];
GO

"@
}

Write-Host "-- Verification query (run in each database)" -ForegroundColor Gray
Write-Host @"
SELECT dp.name, dp.type_desc, p.permission_name
FROM sys.database_principals dp
LEFT JOIN sys.database_permissions p ON dp.principal_id = p.grantee_principal_id
WHERE dp.name = '$ManagedIdentityName';
"@

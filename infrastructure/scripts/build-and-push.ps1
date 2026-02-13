<#
.SYNOPSIS
    Build and push the load generator container to Azure Container Registry.

.DESCRIPTION
    This script builds the load generator Docker image and pushes it to the ACR
    deployed by the Bicep infrastructure. Run this after the initial infrastructure
    deployment.

.PARAMETER ResourceGroup
    Name of the resource group containing the ACR.

.PARAMETER AcrName
    Name of the Azure Container Registry (without .azurecr.io).

.PARAMETER ImageTag
    Tag for the container image. Defaults to 'latest'.

.EXAMPLE
    ./build-and-push.ps1 -ResourceGroup rg-sql-ces -AcrName cesacr

.EXAMPLE
    ./build-and-push.ps1 -ResourceGroup rg-sql-ces -AcrName cesacr -ImageTag v1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$AcrName,

    [Parameter(Mandatory = $false)]
    [string]$ImageTag = "latest"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$loadgenDir = Join-Path $scriptDir "../../loadgen"

Write-Host "Building load generator container..." -ForegroundColor Cyan

# Get ACR login server
$acrLoginServer = az acr show --name $AcrName --resource-group $ResourceGroup --query loginServer -o tsv
if (-not $acrLoginServer) {
    Write-Error "Failed to get ACR login server. Ensure ACR exists and you have access."
    exit 1
}

$imageName = "$acrLoginServer/loadgen:$ImageTag"

Write-Host "Target image: $imageName" -ForegroundColor Gray

# Login to ACR
Write-Host "Logging into ACR..." -ForegroundColor Cyan
az acr login --name $AcrName

# Build and push using ACR Tasks (no local Docker required)
Write-Host "Building and pushing image via ACR Tasks..." -ForegroundColor Cyan
az acr build `
    --registry $AcrName `
    --resource-group $ResourceGroup `
    --image "loadgen:$ImageTag" `
    --file "$loadgenDir/Dockerfile" `
    $loadgenDir

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to build and push image."
    exit 1
}

Write-Host "`nContainer image pushed successfully!" -ForegroundColor Green
Write-Host "Image: $imageName" -ForegroundColor Green

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Update main.bicepparam with:" -ForegroundColor White
Write-Host "   param deployLoadGenerator = true" -ForegroundColor Gray
Write-Host "   param loadGeneratorImage = '$imageName'" -ForegroundColor Gray
Write-Host "2. Re-run the Bicep deployment to create the container instance." -ForegroundColor White

<#
    Despliegue de Foundry + proyecto + modelos con Az PowerShell.
    Equivalente a scripts/01-deploy.sh.
#>
[CmdletBinding()]
param(
    [string] $Workload    = 'gwlab',
    [ValidateSet('dev','pre','pro')]
    [string] $Environment = 'dev',
    [string] $Location    = 'swedencentral',
    [string] $ResourceGroupName
)

$ErrorActionPreference = 'Stop'

if (-not $ResourceGroupName) {
    $ResourceGroupName = "rg-$Workload-$Environment"
}

Register-AzResourceProvider -ProviderNamespace 'Microsoft.ApiManagement'     | Out-Null
Register-AzResourceProvider -ProviderNamespace 'Microsoft.CognitiveServices' | Out-Null

if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
}

Write-Host '== what-if ==' -ForegroundColor Cyan
Get-AzResourceGroupDeploymentWhatIfResult `
    -ResourceGroupName    $ResourceGroupName `
    -TemplateFile         '.\infra\main.bicep' `
    -TemplateParameterFile '.\infra\main.bicepparam'

if ((Read-Host 'Aplicar el despliegue? [y/N]') -notin @('y','Y')) {
    Write-Host 'Cancelado.'
    return
}

$deployment = New-AzResourceGroupDeployment `
    -Name                  ('foundry-{0}' -f (Get-Date -Format 'yyyyMMddHHmmss')) `
    -ResourceGroupName     $ResourceGroupName `
    -TemplateFile          '.\infra\main.bicep' `
    -TemplateParameterFile '.\infra\main.bicepparam'

$deployment.Outputs | Format-Table -AutoSize

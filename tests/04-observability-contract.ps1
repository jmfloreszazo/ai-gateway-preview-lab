[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$checks = 0

function Build-Template([string] $RelativePath) {
    $json = & az bicep build --file (Join-Path $repositoryRoot $RelativePath) --stdout --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "No compila: $RelativePath" }
    ($json -join "`n") | ConvertFrom-Json -AsHashtable -Depth 100
}

function Get-TemplateResources($Template) {
    if ($Template.resources -is [Collections.IDictionary]) { $Template.resources.Values }
    else { $Template.resources }
}

function Get-SingleResource($Template, [string] $Type) {
    $matches = @(Get-TemplateResources $Template | Where-Object { $_.type -eq $Type })
    if ($matches.Count -ne 1) { throw "Se esperaba un recurso de tipo $Type; encontrados: $($matches.Count)" }
    $matches[0]
}

function Assert-Contract([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
    Write-Host "OK: $Message"
}

$gateway = Build-Template 'infra/gateway-existing.bicep'
$module = Get-SingleResource $gateway 'Microsoft.Resources/deployments'
$monitoring = $module.properties.template
$resources = @(Get-TemplateResources $monitoring)
$insights = Get-SingleResource $monitoring 'Microsoft.Insights/components'
$logs = @($resources | Where-Object { $_.properties.parameters.skuName.value -eq 'PerGB2018' })
$dashboard = @($resources | Where-Object { $_.properties.parameters.name.value -match 'dash-' })

Assert-Contract ($gateway.parameters.enableObservability.defaultValue -eq $true -and
    $module.condition -eq "[parameters('enableObservability')]") 'Observabilidad activada por defecto y opcional.'
$checks++

Assert-Contract ($monitoring.parameters.retentionInDays.defaultValue -eq 30 -and
    $logs.Count -eq 1 -and $logs[0].properties.parameters.dataRetention.value -eq "[parameters('retentionInDays')]") 'Retencion de logs configurable, con 30 dias por defecto.'
$checks++

Assert-Contract ($monitoring.parameters.dailyQuotaGb.defaultValue -eq 1 -and
    $logs[0].properties.parameters.dailyQuotaGb.value -eq "[parameters('dailyQuotaGb')]") 'Limite diario de logs configurable, con 1 GB por defecto.'
$checks++

Assert-Contract ($insights.properties -match "'AzureMonitorWorkspaceIngestionMode',\s*'Enabled'" -and
    $insights.properties -match "'DisableLocalAuth',\s*true\(\)" -and
    $insights.properties -match 'WorkspaceResourceId.+log-analytics-') 'Application Insights vinculado a Log Analytics, con OTLP y sin autenticacion local.'
$checks++

Assert-Contract ($dashboard.Count -eq 1 -and $monitoring.variables.panels.Count -eq 4 -and
    $monitoring.variables.modelSpans -match 'Kind =~ "Server"' -and
    $monitoring.variables.modelSpans -match '/models/') 'Dashboard de cuatro paneles, sin contar spans hijos como peticiones.'
$checks++

$tokens = $monitoring.variables.panels[3].query
Assert-Contract ($tokens -match 'OTelLogs' -and $tokens -match 'usage.prompt_tokens' -and
    $tokens -match 'usage.input_tokens' -and $tokens -match 'isnotnull\(Entrada\) and isnotnull\(Salida\)') 'Tokens desde logs OTLP; uso desconocido no se convierte en cero.'
$checks++

$telemetry = Build-Template 'infra/gateway-telemetry.bicep'
$exporter = Get-SingleResource $telemetry 'Microsoft.ApiManagement/aigateways/workspaces/telemetryExporters'
Assert-Contract ($exporter.properties.kind -eq 'OpenTelemetry' -and
    $exporter.properties.payloadCapture -eq $false -and
    $exporter.properties.telemetry.attributes.Count -eq 0) 'Exportador OTLP sin payloads ni claims adicionales.'
$checks++

$otlp = $exporter.properties.openTelemetry
Assert-Contract ($otlp.credentials.managedIdentity.resource -eq 'https://monitor.azure.com' -and
    $otlp.metricsEndpoint -match 'OTLPMetricsEndpoint' -and
    $otlp.logsEndpoint -match 'OTLPLogsEndpoint' -and
    $otlp.tracesEndpoint -match 'OTLPTracesEndpoint') 'Las tres senales OTLP usan identidad administrada.'
$checks++

$newResources = @(Get-TemplateResources $gateway) + $resources + @(Get-TemplateResources $telemetry)
Assert-Contract (@($newResources | Where-Object { $_.type -like 'Microsoft.CognitiveServices/*' }).Count -eq 0 -and
    @(Get-TemplateResources $telemetry | Where-Object { $_.type -eq 'Microsoft.Authorization/roleAssignments' }).Count -eq 0) 'No se modifica Foundry ni se intenta desplegar RBAC en el grupo administrado de OTLP.'
$checks++

$outputs = @($monitoring.outputs.Keys) + @($telemetry.outputs.Keys)
Assert-Contract (@($outputs | Where-Object { $_ -match '(?i)secret|connectionString|instrumentationKey|sharedKey' }).Count -eq 0) 'Las salidas publicas de observabilidad no incluyen credenciales.'
$checks++

Write-Host "OK: $checks comprobaciones locales de observabilidad. Sin despliegues ni inferencias."
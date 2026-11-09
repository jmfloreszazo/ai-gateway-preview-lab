targetScope = 'resourceGroup'

@description('Prefijo de los recursos de observabilidad del laboratorio.')
@minLength(3)
@maxLength(24)
param namePrefix string

param location string = resourceGroup().location

@description('Retencion de Log Analytics en dias.')
@allowed([30, 31, 60, 90, 120, 180, 270, 365])
param retentionInDays int = 30

@description('Limite diario de ingesta en GB. No es un limite de gasto garantizado.')
@minValue(1)
param dailyQuotaGb int = 1

param tags object = {}

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.9.1' = {
  name: 'log-analytics-${namePrefix}'
  params: {
    name: 'log-${namePrefix}'
    location: location
    skuName: 'PerGB2018'
    dataRetention: retentionInDays
    dailyQuotaGb: dailyQuotaGb
    tags: tags
    enableTelemetry: false
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${namePrefix}'
  location: location
  kind: 'web'
  tags: tags
  properties: union({
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.outputs.resourceId
    DisableLocalAuth: true
  }, {
    AzureMonitorWorkspaceIngestionMode: 'Enabled'
  })
}

var modelSpans = '''
OTelSpans
| where TimeGenerated > ago(24h)
| where Kind =~ "Server" and tostring(Attributes["http.route"]) contains "/models/"
'''

var panels = [
  {
    title: 'Peticiones de modelos'
    query: '${modelSpans}\n| summarize Peticiones = count() by bin(TimeGenerated, 5m)\n| render timechart'
    chart: 'Line'
    xColumn: 'TimeGenerated'
    xType: 'datetime'
    yAxis: [{ name: 'Peticiones', type: 'long' }]
  }
  {
    title: 'Respuestas HTTP de modelos'
    query: '${modelSpans}\n| extend CodigoHTTP = tostring(coalesce(toint(Attributes["http.response.status_code"]), toint(Attributes["http.status_code"]), toint(ResultCode)))\n| summarize Peticiones = count() by CodigoHTTP\n| render columnchart'
    chart: 'Column'
    xColumn: 'CodigoHTTP'
    xType: 'string'
    yAxis: [{ name: 'Peticiones', type: 'long' }]
  }
  {
    title: 'Latencia de modelos en ms'
    query: '${modelSpans}\n| summarize Media = avg(DurationMs), P95 = percentile(DurationMs, 95) by bin(TimeGenerated, 5m)\n| render timechart'
    chart: 'Line'
    xColumn: 'TimeGenerated'
    xType: 'datetime'
    yAxis: [{ name: 'Media', type: 'real' }, { name: 'P95', type: 'real' }]
  }
  {
    title: 'Tokens reportados en logs por modelo'
    query: '''
OTelLogs
| where TimeGenerated > ago(24h)
| extend Modelo = tostring(Attributes["gen_ai.request.model"]),
    Entrada = coalesce(tolong(Attributes["azure.ai_gateway.client.usage.prompt_tokens"]), tolong(Attributes["azure.ai_gateway.client.usage.input_tokens"])),
    Salida = coalesce(tolong(Attributes["azure.ai_gateway.client.usage.completion_tokens"]), tolong(Attributes["azure.ai_gateway.client.usage.output_tokens"]))
| where isnotnull(Entrada) and isnotnull(Salida)
| summarize Entrada = sum(Entrada), Salida = sum(Salida) by Modelo
| render columnchart
'''
    chart: 'Column'
    xColumn: 'Modelo'
    xType: 'string'
    yAxis: [{ name: 'Entrada', type: 'long' }, { name: 'Salida', type: 'long' }]
  }
]

module dashboard 'br/public:avm/res/portal/dashboard:0.1.1' = {
  name: 'dashboard-${namePrefix}'
  params: {
    name: 'dash-${namePrefix}'
    location: location
    tags: union(tags, { 'hidden-title': 'AI Gateway - ${namePrefix}' })
    enableTelemetry: false
    lenses: [
      {
        order: 0
        parts: [for (panel, index) in panels: {
          position: {
            x: (index % 2) * 6
            y: (index / 2) * 4
            colSpan: 6
            rowSpan: 4
          }
          metadata: {
            type: 'Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart'
            inputs: [
              {
                name: 'Scope'
                value: { resourceIds: [logAnalytics.outputs.resourceId] }
                isOptional: true
              }
              {
                name: 'ComponentId'
                value: {
                  SubscriptionId: subscription().subscriptionId
                  ResourceGroup: resourceGroup().name
                  Name: 'log-${namePrefix}'
                  ResourceId: logAnalytics.outputs.resourceId
                }
                isOptional: true
              }
              {
                name: 'Query'
                value: panel.query
                isOptional: true
              }
              {
                name: 'TimeRange'
                value: 'PT24H'
                isOptional: true
              }
              {
                name: 'Version'
                value: '2.0'
                isOptional: true
              }
              {
                name: 'ControlType'
                value: 'AnalyticsChart'
                isOptional: true
              }
              {
                name: 'SpecificChart'
                value: panel.chart
                isOptional: true
              }
              {
                name: 'PartTitle'
                value: panel.title
                isOptional: true
              }
              {
                name: 'Dimensions'
                value: {
                  xAxis: { name: panel.xColumn, type: panel.xType }
                  yAxis: panel.yAxis
                  splitBy: []
                  aggregation: 'Sum'
                }
                isOptional: true
              }
            ]
          }
        }]
      }
    ]
    metadata: {
      model: {
        timeRange: {
          value: { relative: { duration: 24, timeUnit: 1 } }
          type: 'MsPortalFx.Composition.Configuration.ValueTypes.TimeRange'
        }
      }
    }
  }
}

output logAnalyticsResourceId string = logAnalytics.outputs.resourceId
output logAnalyticsCustomerId string = logAnalytics.outputs.logAnalyticsWorkspaceId
output applicationInsightsResourceId string = applicationInsights.id
output applicationInsightsName string = applicationInsights.name
output dashboardResourceId string = dashboard.outputs.resourceId
output dashboardUrl string = 'https://portal.azure.com/#dashboard/arm${dashboard.outputs.resourceId}'

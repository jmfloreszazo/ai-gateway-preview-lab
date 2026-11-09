targetScope = 'resourceGroup'

@description('Gateway existente, con identidad administrada asignada por el sistema.')
param gatewayName string

@description('Application Insights existente, con endpoints OTLP y regla de recogida de datos ya disponibles.')
param applicationInsightsName string

param exporterName string = 'appinsights'

resource gateway 'Microsoft.ApiManagement/aigateways@2026-11-01' existing = {
  name: gatewayName
}

resource workspace 'Microsoft.ApiManagement/aigateways/workspaces@2025-09-01-preview' existing = {
  parent: gateway
  name: 'default'
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

var otlp = any(applicationInsights.properties)

resource exporter 'Microsoft.ApiManagement/aigateways/workspaces/telemetryExporters@2025-09-01-preview' = {
  parent: workspace
  name: exporterName
  properties: {
    kind: 'OpenTelemetry'
    payloadCapture: false
    applicationInsights: {
      resourceId: applicationInsights.id
    }
    openTelemetry: {
      metricsEndpoint: otlp.OTLPMetricsEndpoint
      logsEndpoint: otlp.OTLPLogsEndpoint
      tracesEndpoint: otlp.OTLPTracesEndpoint
      credentials: {
        managedIdentity: {
          resource: 'https://monitor.azure.com'
        }
      }
    }
    telemetry: {
      attributes: []
    }
  }
}

output telemetryExporterId string = exporter.id

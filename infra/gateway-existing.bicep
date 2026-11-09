targetScope = 'resourceGroup'

@description('Nombre globalmente unico del gateway nuevo. No es un servicio APIM clasico.')
@minLength(3)
@maxLength(24)
param gatewayName string

@description('Region del gateway, independiente de la del Foundry existente.')
@allowed(['eastus2', 'swedencentral'])
param location string = 'eastus2'

@description('Cuenta Foundry existente en este grupo de recursos. Nunca se modifica.')
param foundryAccountName string

@description('Nombre exacto de un despliegue existente de Chat Completions.')
param modelDeploymentName string

@description('Nombre del modelo del backend, obtenido de los metadatos del despliegue.')
param modelName string

@description('Version del modelo existente, obtenida de los metadatos del despliegue.')
param modelVersion string

@description('GUID del rol Foundry User, resuelto y revisado en la suscripcion destino.')
@minLength(36)
@maxLength(36)
param foundryRoleDefinitionId string

@description('Identificador ARM del registro del modelo dentro del proveedor.')
@minLength(3)
@maxLength(63)
param modelRegistrationName string = 'chat-backend'

@description('Alias exacto que enviara la aplicacion en el campo model.')
param modelAliasName string = 'chat-principal'

@description('Nombre de la clave temporal; no su valor.')
param runtimeKeyName string = 'example-runtime-key'

@description('Caducidad de la clave. Esta API conserva el dia: por defecto, la siguiente medianoche UTC.')
param runtimeKeyExpiration string = dateTimeAdd(utcNow(), 'P1D', 'yyyy-MM-ddT00:00:00Z')

@description('Crea Application Insights con OTLP, Log Analytics y un dashboard. El exportador se conecta en un segundo paso.')
param enableObservability bool = true

@description('Retencion de Log Analytics en dias.')
@allowed([30, 31, 60, 90, 120, 180, 270, 365])
param logRetentionInDays int = 30

@description('Limite diario de ingesta de logs en GB; no limita el gasto de metricas ni de inferencia.')
@minValue(1)
param logDailyQuotaGb int = 1

@description('Etiquetas del recurso temporal para identificarlo y limpiarlo.')
param tags object = {
  workload: 'gwlab'
  environment: 'lab'
  purpose: 'capturas'
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource backendDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' existing = {
  parent: foundry
  name: modelDeploymentName
}

resource gateway 'Microsoft.ApiManagement/aigateways@2026-11-01' = {
  name: gatewayName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Standard'
  }
  properties: {}
}

resource foundryAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, gateway.id, foundryRoleDefinitionId)
  scope: foundry
  properties: {
    principalId: gateway.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', foundryRoleDefinitionId)
  }
}

resource workspace 'Microsoft.ApiManagement/aigateways/workspaces@2025-09-01-preview' existing = {
  parent: gateway
  name: 'default'
}

resource provider 'Microsoft.ApiManagement/aigateways/workspaces/modelProviders@2025-09-01-preview' = {
  parent: workspace
  name: 'foundry'
  properties: {
    kind: 'Foundry'
    displayName: foundryAccountName
    foundry: {
      endpoint: foundry.properties.endpoint
      resourceIds: [foundry.id]
      authentication: {
        kind: 'ManagedIdentity'
        managedIdentity: {
          resource: 'https://cognitiveservices.azure.com/'
        }
      }
    }
  }
  dependsOn: [foundryAccess]
}

resource registeredModel 'Microsoft.ApiManagement/aigateways/workspaces/modelProviders/models@2025-09-01-preview' = {
  parent: provider
  name: modelRegistrationName
  properties: {
    displayName: modelName
    apiFormat: 'OpenAIChatCompletions'
    deployment: {
      resourceId: backendDeployment.id
      modelName: modelDeploymentName
      modelVersion: modelVersion
    }
    supportedEndpoints: ['/openai/v1/chat/completions']
  }
}

resource modelAlias 'Microsoft.ApiManagement/aigateways/workspaces/aliases@2025-09-01-preview' = {
  parent: workspace
  name: modelAliasName
  properties: {
    aliasName: modelAliasName
    backendModels: [
      {
        resourceId: registeredModel.id
        priority: 0
        weight: 100
      }
    ]
  }
}

resource runtimeKey 'Microsoft.ApiManagement/aigateways/apiKeys@2025-09-01-preview' = {
  parent: gateway
  name: runtimeKeyName
  properties: {
    displayName: 'Laboratorio de capturas'
    expirationDate: runtimeKeyExpiration
  }
}

module observability 'modules/observability.bicep' = if (enableObservability) {
  name: 'observability-${gatewayName}'
  params: {
    namePrefix: gatewayName
    location: location
    retentionInDays: logRetentionInDays
    dailyQuotaGb: logDailyQuotaGb
    tags: tags
  }
}

output gatewayId string = gateway.id
output gatewayPrincipalId string = gateway.identity.principalId
output gatewayBaseUrl string = 'https://${gateway.properties.frontend.defaultHostname}/default/models/openai/v1'
output model string = modelAlias.properties.aliasName
output backendModelName string = modelName
output backendModelVersion string = modelVersion
output runtimeKeyId string = runtimeKey.id
output foundryRoleAssignmentId string = foundryAccess.id
output applicationInsightsResourceId string = observability.?outputs.applicationInsightsResourceId ?? ''
output applicationInsightsName string = observability.?outputs.applicationInsightsName ?? ''
output logAnalyticsResourceId string = observability.?outputs.logAnalyticsResourceId ?? ''
output logAnalyticsCustomerId string = observability.?outputs.logAnalyticsCustomerId ?? ''
output dashboardResourceId string = observability.?outputs.dashboardResourceId ?? ''
output dashboardUrl string = observability.?outputs.dashboardUrl ?? ''

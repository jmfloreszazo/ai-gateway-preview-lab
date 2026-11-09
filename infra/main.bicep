metadata name        = 'Microsoft Foundry para AI Gateway'
metadata description = 'Despliega la cuenta Foundry, el proyecto y N despliegues de modelo, sin autenticacion local.'
metadata owner       = 'AI Gateway Lab'
metadata version     = '1.0.0'

targetScope = 'resourceGroup'

@description('Prefijo corto del workload. Se usa para componer los nombres.')
@minLength(3)
@maxLength(10)
param workload string = 'gwlab'

@allowed([ 'dev', 'pre', 'pro' ])
param environment string = 'dev'

@description('Region del recurso Foundry. No tiene por que coincidir con la del gateway.')
param location string = resourceGroup().location

@description('Modelos a desplegar. Resuelve name/version/format/sku con scripts/00-check-models.sh ANTES de rellenar esto.')
param models array = []

@description('ObjectId del principal que recibira el rol sobre Foundry. Vacio = no se asigna nada.')
param granteePrincipalId string = ''

@description('Role definition id (GUID) del rol a conceder. Resuelvelo en TU tenant; no lo fijes a ciegas.')
param roleDefinitionId string = ''

@description('Deshabilita las claves locales de Foundry. true fuerza al gateway a entrar con identidad administrada.')
param disableLocalAuth bool = true

var suffix      = uniqueString(resourceGroup().id)
var foundryName = 'aif-${workload}-${environment}-${suffix}'

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: foundryName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName:    foundryName
    allowProjectManagement: true
    disableLocalAuth:       disableLocalAuth
    publicNetworkAccess:    'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  name: 'proj-${workload}-${environment}'
  parent: foundry
  location: location
  identity: {
    type: 'SystemAssigned'
  }
}

module modelDeployments 'modules/model.bicep' = [for (model, i) in models: {
  name: 'model-${i}-${model.deploymentName}'
  params: {
    foundryAccountName: foundry.name
    deploymentName:     model.deploymentName
    modelName:          model.modelName
    modelVersion:       model.modelVersion
    modelFormat:        model.modelFormat
    skuName:            model.skuName
    capacity:           model.capacity
  }
  dependsOn: [
    project
  ]
}]

resource grant 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(granteePrincipalId) && !empty(roleDefinitionId)) {
  name: guid(foundry.id, granteePrincipalId, roleDefinitionId)
  scope: foundry
  properties: {
    principalId:      granteePrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}

output foundryAccountName string   = foundry.name
output foundryEndpoint    string   = foundry.properties.endpoint
output projectName        string   = project.name
output localAuthDisabled  bool     = disableLocalAuth
output deployedModels     array    = [for (model, i) in models: model.deploymentName]

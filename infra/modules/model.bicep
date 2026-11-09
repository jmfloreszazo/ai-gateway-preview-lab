metadata description = 'Despliegue de un modelo sobre una cuenta Foundry existente. Todo parametrizado a proposito.'

@description('Nombre de la cuenta Foundry ya desplegada.')
param foundryAccountName string

@description('Nombre del despliegue. Es el que vera AI Gateway al importar.')
param deploymentName string

param modelName    string
param modelVersion string

@description('Formato del modelo: OpenAI, Meta, Mistral AI, xAI, ... Depende del catalogo de tu region.')
param modelFormat string

@allowed([ 'GlobalStandard', 'Standard', 'DataZoneStandard', 'ProvisionedManaged' ])
param skuName string = 'GlobalStandard'

@minValue(1)
param capacity int = 50

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  name: deploymentName
  parent: account
  sku: {
    name:     skuName
    capacity: capacity
  }
  properties: {
    model: {
      name:    modelName
      format:  modelFormat
      version: modelVersion
    }
  }
}

output deploymentName string = deployment.name

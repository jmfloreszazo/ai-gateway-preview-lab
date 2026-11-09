using './gateway-existing.bicep'

param gatewayName = 'aigw-example-lab'
param location = 'eastus2'
param foundryAccountName = 'foundry-example-lab'
param modelDeploymentName = 'chat-backend'
param modelName = 'gpt-6.1-sol'
param modelVersion = '2026-09-29'
param modelRegistrationName = 'gpt-6-1-sol'
param modelAliasName = 'chat-principal'
param foundryRoleDefinitionId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
param runtimeKeyName = 'example-runtime-key'
param enableObservability = true
param logRetentionInDays = 30
param logDailyQuotaGb = 1

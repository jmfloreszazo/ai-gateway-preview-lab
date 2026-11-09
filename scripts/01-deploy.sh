#!/usr/bin/env bash
# Despliegue de Foundry + proyecto + modelos.
# El recurso de AI Gateway NO se crea aqui: ver README (plano de control en preview).
set -euo pipefail

WORKLOAD="${WORKLOAD:-gwlab}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
LOCATION="${LOCATION:-swedencentral}"
RG="${RG:-rg-${WORKLOAD}-${ENVIRONMENT}}"

az provider register --namespace Microsoft.ApiManagement --wait
az provider register --namespace Microsoft.CognitiveServices --wait

az group create --name "$RG" --location "$LOCATION" -o none

echo "== what-if (lee esto antes de decir que si) =="
az deployment group what-if \
  --resource-group "$RG" \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam

read -r -p "Aplicar el despliegue? [y/N] " answer
[[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Cancelado."; exit 0; }

az deployment group create \
  --name "foundry-$(date +%Y%m%d%H%M%S)" \
  --resource-group "$RG" \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam \
  --query "properties.outputs" \
  -o jsonc

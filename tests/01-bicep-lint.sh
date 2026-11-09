#!/usr/bin/env bash
# Prueba 1: la plantilla compila y pasa el linter.
# No prueba que el despliegue funcione. Prueba que no has publicado algo que ni siquiera compila.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== bicep build =="
az bicep build --file infra/main.bicep --stdout > /dev/null
az bicep build --file infra/modules/model.bicep --stdout > /dev/null
az bicep build --file infra/gateway-existing.bicep --stdout > /dev/null
az bicep build --file infra/modules/observability.bicep --stdout > /dev/null
az bicep build --file infra/gateway-telemetry.bicep --stdout > /dev/null

echo "== bicep lint =="
az bicep lint --file infra/main.bicep
az bicep lint --file infra/modules/model.bicep
az bicep lint --file infra/gateway-existing.bicep
az bicep lint --file infra/modules/observability.bicep
az bicep lint --file infra/gateway-telemetry.bicep

echo "== parametros sin resolver =="
if grep -q 'REEMPLAZAR' infra/main.bicepparam; then
  echo "AVISO: main.bicepparam todavia tiene valores REEMPLAZAR."
  echo "Ejecuta scripts/00-check-models.sh y sustituyelos. Esto NO es un fallo del lab."
fi

echo "OK"

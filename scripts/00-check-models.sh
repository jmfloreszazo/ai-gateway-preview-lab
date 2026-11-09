#!/usr/bin/env bash
# Paso 0: averiguar que existe DE VERDAD en tu region/suscripcion antes de escribir Bicep.
# Sin este paso publicas una plantilla que solo funciona en la suscripcion de quien la escribio.
set -euo pipefail

RG="${RG:?Exporta RG con el resource group}"
ACCOUNT="${ACCOUNT:-}"

if [[ -n "$ACCOUNT" ]]; then
  echo "== Modelos disponibles en la cuenta $ACCOUNT =="
  az cognitiveservices account list-models \
    --name "$ACCOUNT" \
    --resource-group "$RG" \
    --query "[].{name:name, format:format, version:version, skus:join(',', skus[].name)}" \
    -o table
else
  echo "(Sin ACCOUNT: salta el listado de modelos. Despliega primero Foundry y vuelve.)"
fi

echo
echo "== Role definition ids candidatos (usa el GUID en main.bicepparam) =="
for ROLE in "Azure AI User" "Cognitive Services User" "Cognitive Services OpenAI User"; do
  az role definition list --name "$ROLE" \
    --query "[].{rol:roleName, id:name}" -o tsv 2>/dev/null || true
done

echo
echo "== Tu objectId (para granteePrincipalId) =="
az ad signed-in-user show --query id -o tsv

echo
echo "== Proveedor de AI Gateway =="
az provider show --namespace Microsoft.ApiManagement --query registrationState -o tsv

#!/usr/bin/env bash
# Prueba minima contra el gateway. Verifica tres cosas, no una:
#   1. que la runtime access key autentica
#   2. que el enrutado por campo "model" llega donde crees
#   3. que la respuesta trae contabilidad de tokens
set -euo pipefail

BASE_URL="${AI_GATEWAY_BASE_URL:?Exporta AI_GATEWAY_BASE_URL (URL base copiada del gateway, sin /chat/completions)}"
API_KEY="${AI_GATEWAY_API_KEY:?Exporta AI_GATEWAY_API_KEY (runtime access key)}"
MODEL="${AI_GATEWAY_MODEL:?Exporta AI_GATEWAY_MODEL (nombre exacto publicado en el gateway)}"
EXPECTED_MODEL="${AI_GATEWAY_EXPECTED_MODEL:-$MODEL}"
MAX_TOKENS="${AI_GATEWAY_MAX_TOKENS:-200}"
BASE_URL="${BASE_URL%/}"
case "${AI_GATEWAY_AUTH_MODE:-bearer}" in
  bearer) AUTH_HEADER="Authorization: Bearer ${API_KEY}" ;;
  api-key) AUTH_HEADER="api-key: ${API_KEY}" ;;
  *) echo 'AI_GATEWAY_AUTH_MODE debe ser bearer o api-key.'; exit 1 ;;
esac

[[ "$MAX_TOKENS" =~ ^[1-9][0-9]*$ ]] || { echo 'AI_GATEWAY_MAX_TOKENS debe ser un entero positivo.'; exit 1; }
payload=$(jq -cn --arg model "$MODEL" --argjson budget "$MAX_TOKENS" \
  '{model: $model, max_completion_tokens: $budget, messages: [{role: "user", content: "Responde solo: gateway-ok."}]}')

response=$(curl -sS --proto '=https' --connect-timeout 10 --max-time 60 -w '\n%{http_code}' "${BASE_URL}/chat/completions" \
  -H "$AUTH_HEADER" \
  -H 'Content-Type: application/json' \
  -d "$payload")

status=$(printf '%s' "$response" | tail -n1)
body=$(printf '%s' "$response" | sed '$d')

case "$status" in
  200) ;;
  401) echo "401: clave de runtime ausente, invalida o inactiva. Revisa AI_GATEWAY_AUTH_MODE."; exit 1 ;;
  404) echo "404: modelo desconocido. El campo model debe coincidir EXACTO con el publicado."; exit 1 ;;
  429) echo "429: limite de tokens o de peticiones. Mira la tarjeta de politica del asset."; exit 1 ;;
  403) echo "403: filtro de IP u otra politica de acceso. Tu IP de salida no esta permitida."; exit 1 ;;
  *)   echo "HTTP $status"; printf '%s\n' "$body"; exit 1 ;;
esac

printf '%s\n' "$body" | jq '{
  modelo_que_respondio: .model,
  contenido:            .choices[0].message.content,
  tokens:               .usage
}'

printf '%s\n' "$body" | jq -e --arg expected "$EXPECTED_MODEL" '
  try (
    .model == $expected and
    (.choices[0].message.content | type == "string" and test("\\S")) and
    ([.usage.prompt_tokens, .usage.completion_tokens, .usage.total_tokens] |
      all(type == "number" and . >= 0 and . == floor)) and
    .usage.total_tokens > 0 and
    .usage.total_tokens == (.usage.prompt_tokens + .usage.completion_tokens)
  ) catch false
' > /dev/null || {
  echo "FALLO: se esperaba $EXPECTED_MODEL, contenido no vacio y contabilidad de tokens consistente."
  exit 1
}

echo 'Smoke test verificado.'

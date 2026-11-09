#!/usr/bin/env bash
# Prueba 2: contrato del gateway contra un entorno real.
#
# Comprueba cuatro fronteras, no una:
#   a) sin credencial          -> 401
#   b) credencial invalida     -> 401
#   c) modelo inexistente      -> 404
#   d) peticion correcta       -> 200, con el modelo servido y la contabilidad de tokens
#
# Requiere AI_GATEWAY_BASE_URL, AI_GATEWAY_API_KEY y AI_GATEWAY_MODEL.
set -euo pipefail

BASE_URL="${AI_GATEWAY_BASE_URL:?Exporta AI_GATEWAY_BASE_URL}"
API_KEY="${AI_GATEWAY_API_KEY:?Exporta AI_GATEWAY_API_KEY}"
MODEL="${AI_GATEWAY_MODEL:?Exporta AI_GATEWAY_MODEL}"
EXPECTED_MODEL="${AI_GATEWAY_EXPECTED_MODEL:-$MODEL}"
MAX_TOKENS="${AI_GATEWAY_MAX_TOKENS:-200}"
BASE_URL="${BASE_URL%/}"
case "${AI_GATEWAY_AUTH_MODE:-bearer}" in
  bearer)
    AUTH_HEADER="Authorization: Bearer ${API_KEY}"
    INVALID_AUTH_HEADER='Authorization: Bearer clave-que-no-existe'
    ;;
  api-key)
    AUTH_HEADER="api-key: ${API_KEY}"
    INVALID_AUTH_HEADER='api-key: clave-que-no-existe'
    ;;
  *) echo 'AI_GATEWAY_AUTH_MODE debe ser bearer o api-key.'; exit 1 ;;
esac

[[ "$MAX_TOKENS" =~ ^[1-9][0-9]*$ ]] || { echo 'AI_GATEWAY_MAX_TOKENS debe ser un entero positivo.'; exit 1; }

fallos=0

payload() {
  jq -cn --arg model "$1" --argjson budget "$MAX_TOKENS" \
    '{model: $model, max_completion_tokens: $budget, messages: [{role: "user", content: "Responde solo: gateway-ok."}]}'
}

check() {
  local titulo="$1" esperado="$2" obtenido="$3"
  if [[ "$esperado" == "$obtenido" ]]; then
    printf '  OK    %-38s %s\n' "$titulo" "$obtenido"
  else
    printf '  FALLO %-38s esperado %s, obtenido %s\n' "$titulo" "$esperado" "$obtenido"
    fallos=$((fallos + 1))
  fi
}

echo "== contrato del gateway =="

status=$(curl -sS --proto '=https' --connect-timeout 10 --max-time 60 -o /dev/null -w '%{http_code}' "${BASE_URL}/chat/completions" \
  -H 'Content-Type: application/json' -d "$(payload "$MODEL")")
check "sin credencial" "401" "$status"

status=$(curl -sS --proto '=https' --connect-timeout 10 --max-time 60 -o /dev/null -w '%{http_code}' "${BASE_URL}/chat/completions" \
  -H "$INVALID_AUTH_HEADER" \
  -H 'Content-Type: application/json' -d "$(payload "$MODEL")")
check "credencial invalida" "401" "$status"

status=$(curl -sS --proto '=https' --connect-timeout 10 --max-time 60 -o /dev/null -w '%{http_code}' "${BASE_URL}/chat/completions" \
  -H "$AUTH_HEADER" \
  -H 'Content-Type: application/json' -d "$(payload "modelo-que-no-existe-$$")")
check "modelo inexistente" "404" "$status"

response=$(curl -sS --proto '=https' --connect-timeout 10 --max-time 60 -w '\n%{http_code}' "${BASE_URL}/chat/completions" \
  -H "$AUTH_HEADER" \
  -H 'Content-Type: application/json' -d "$(payload "$MODEL")")
status=$(printf '%s' "$response" | tail -n1)
body=$(printf '%s' "$response" | sed '$d')
check "peticion valida: HTTP" "200" "$status"

servido=$(printf '%s' "$body" | jq -r '.model // "sin-campo-model"')

check "peticion valida: modelo servido" "$EXPECTED_MODEL" "$servido"

if printf '%s\n' "$body" | jq -e '
  try (
    ([.usage.prompt_tokens, .usage.completion_tokens, .usage.total_tokens] |
      all(type == "number" and . >= 0 and . == floor)) and
    .usage.total_tokens > 0 and
    .usage.total_tokens == (.usage.prompt_tokens + .usage.completion_tokens)
  ) catch false
' > /dev/null; then
  printf '  OK    %-38s %s tokens\n' "contabilidad de tokens" "$(printf '%s' "$body" | jq -r '.usage.total_tokens')"
else
  echo "  FALLO contabilidad de tokens              ausente o inconsistente"
  fallos=$((fallos + 1))
fi

if printf '%s\n' "$body" | jq -e '.choices[0].message.content | strings | test("\\S")' > /dev/null; then
  printf '  OK    %-38s\n' "contenido no vacio"
else
  echo "  FALLO contenido                           respuesta vacia"
  fallos=$((fallos + 1))
fi

echo
if [[ $fallos -eq 0 ]]; then
  echo "Contrato verificado."
  exit 0
fi

echo "$fallos comprobacion(es) fallida(s)."
echo "Si falla 'modelo servido', revisa AI_GATEWAY_EXPECTED_MODEL y la politica de fallback."
exit 1

"""
Cliente equivalente en Python con el SDK de OpenAI.

El recurso actual Microsoft.ApiManagement/aigateways usa Authorization: Bearer.
AI_GATEWAY_AUTH_MODE=api-key conserva el contrato del tier anterior.
"""

from __future__ import annotations

import os
import sys
import time
from urllib.parse import urlsplit

from openai import APIError, APIStatusError, Omit, OpenAI


def required(name: str, hint: str) -> str:
    value = os.environ.get(name)
    if not value or not value.strip():
        raise SystemExit(f"Falta la variable {name} ({hint}).")
    return value


def main() -> int:
    base_url = required(
        "AI_GATEWAY_BASE_URL",
        "URL base copiada del gateway, sin /chat/completions",
    )
    api_key = required("AI_GATEWAY_API_KEY", "runtime access key del gateway")
    model = required("AI_GATEWAY_MODEL", "nombre exacto publicado en el gateway")
    expected_model = os.environ.get("AI_GATEWAY_EXPECTED_MODEL") or model
    auth_mode = os.environ.get("AI_GATEWAY_AUTH_MODE", "bearer")
    if auth_mode not in ("bearer", "api-key"):
        print("AI_GATEWAY_AUTH_MODE debe ser bearer o api-key.", file=sys.stderr)
        return 1

    parts = urlsplit(base_url)
    if parts.scheme != "https" or not parts.hostname or parts.username or parts.password or parts.query or parts.fragment:
        print("AI_GATEWAY_BASE_URL debe ser HTTPS y no incluir credenciales, query ni fragmento.", file=sys.stderr)
        return 1

    try:
        max_tokens = int(os.environ.get("AI_GATEWAY_MAX_TOKENS", "200"))
        if max_tokens <= 0:
            raise ValueError
    except ValueError:
        print("AI_GATEWAY_MAX_TOKENS debe ser un entero positivo.", file=sys.stderr)
        return 1

    headers = {"api-key": api_key} if auth_mode == "api-key" else {}

    started = time.perf_counter()
    try:
        with OpenAI(
            base_url=base_url,
            api_key=api_key if auth_mode == "bearer" else "unused",
            default_headers=headers,
            timeout=60,
            max_retries=0,
        ) as client:
            completion = client.chat.completions.create(
                model=model,
                max_completion_tokens=max_tokens,
                extra_headers={"Authorization": Omit()} if auth_mode == "api-key" else None,
                messages=[
                    {"role": "system", "content": "Eres conciso."},
                    {"role": "user", "content": "Que gobierna un gateway de IA y que no?"},
                ],
            )
    except APIStatusError as error:
        print(f"HTTP {error.status_code}: solicitud rechazada por el gateway.", file=sys.stderr)
        return 1
    except APIError as error:
        print(f"Error de comunicacion con el gateway: {type(error).__name__}.", file=sys.stderr)
        return 1

    elapsed_ms = (time.perf_counter() - started) * 1000

    print(f"modelo solicitado : {model}")
    print(f"modelo que atendio: {completion.model}")
    print(f"latencia          : {elapsed_ms:.0f} ms")
    if completion.usage:
        print(
            f"tokens            : prompt {completion.usage.prompt_tokens} / "
            f"salida {completion.usage.completion_tokens} / "
            f"total {completion.usage.total_tokens}"
        )
    if completion.model != expected_model:
        print()
        print(f"AVISO: se esperaba el modelo {expected_model}.")
        return 2

    usage = completion.usage
    if not usage or usage.prompt_tokens < 0 or usage.completion_tokens < 0 or usage.total_tokens <= 0 or usage.total_tokens != usage.prompt_tokens + usage.completion_tokens:
        print("Contabilidad de tokens ausente o inconsistente.", file=sys.stderr)
        return 3

    content = completion.choices[0].message.content if completion.choices else None
    if not content or not content.strip():
        print("El modelo no ha devuelto contenido. Revisa el presupuesto de tokens de razonamiento.", file=sys.stderr)
        return 4

    print()
    print(content)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

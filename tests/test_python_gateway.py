import copy
import io
import json
import os
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

import httpx
from openai import OpenAI

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src" / "python"))
import call_gateway


class PythonGatewayTests(unittest.TestCase):
    completion = {
        "id": "chatcmpl-local-test",
        "object": "chat.completion",
        "created": 0,
        "model": "modelo-versionado",
        "choices": [{"index": 0, "finish_reason": "stop", "message": {"role": "assistant", "content": "gateway-ok."}}],
        "usage": {"prompt_tokens": 3, "completion_tokens": 2, "total_tokens": 5},
    }

    def invoke(self, body=None, status=200, **environment):
        requests = []
        settings = {
            "AI_GATEWAY_BASE_URL": "https://gateway.invalid/default/models/openai/v1",
            "AI_GATEWAY_API_KEY": "test-runtime-key-not-a-secret",
            "AI_GATEWAY_MODEL": "alias-publicado",
            "AI_GATEWAY_EXPECTED_MODEL": "modelo-versionado",
            "AI_GATEWAY_MAX_TOKENS": "1024",
            **environment,
        }

        def respond(request):
            requests.append(request)
            return httpx.Response(status, json=body if body is not None else self.completion)

        def create_client(**options):
            return OpenAI(**options, http_client=httpx.Client(transport=httpx.MockTransport(respond)))

        output = io.StringIO()
        with patch.dict(os.environ, settings, clear=True), patch.object(call_gateway, "OpenAI", side_effect=create_client), redirect_stdout(output), redirect_stderr(output):
            result = call_gateway.main()
        self.assertNotIn(settings["AI_GATEWAY_API_KEY"], output.getvalue())
        return result, requests

    def test_bearer_alias_y_presupuesto_de_razonamiento(self):
        result, requests = self.invoke()
        self.assertEqual(0, result)
        self.assertEqual(1, len(requests))
        self.assertEqual("Bearer test-runtime-key-not-a-secret", requests[0].headers["Authorization"])
        self.assertNotIn("api-key", requests[0].headers)
        payload = json.loads(requests[0].content)
        self.assertEqual("alias-publicado", payload["model"])
        self.assertEqual(1024, payload["max_completion_tokens"])
        self.assertNotIn("max_tokens", payload)

    def test_legacy_no_envia_authorization(self):
        result, requests = self.invoke(AI_GATEWAY_AUTH_MODE="api-key")
        self.assertEqual(0, result)
        self.assertEqual("test-runtime-key-not-a-secret", requests[0].headers["api-key"])
        self.assertNotIn("Authorization", requests[0].headers)

    def test_fallback_inesperado_falla(self):
        body = copy.deepcopy(self.completion)
        body["model"] = "otro-modelo"
        self.assertEqual(2, self.invoke(body)[0])

    def test_usage_ausente_o_inconsistente_falla(self):
        for usage in (None, {"prompt_tokens": 3, "completion_tokens": 2, "total_tokens": 9}):
            with self.subTest(usage=usage):
                body = copy.deepcopy(self.completion)
                body["usage"] = usage
                self.assertEqual(3, self.invoke(body)[0])

    def test_contenido_vacio_falla(self):
        body = copy.deepcopy(self.completion)
        body["choices"] = []
        self.assertEqual(4, self.invoke(body)[0])

    def test_error_http_falla(self):
        self.assertEqual(1, self.invoke({"error": {"message": "clave invalida"}}, status=401)[0])

    def test_configuracion_insegura_o_invalida_no_envia_peticiones(self):
        for settings in (
            {"AI_GATEWAY_AUTH_MODE": "invalido"},
            {"AI_GATEWAY_BASE_URL": "http://gateway.invalid"},
            {"AI_GATEWAY_MAX_TOKENS": "-1"},
        ):
            with self.subTest(settings=settings):
                result, requests = self.invoke(**settings)
                self.assertEqual(1, result)
                self.assertEqual([], requests)


if __name__ == "__main__":
    unittest.main()
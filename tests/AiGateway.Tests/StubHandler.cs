using System.Net;
using System.Text;

namespace AiGateway.Tests;

/// <summary>Handler de prueba. Guarda la peticion para poder afirmar sobre la credencial enviada.</summary>
internal sealed class StubHandler(HttpStatusCode status, string body) : HttpMessageHandler
{
    public HttpRequestMessage? LastRequest { get; private set; }

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        LastRequest = request;

        var response = new HttpResponseMessage(status)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json")
        };

        return Task.FromResult(response);
    }

    internal static string Completion(string servedModel) =>
        $$"""
        {
          "id": "chatcmpl-test",
          "model": "{{servedModel}}",
          "choices": [
            { "index": 0, "message": { "role": "assistant", "content": "una frase" } }
          ],
          "usage": { "prompt_tokens": 31, "completion_tokens": 12, "total_tokens": 43 }
        }
        """;
}

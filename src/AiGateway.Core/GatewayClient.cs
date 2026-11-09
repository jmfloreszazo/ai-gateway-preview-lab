using System.Diagnostics;
using System.Net.Http.Headers;
using System.Net.Http.Json;

namespace AiGateway.Core;

/// <summary>
/// Cliente minimo contra AI Gateway.
///
/// Lo que demuestra, que no es "que el modelo responde":
///   1. La aplicacion nunca ve una credencial del proveedor. Solo la del gateway.
///   2. El enrutado se decide por coincidencia exacta del campo model.
///   3. La respuesta identifica el modelo que atendio: eso es lo que se verifica.
///   4. Los codigos de error son diagnostico de gobierno.
/// </summary>
public sealed class GatewayClient
{
    private readonly HttpClient _http;
    private readonly GatewayOptions _options;
    private readonly Uri _completionUri;

    public GatewayClient(HttpClient http, GatewayOptions options)
    {
        ArgumentNullException.ThrowIfNull(http);
        ArgumentNullException.ThrowIfNull(options);
        ArgumentException.ThrowIfNullOrWhiteSpace(options.BaseUrl);
        ArgumentException.ThrowIfNullOrWhiteSpace(options.ApiKey);
        ArgumentException.ThrowIfNullOrWhiteSpace(options.Model);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(options.MaxTokens);

        if (options.AuthenticationMode is not ("bearer" or "api-key"))
        {
            throw new ArgumentException("AuthenticationMode debe ser bearer o api-key.", nameof(options));
        }

        if (!Uri.TryCreate(options.BaseUrl, UriKind.Absolute, out var baseUri)
            || baseUri.Scheme != Uri.UriSchemeHttps
            || !string.IsNullOrEmpty(baseUri.UserInfo)
            || !string.IsNullOrEmpty(baseUri.Query)
            || !string.IsNullOrEmpty(baseUri.Fragment))
        {
            throw new ArgumentException("BaseUrl debe ser una URL HTTPS sin credenciales, query ni fragmento.", nameof(options));
        }

        if (http.DefaultRequestHeaders.Authorization is not null || http.DefaultRequestHeaders.Contains("api-key"))
        {
            throw new ArgumentException("HttpClient no debe incluir credenciales por defecto. Configuralas en GatewayOptions.", nameof(http));
        }

        _options = options;
        _http = http;
        _completionUri = new Uri(options.BaseUrl.TrimEnd('/') + "/chat/completions");
    }

    public async Task<GatewayResult> AskAsync(string prompt, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(prompt);

        var request = new ChatRequest(
            Model: _options.Model,
            MaxTokens: _options.MaxTokens,
            Messages:
            [
                new ChatMessage("system", _options.SystemPrompt),
                new ChatMessage("user", prompt)
            ]);

        using var message = new HttpRequestMessage(HttpMethod.Post, _completionUri)
        {
            Content = JsonContent.Create(request, options: GatewayJson.Options)
        };
        if (_options.AuthenticationMode == "bearer")
        {
            message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _options.ApiKey);
        }
        else
        {
            message.Headers.Add("api-key", _options.ApiKey);
        }

        var stopwatch = Stopwatch.StartNew();

        using var response = await _http
            .SendAsync(message, cancellationToken)
            .ConfigureAwait(false);

        stopwatch.Stop();

        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            throw new GatewayException(response.StatusCode, GatewayException.Explain(response.StatusCode), body);
        }

        var completion = await response.Content
            .ReadFromJsonAsync<ChatResponse>(GatewayJson.Options, cancellationToken)
            .ConfigureAwait(false)
            ?? throw new InvalidOperationException("Respuesta vacia o no deserializable.");

        return new GatewayResult(
            RequestedModel: _options.Model,
            ServedModel: completion.Model,
            Content: completion.Choices.Count > 0 ? completion.Choices[0].Message.Content : string.Empty,
            Usage: completion.Usage,
            ElapsedMilliseconds: stopwatch.ElapsedMilliseconds,
            ExpectedServedModel: _options.ExpectedServedModel);
    }
}

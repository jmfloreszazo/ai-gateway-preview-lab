using System.Net;
using System.Text.Json;
using AiGateway.Core;
using Xunit;

namespace AiGateway.Tests;

public sealed class GatewayClientTests
{
    private static GatewayOptions Options(string model = "chat-principal") => new()
    {
        BaseUrl = "https://gw.eastus2-01.ai.gateway.azure.com/default/models/openai/v1",
        ApiKey  = "runtime-key-de-prueba",
        Model   = model
    };

    private static (GatewayClient Client, StubHandler Handler) Build(
        HttpStatusCode status,
        string body,
        GatewayOptions? options = null)
    {
        var handler = new StubHandler(status, body);
        var http = new HttpClient(handler);
        return (new GatewayClient(http, options ?? Options()), handler);
    }

    [Fact]
    public async Task La_credencial_del_gateway_actual_viaja_como_Bearer_y_no_en_api_key()
    {
        var (client, handler) = Build(HttpStatusCode.OK, StubHandler.Completion("chat-principal"));

        await client.AskAsync("hola");

        var request = Assert.IsType<HttpRequestMessage>(handler.LastRequest);
        Assert.False(request.Headers.Contains("api-key"));
        Assert.Equal("Bearer", request.Headers.Authorization?.Scheme);
        Assert.Equal("runtime-key-de-prueba", request.Headers.Authorization?.Parameter);
    }

    [Fact]
    public async Task El_modo_legacy_envia_solo_api_key()
    {
        var options = Options() with { AuthenticationMode = "api-key" };
        var (client, handler) = Build(HttpStatusCode.OK, StubHandler.Completion("chat-principal"), options);

        await client.AskAsync("hola");

        Assert.Equal("runtime-key-de-prueba", Assert.Single(handler.LastRequest!.Headers.GetValues("api-key")));
        Assert.Null(handler.LastRequest.Headers.Authorization);
    }

    [Fact]
    public async Task La_peticion_va_al_endpoint_de_chat_completions()
    {
        var (client, handler) = Build(HttpStatusCode.OK, StubHandler.Completion("chat-principal"));

        await client.AskAsync("hola");

        Assert.Equal(
            "https://gw.eastus2-01.ai.gateway.azure.com/default/models/openai/v1/chat/completions",
            handler.LastRequest!.RequestUri!.ToString());
    }

    [Fact]
    public async Task Una_BaseAddress_previa_no_desvia_la_credencial_a_otro_host()
    {
        var handler = new StubHandler(HttpStatusCode.OK, StubHandler.Completion("chat-principal"));
        using var http = new HttpClient(handler) { BaseAddress = new Uri("https://otro-host.invalid/") };
        var client = new GatewayClient(http, Options());

        await client.AskAsync("hola");

        Assert.Equal("gw.eastus2-01.ai.gateway.azure.com", handler.LastRequest!.RequestUri!.Host);
        Assert.Null(http.DefaultRequestHeaders.Authorization);
        Assert.False(http.DefaultRequestHeaders.Contains("api-key"));
    }

    [Theory]
    [InlineData("http://gateway.invalid/")]
    [InlineData("https://user:password@gateway.invalid/")]
    [InlineData("https://gateway.invalid/?api-key=credential")]
    public void Las_credenciales_no_se_envian_a_urls_inseguras(string baseUrl)
    {
        Assert.Throws<ArgumentException>(() => Build(HttpStatusCode.OK, "{}", Options() with { BaseUrl = baseUrl }));
    }

    [Fact]
    public void Se_rechazan_credenciales_heredadas_de_otro_cliente()
    {
        using var http = new HttpClient();
        http.DefaultRequestHeaders.Add("api-key", "credencial-ajena");

        Assert.Throws<ArgumentException>(() => new GatewayClient(http, Options()));
    }

    [Fact]
    public async Task Cuando_el_modelo_que_atiende_coincide_no_hay_desvio()
    {
        var (client, _) = Build(HttpStatusCode.OK, StubHandler.Completion("chat-principal"));

        var result = await client.AskAsync("hola");

        Assert.False(result.RoutedElsewhere);
        Assert.Equal("chat-principal", result.ServedModel);
    }

    [Fact]
    public async Task Un_fallback_silencioso_del_gateway_se_detecta()
    {
        // El gateway puede responder con otro modelo por alias o por politica de fallback.
        // Esta es la prueba que separa una verificacion real de una demo que parece correcta.
        var (client, _) = Build(HttpStatusCode.OK, StubHandler.Completion("chat-fallback"));

        var result = await client.AskAsync("hola");

        Assert.True(result.RoutedElsewhere);
        Assert.Equal("chat-principal", result.RequestedModel);
        Assert.Equal("chat-fallback", result.ServedModel);
    }

    [Theory]
    [InlineData("gpt-4.1-2025-04-14", false)]
    [InlineData("gpt-4o-2024-08-06", true)]
    public async Task El_modelo_del_backend_se_verifica_sin_confundirlo_con_el_alias(
        string servedModel, bool routedElsewhere)
    {
        var options = Options() with { ExpectedServedModel = "gpt-4.1-2025-04-14" };
        var (client, _) = Build(HttpStatusCode.OK, StubHandler.Completion(servedModel), options);

        var result = await client.AskAsync("hola");

        Assert.Equal("chat-principal", result.RequestedModel);
        Assert.Equal(options.ExpectedServedModel, result.ExpectedServedModel);
        Assert.Equal(routedElsewhere, result.RoutedElsewhere);
    }

    [Fact]
    public async Task La_contabilidad_de_tokens_se_deserializa()
    {
        var (client, _) = Build(HttpStatusCode.OK, StubHandler.Completion("chat-principal"));

        var result = await client.AskAsync("hola");

        var usage = Assert.IsType<Usage>(result.Usage);
        Assert.Equal(31, usage.PromptTokens);
        Assert.Equal(12, usage.CompletionTokens);
        Assert.Equal(43, usage.TotalTokens);
        Assert.True(result.HasValidUsage);
    }

    [Theory]
    [InlineData(0, 0, 0)]
    [InlineData(-1, 2, 1)]
    [InlineData(31, -1, 30)]
    [InlineData(31, 12, 42)]
    public void La_contabilidad_inconsistente_no_supera_la_verificacion(int prompt, int completion, int total)
    {
        var result = new GatewayResult("chat", "chat", "hola", new Usage(prompt, completion, total), 1);

        Assert.False(result.HasValidUsage);
    }

    [Fact]
    public void La_contabilidad_ausente_no_supera_la_verificacion()
    {
        var result = new GatewayResult("chat", "chat", "hola", null, 1);

        Assert.False(result.HasValidUsage);
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized, "Credencial")]
    [InlineData(HttpStatusCode.Forbidden, "Politica de acceso")]
    [InlineData(HttpStatusCode.NotFound, "Enrutado")]
    [InlineData(HttpStatusCode.TooManyRequests, "Limite")]
    public async Task Cada_codigo_de_error_se_traduce_a_su_frontera(HttpStatusCode status, string esperado)
    {
        var (client, _) = Build(status, """{ "error": "..." }""");

        var exception = await Assert.ThrowsAsync<GatewayException>(() => client.AskAsync("hola"));

        Assert.Equal(status, exception.Status);
        Assert.StartsWith(esperado, exception.Cause, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    public void Las_opciones_exigen_un_modelo_explicito(string model)
    {
        var options = Options(model);

        Assert.Throws<ArgumentException>(() => Build(HttpStatusCode.OK, "{}", options));
    }

    [Fact]
    public void El_presupuesto_de_tokens_es_compatible_con_modelos_de_razonamiento()
    {
        var request = new ChatRequest("chat-principal", 1024, [new ChatMessage("user", "hola")]);

        var payload = JsonSerializer.SerializeToElement(request, GatewayJson.Options);

        Assert.Equal(1024, payload.GetProperty("max_completion_tokens").GetInt32());
        Assert.False(payload.TryGetProperty("max_tokens", out _));
    }
}

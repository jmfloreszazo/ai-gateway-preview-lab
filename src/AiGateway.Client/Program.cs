using AiGateway.Core;

// -----------------------------------------------------------------------------
//  Verificacion manual contra AI Gateway.
//
//  No comprueba que el modelo responde: eso ya lo hace el playground del portal.
//  Comprueba que la peticion llega donde crees y a que coste en tokens.
// -----------------------------------------------------------------------------

try
{
    var options = new GatewayOptions
    {
        BaseUrl = Required("AI_GATEWAY_BASE_URL", "URL base copiada del gateway, sin /chat/completions"),
        ApiKey  = Required("AI_GATEWAY_API_KEY", "runtime access key creada en la pagina Keys del portal"),
        AuthenticationMode = Environment.GetEnvironmentVariable("AI_GATEWAY_AUTH_MODE") ?? "bearer",
        Model   = Required("AI_GATEWAY_MODEL", "nombre exacto del modelo publicado en el gateway"),
        ExpectedServedModel = Environment.GetEnvironmentVariable("AI_GATEWAY_EXPECTED_MODEL"),
        MaxTokens = int.Parse(Environment.GetEnvironmentVariable("AI_GATEWAY_MAX_TOKENS") ?? "200")
    };

    var prompt = args.Length > 0
        ? string.Join(' ', args)
        : "Responde en una sola frase: que gobierna un gateway de IA y que no.";

    using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
    var client = new GatewayClient(http, options);

    var result = await client.AskAsync(prompt);

    Console.WriteLine($"modelo solicitado : {result.RequestedModel}");
    Console.WriteLine($"modelo que atendio: {result.ServedModel}");
    Console.WriteLine($"latencia          : {result.ElapsedMilliseconds} ms");

    if (result.Usage is { } usage)
    {
        Console.WriteLine(
            $"tokens            : prompt {usage.PromptTokens} / salida {usage.CompletionTokens} / total {usage.TotalTokens}");
    }
    else
    {
        Console.WriteLine("tokens            : el backend no ha devuelto contabilidad de uso");
    }

    Console.WriteLine();
    Console.WriteLine(result.Content);

    if (result.RoutedElsewhere)
    {
        Console.WriteLine();
        Console.WriteLine($"AVISO: se esperaba el modelo {options.ExpectedServedModel ?? options.Model}.");
        Console.WriteLine("Revisa el modelo esperado y la politica de fallback antes de dar la prueba por buena.");
        return 2;
    }

    if (!result.HasValidUsage)
    {
        Console.Error.WriteLine("Contabilidad de tokens ausente o inconsistente.");
        return 3;
    }

    if (string.IsNullOrWhiteSpace(result.Content))
    {
        Console.Error.WriteLine("El modelo no ha devuelto contenido. Revisa el presupuesto de tokens de razonamiento.");
        return 4;
    }

    return 0;
}
catch (GatewayException ex)
{
    Console.Error.WriteLine(ex.Message);
    if (!string.IsNullOrWhiteSpace(ex.Body))
    {
        Console.Error.WriteLine(ex.Body);
    }
    return 1;
}
catch (InvalidOperationException ex)
{
    Console.Error.WriteLine(ex.Message);
    return 1;
}
catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or ArgumentException or FormatException or OverflowException)
{
    Console.Error.WriteLine(ex.Message);
    return 1;
}

static string Required(string name, string hint)
{
    var value = Environment.GetEnvironmentVariable(name);
    return !string.IsNullOrWhiteSpace(value)
        ? value
        : throw new InvalidOperationException($"Falta la variable {name} ({hint}).");
}

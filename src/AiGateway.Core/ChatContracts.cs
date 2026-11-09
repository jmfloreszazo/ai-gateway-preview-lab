using System.Text.Json;
using System.Text.Json.Serialization;

namespace AiGateway.Core;

/// <summary>Opciones de conexion contra el gateway. No contiene credenciales de proveedor a proposito.</summary>
public sealed record GatewayOptions
{
    /// <summary>URL base de modelos copiada del gateway, sin /chat/completions.</summary>
    public required string BaseUrl { get; init; }

    /// <summary>Runtime access key del gateway. Alcance: todo el gateway.</summary>
    public required string ApiKey { get; init; }

    public string AuthenticationMode { get; init; } = "bearer";

    /// <summary>Nombre exacto del modelo publicado. El enrutado es por coincidencia exacta.</summary>
    public required string Model { get; init; }

    public string? ExpectedServedModel { get; init; }

    public int MaxTokens { get; init; } = 200;

    public string SystemPrompt { get; init; } =
        "Eres conciso. Nunca inventas datos de infraestructura.";
}

public static class GatewayJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };
}

public sealed record ChatMessage(
    [property: JsonPropertyName("role")] string Role,
    [property: JsonPropertyName("content")] string Content);

public sealed record ChatRequest(
    [property: JsonPropertyName("model")] string Model,
    [property: JsonPropertyName("max_completion_tokens")] int MaxTokens,
    [property: JsonPropertyName("messages")] IReadOnlyList<ChatMessage> Messages);

public sealed record Choice(
    [property: JsonPropertyName("index")] int Index,
    [property: JsonPropertyName("message")] ChatMessage Message);

public sealed record Usage(
    [property: JsonPropertyName("prompt_tokens")] int PromptTokens,
    [property: JsonPropertyName("completion_tokens")] int CompletionTokens,
    [property: JsonPropertyName("total_tokens")] int TotalTokens);

public sealed record ChatResponse(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("model")] string Model,
    [property: JsonPropertyName("choices")] IReadOnlyList<Choice> Choices,
    [property: JsonPropertyName("usage")] Usage? Usage);

/// <summary>
/// Resultado de una invocacion. Separa el modelo solicitado del modelo que atendio:
/// con alias o politica de fallback configurados en el gateway pueden no coincidir,
/// y una prueba que no mira esto da por buena una verificacion que no lo es.
/// </summary>
public sealed record GatewayResult(
    string RequestedModel,
    string ServedModel,
    string Content,
    Usage? Usage,
    long ElapsedMilliseconds,
    string? ExpectedServedModel = null)
{
    public bool RoutedElsewhere =>
        !string.Equals(ExpectedServedModel ?? RequestedModel, ServedModel, StringComparison.Ordinal);

    public bool HasValidUsage =>
        Usage is { PromptTokens: >= 0, CompletionTokens: >= 0, TotalTokens: > 0 } usage
        && (long)usage.PromptTokens + usage.CompletionTokens == usage.TotalTokens;
}

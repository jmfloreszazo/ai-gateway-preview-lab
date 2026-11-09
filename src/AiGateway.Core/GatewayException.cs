using System.Net;

namespace AiGateway.Core;

/// <summary>
/// Error devuelto por el gateway, traducido a su causa de gobierno.
/// El codigo HTTP no es ruido: cada uno senala una frontera distinta.
/// </summary>
public sealed class GatewayException(HttpStatusCode status, string cause, string? body = null)
    : Exception($"HTTP {(int)status}: {cause}")
{
    public HttpStatusCode Status { get; } = status;

    public string Cause { get; } = cause;

    public string? Body { get; } = body;

    public static string Explain(HttpStatusCode status) => status switch
    {
        HttpStatusCode.Unauthorized    => "Credencial: la runtime access key falta, es invalida o esta inactiva.",
        HttpStatusCode.Forbidden       => "Politica de acceso: filtro de IP u otro control de red.",
        HttpStatusCode.NotFound        => "Enrutado: modelo desconocido, el campo model debe coincidir exacto.",
        HttpStatusCode.TooManyRequests => "Limite: tokens o peticiones por minuto en la tarjeta de politica.",
        HttpStatusCode.BadGateway      => "Backend: el proveedor detras del gateway no ha respondido.",
        _                              => "Error no clasificado del gateway o del backend."
    };
}

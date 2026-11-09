#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $BaseUrl = $env:AI_GATEWAY_BASE_URL,
    [string] $Model = $env:AI_GATEWAY_MODEL,
    [string] $ExpectedModel = $env:AI_GATEWAY_EXPECTED_MODEL,
    [ValidateSet('bearer', 'api-key')]
    [string] $AuthMode = $(if ($env:AI_GATEWAY_AUTH_MODE) { $env:AI_GATEWAY_AUTH_MODE } else { 'bearer' }),
    [ValidateRange(1, 100000)]
    [int] $MaxTokens = $(if ($env:AI_GATEWAY_MAX_TOKENS) { $env:AI_GATEWAY_MAX_TOKENS } else { 200 }),
    [switch] $Contract,
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($BaseUrl) -or [string]::IsNullOrWhiteSpace($Model)) {
    throw 'Configura AI_GATEWAY_BASE_URL y AI_GATEWAY_MODEL antes de ejecutar la prueba.'
}

$baseUri = $null
if (-not [Uri]::TryCreate($BaseUrl, [UriKind]::Absolute, [ref] $baseUri) -or
    $baseUri.Scheme -ne 'https' -or $baseUri.UserInfo -or $baseUri.Query -or $baseUri.Fragment) {
    throw 'AI_GATEWAY_BASE_URL debe ser una URL HTTPS sin credenciales, query ni fragmento.'
}

$endpoint = $BaseUrl.TrimEnd('/') + '/chat/completions'
if ([string]::IsNullOrWhiteSpace($ExpectedModel)) {
    $ExpectedModel = $Model
}

$apiKey = $env:AI_GATEWAY_API_KEY
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    $secureKey = Read-Host 'Runtime access key del gateway (entrada oculta)' -AsSecureString
    $apiKey = [Net.NetworkCredential]::new('', $secureKey).Password
}
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw 'La runtime access key no puede estar vacia.'
}

$checks = [Collections.Generic.List[object]]::new()

function New-KeyHeaders([string] $Key) {
    if ($AuthMode -eq 'bearer') {
        return @{ Authorization = "Bearer $Key" }
    }
    return @{ 'api-key' = $Key }
}

function Invoke-GatewayRequest([string] $RequestedModel, [hashtable] $Headers) {
    $payload = @{
        model = $RequestedModel
        max_completion_tokens = $MaxTokens
        messages = @(@{ role = 'user'; content = 'Responde solo: gateway-ok.' })
    } | ConvertTo-Json -Depth 4 -Compress

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Method Post -Uri $endpoint -Headers $Headers `
        -ContentType 'application/json' -Body $payload -TimeoutSec 60 `
        -MaximumRedirection 0 -SkipHttpErrorCheck
    $watch.Stop()

    [pscustomobject]@{
        StatusCode = [int] $response.StatusCode
        Content = $response.Content
        ElapsedMilliseconds = $watch.ElapsedMilliseconds
    }
}

function Add-Check([string] $Name, [bool] $Passed, [string] $Detail) {
    $checks.Add([pscustomobject]@{ Name = $Name; Passed = $Passed; Detail = $Detail })
    $label = if ($Passed) { 'OK' } else { 'FALLO' }
    Write-Host ('{0,-6} {1,-35} {2}' -f $label, $Name, $Detail)
}

if ($Contract) {
    $response = Invoke-GatewayRequest $Model @{}
    Add-Check 'sin credencial' ($response.StatusCode -eq 401) "HTTP $($response.StatusCode), esperado 401"

    $response = Invoke-GatewayRequest $Model (New-KeyHeaders 'clave-que-no-existe')
    Add-Check 'credencial invalida' ($response.StatusCode -eq 401) "HTTP $($response.StatusCode), esperado 401"

    $response = Invoke-GatewayRequest ('modelo-inexistente-' + [Guid]::NewGuid().ToString('N')) (New-KeyHeaders $apiKey)
    Add-Check 'modelo inexistente' ($response.StatusCode -eq 404) "HTTP $($response.StatusCode), esperado 404"
}

$response = Invoke-GatewayRequest $Model (New-KeyHeaders $apiKey)
Add-Check 'peticion valida' ($response.StatusCode -eq 200) "HTTP $($response.StatusCode), esperado 200"

$completion = $null
if ($response.StatusCode -eq 200) {
    try {
        $completion = $response.Content | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Add-Check 'respuesta JSON' $false 'La respuesta no es JSON valido.'
    }

    if ($null -ne $completion) {
        Add-Check 'modelo servido' ($completion.model -ceq $ExpectedModel) "recibido $($completion.model), esperado $ExpectedModel"

        $usage = $completion.usage
        $validUsage = $null -ne $usage -and
            ($usage.prompt_tokens -is [long] -or $usage.prompt_tokens -is [int]) -and
            ($usage.completion_tokens -is [long] -or $usage.completion_tokens -is [int]) -and
            ($usage.total_tokens -is [long] -or $usage.total_tokens -is [int]) -and
            $usage.prompt_tokens -ge 0 -and $usage.completion_tokens -ge 0 -and
            $usage.total_tokens -gt 0 -and
            ([decimal] $usage.prompt_tokens + $usage.completion_tokens) -eq $usage.total_tokens
        Add-Check 'contabilidad de tokens' $validUsage ($usage | ConvertTo-Json -Compress)

        $content = $completion.choices[0].message.content
        Add-Check 'contenido' (-not [string]::IsNullOrWhiteSpace($content)) 'Se requiere una respuesta no vacia.'
        Write-Host "modelo solicitado : $Model"
        Write-Host "latencia          : $($response.ElapsedMilliseconds) ms"
        Write-Host $content
    }
    else {
        Add-Check 'respuesta de chat' $false 'La respuesta esta vacia.'
    }
}

if ($OutputPath) {
    $evidencePath = [IO.Path]::GetFullPath($OutputPath)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($evidencePath)) | Out-Null
    [ordered]@{
        TimestampUtc = [DateTimeOffset]::UtcNow.ToString('o')
        Endpoint = $endpoint
        AuthenticationMode = $AuthMode
        RequestedModel = $Model
        ExpectedModel = $ExpectedModel
        ServedModel = $completion.model
        Usage = $completion.usage
        ElapsedMilliseconds = $response.ElapsedMilliseconds
        Checks = $checks.ToArray()
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $evidencePath -Encoding utf8
    Write-Host "Evidencia sin credenciales: $evidencePath"
}

if (@($checks | Where-Object { -not $_.Passed }).Count -gt 0) {
    throw 'La verificacion del gateway ha fallado. Revisa las comprobaciones anteriores.'
}

Write-Host 'Verificacion completada.'
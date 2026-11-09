#requires -Version 7.0
$ErrorActionPreference = 'Stop'

$scriptUnderTest = Join-Path $PSScriptRoot '../scripts/02-smoke-test.ps1'
$originalKey = $env:AI_GATEWAY_API_KEY
$originalMaxTokens = $env:AI_GATEWAY_MAX_TOKENS
$evidencePath = Join-Path ([IO.Path]::GetTempPath()) ('aigateway-local-' + [Guid]::NewGuid().ToString('N') + '.json')
$env:AI_GATEWAY_API_KEY = 'test-runtime-key-not-a-secret'
$testState = @{
    Requests = [Collections.Generic.List[object]]::new()
    Responses = [Collections.Generic.Queue[object]]::new()
}

function Invoke-WebRequest {
    param($Method, $Uri, $Headers, $ContentType, $Body, $TimeoutSec, $MaximumRedirection, [switch] $SkipHttpErrorCheck)

    if ($testState.Responses.Count -eq 0) {
        throw 'El script ha enviado una peticion no prevista.'
    }
    $testState.Requests.Add([pscustomobject]@{
        Uri = $Uri
        Headers = $Headers
        Payload = ($Body | ConvertFrom-Json)
        MaximumRedirection = $MaximumRedirection
    })
    $testState.Responses.Dequeue()
}

function New-Completion([string] $Model = 'modelo-versionado', [object] $Usage = @{ prompt_tokens = 3; completion_tokens = 2; total_tokens = 5 }, [string] $Content = 'gateway-ok.') {
    @{
        model = $Model
        choices = @(@{ message = @{ content = $Content } })
        usage = $Usage
    } | ConvertTo-Json -Depth 5 -Compress
}

function Invoke-Case([string] $Name, [object[]] $Responses, [bool] $ShouldPass, [switch] $Contract, [string] $AuthMode = 'bearer', [string] $OutputPath) {
    $testState.Responses.Clear()
    $testState.Requests.Clear()
    foreach ($response in $Responses) {
        $testState.Responses.Enqueue($response)
    }

    $passed = $true
    $failure = $null
    try {
        & $scriptUnderTest -BaseUrl 'https://gateway.invalid/default/models/openai/v1/' `
            -Model 'alias-publicado' -ExpectedModel 'modelo-versionado' -MaxTokens 1024 `
            -Contract:$Contract -AuthMode $AuthMode -OutputPath $OutputPath
    }
    catch {
        $passed = $false
        $failure = $_.Exception.Message
    }

    if ($passed -ne $ShouldPass) {
        throw "Caso '$Name': resultado inesperado. $failure"
    }
    if ($testState.Responses.Count -ne 0) {
        throw "Caso '$Name': no se han consumido todas las respuestas previstas. $failure"
    }
    Write-Host "PASS local (simulado): $Name"
}

try {
    Invoke-Case 'contrato completo y alias legitimo' @(
        @{ StatusCode = 401; Content = '{}' }
        @{ StatusCode = 401; Content = '{}' }
        @{ StatusCode = 404; Content = '{}' }
        @{ StatusCode = 200; Content = (New-Completion) }
    ) $true -Contract -OutputPath $evidencePath

    if ($testState.Requests.Count -ne 4 -or
        $testState.Requests[0].Headers.ContainsKey('Authorization') -or
        $testState.Requests[1].Headers.Authorization -ne 'Bearer clave-que-no-existe' -or
        $testState.Requests[2].Headers.Authorization -ne "Bearer $env:AI_GATEWAY_API_KEY") {
        throw 'Las fronteras de autenticacion no se han probado correctamente.'
    }
    foreach ($request in $testState.Requests) {
        if ($request.Headers.ContainsKey('api-key') -or
            $request.Payload.max_completion_tokens -ne 1024 -or
            $request.Payload.PSObject.Properties.Name -contains 'max_tokens' -or
            $request.MaximumRedirection -ne 0 -or
            $request.Uri -ne 'https://gateway.invalid/default/models/openai/v1/chat/completions') {
            throw 'La peticion no respeta el contrato de URL, headers y tokens.'
        }
    }

    $evidenceText = Get-Content -LiteralPath $evidencePath -Raw
    $evidence = $evidenceText | ConvertFrom-Json
    if ($evidenceText.Contains($env:AI_GATEWAY_API_KEY) -or
        $evidence.Checks.Count -ne 7 -or $evidence.AuthenticationMode -ne 'bearer') {
        throw 'El archivo de evidencia no respeta el contrato o contiene una credencial.'
    }

    Invoke-Case 'modo legacy explicito' @(@{ StatusCode = 200; Content = (New-Completion) }) $true -AuthMode 'api-key'
    if ($testState.Requests[0].Headers.ContainsKey('Authorization') -or
        $testState.Requests[0].Headers['api-key'] -ne $env:AI_GATEWAY_API_KEY) {
        throw 'El modo legacy no envia exclusivamente api-key.'
    }

    Invoke-Case 'acceso sin credencial no rechazado' @(
        @{ StatusCode = 200; Content = '{}' }
        @{ StatusCode = 401; Content = '{}' }
        @{ StatusCode = 404; Content = '{}' }
        @{ StatusCode = 200; Content = (New-Completion) }
    ) $false -Contract

    Invoke-Case 'fallback inesperado' @(@{ StatusCode = 200; Content = (New-Completion 'otro-modelo') }) $false
    Invoke-Case 'usage ausente' @(@{ StatusCode = 200; Content = (New-Completion -Usage $null) }) $false
    Invoke-Case 'tokens inconsistentes' @(@{ StatusCode = 200; Content = (New-Completion -Usage @{ prompt_tokens = 3; completion_tokens = 2; total_tokens = 9 }) }) $false
    Invoke-Case 'contenido vacio' @(@{ StatusCode = 200; Content = (New-Completion -Content '') }) $false
    Invoke-Case 'error HTTP' @(@{ StatusCode = 502; Content = '{}' }) $false
    Invoke-Case 'JSON invalido' @(@{ StatusCode = 200; Content = 'no-es-json' }) $false

    Write-Host '9 casos locales verificados. No se ha llamado a ningun gateway real.'
}
finally {
    $env:AI_GATEWAY_API_KEY = $originalKey
    $env:AI_GATEWAY_MAX_TOKENS = $originalMaxTokens
    if (Test-Path -LiteralPath $evidencePath) {
        Remove-Item -LiteralPath $evidencePath
    }
}
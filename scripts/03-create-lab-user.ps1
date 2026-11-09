[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)]
    [guid] $TenantId,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$')]
    [string] $UserPrincipalName,

    [string] $DisplayName = 'AI Gateway Lab'
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$headers = @{}
$securePassword = $null
$password = $null
$body = $null
$accessToken = $null

try {
    $currentTenant = az account show --query tenantId --output tsv
    if ($LASTEXITCODE -ne 0 -or $currentTenant.Trim() -ne $TenantId.ToString()) {
        throw 'El tenant activo de Azure CLI no coincide con el autorizado. No se ha creado ningun usuario.'
    }

    $accessToken = az account get-access-token --tenant $TenantId.ToString() `
        --resource-type ms-graph --query accessToken --output tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($accessToken)) {
        throw 'No se ha podido obtener acceso a Microsoft Graph.'
    }

    $headers.Authorization = "Bearer $accessToken"
    $existingUser = $null
    $userUri = 'https://graph.microsoft.com/v1.0/users/{0}?$select=id,userPrincipalName' -f `
        [uri]::EscapeDataString($UserPrincipalName)

    try {
        $existingUser = Invoke-RestMethod -Method Get -Uri $userUri -Headers $headers
    }
    catch {
        if ([int] $_.Exception.Response.StatusCode -ne 404) {
            throw 'No se ha podido comprobar si el usuario existe. No se ha modificado ninguna cuenta.'
        }
    }

    if ($null -ne $existingUser) {
        throw "El usuario $UserPrincipalName ya existe. No se ha cambiado su contrasena ni su configuracion."
    }

    if (-not $PSCmdlet.ShouldProcess($UserPrincipalName, 'Crear usuario nativo de Microsoft Entra')) {
        return
    }

    $password = 'Gw!a1' + [Convert]::ToBase64String(
        [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
    $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
    $body = @{
        accountEnabled = $true
        displayName = $DisplayName
        mailNickname = $UserPrincipalName.Split('@')[0]
        userPrincipalName = $UserPrincipalName
        userType = 'Member'
        passwordProfile = @{
            forceChangePasswordNextSignIn = $true
            password = $password
        }
    } | ConvertTo-Json -Depth 4 -Compress

    try {
        $createdUser = Invoke-RestMethod -Method Post -Uri 'https://graph.microsoft.com/v1.0/users' `
            -Headers $headers -ContentType 'application/json' -Body $body
    }
    catch {
        $status = [int] $_.Exception.Response.StatusCode
        throw "Microsoft Graph ha rechazado la creacion del usuario (HTTP $status). No se muestran cuerpos ni credenciales."
    }

    $global:AiGatewayLabCredential = [pscredential]::new($UserPrincipalName, $securePassword.Copy())

    [pscustomobject]@{
        Id = $createdUser.id
        UserPrincipalName = $createdUser.userPrincipalName
        UserType = $createdUser.userType
        MustChangePassword = $true
        CredentialLocation = 'Variable protegida AiGatewayLabCredential de esta sesion PowerShell'
    }
}
finally {
    $headers.Clear()
    $accessToken = $null
    $password = $null
    $body = $null
    if ($null -ne $securePassword) {
        $securePassword.Dispose()
    }
}
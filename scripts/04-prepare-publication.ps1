[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path $PSScriptRoot -Parent),
    [switch] $CheckOnly,
    [switch] $ImagesReviewed
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$privateConfig = Join-Path $RepositoryRoot '.azure/publication-redactions.local.json'
$identifiers = @()
if (Test-Path $privateConfig) {
    $identifiers = @((Get-Content $privateConfig -Raw | ConvertFrom-Json).identifiers)
}

$privateRun = Join-Path $RepositoryRoot 'evidence/run-summary.json'
if (Test-Path $privateRun) {
    $run = Get-Content $privateRun -Raw | ConvertFrom-Json
    $total = ($run.liveTests | Measure-Object totalTokens -Sum).Sum
    if ($total -ne $run.totalTokens -or $run.liveTests.Count -ne $run.validInferenceCount -or
        @($run.liveTests | Where-Object { -not $_.passed }).Count -gt 0) {
        throw 'Las evidencias originales no son consistentes.'
    }
}

$excludedDirectories = @('bin', 'obj', '__pycache__', '.venv', '.git', '.azure', '.vscode',
    'evidence', 'publication', 'TestResults', '.pytest_cache')

function Get-PublicFiles([string] $Directory) {
    foreach ($item in (Get-ChildItem $Directory -Force)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'No se publican enlaces simbolicos ni junctions.'
        }
        if ($item.PSIsContainer) {
            if ($item.Name -notin $excludedDirectories) { Get-PublicFiles $item.FullName }
        }
        elseif ($item.Name -notlike '*.local.*' -and $item.Name -notlike '.env*' -and
            $item.Name -notlike '*.user') {
            $item
        }
    }
}

$files = @(
    foreach ($name in @('.gitignore', '.gitattributes', '.editorconfig', 'AiGateway.sln',
        'Directory.Build.props', 'LICENSE', 'README.md', 'global.json')) {
        $path = Join-Path $RepositoryRoot $name
        if (Test-Path $path -PathType Leaf) { Get-Item $path }
    }
    foreach ($directory in @('.github', 'infra', 'scripts', 'src', 'tests', 'docs')) {
        $path = Join-Path $RepositoryRoot $directory
        if (Test-Path $path -PathType Container) { Get-PublicFiles $path }
    }
)

$findings = [Collections.Generic.List[string]]::new()
$textExtensions = @('.cs', '.csproj', '.sln', '.props', '.bicep', '.bicepparam', '.ps1', '.sh',
    '.py', '.txt', '.md', '.json', '.yml', '.yaml', '.js')
$secretPatterns = @(
    '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    '\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b',
    '\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b',
    '(?i)AccountKey=[A-Za-z0-9+/=]{32,}',
    '(?i)[?&]sig=[A-Za-z0-9%+/=_-]{24,}',
    '(?i)(?:api[_-]?key|client[_-]?secret|password)\s*[:=]\s*[''"][A-Za-z0-9+/_~.-]{32,}[''"]'
)
$emailPattern = '(?i)\b[A-Z0-9._%+-]+@(?!(?:example\.com|example\.org|example\.net|[A-Z0-9.-]+\.invalid)\b)[A-Z0-9.-]+\.[A-Z]{2,}\b'
$identityPattern = '(?i)/(?:subscriptions|tenants)/(?<id>[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12})'
$imageCount = 0

foreach ($file in $files) {
    $relative = [IO.Path]::GetRelativePath($RepositoryRoot, $file.FullName).Replace('\', '/')
    if ($file.Extension -eq '.png') {
        $imageCount++
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -lt 20 -or [BitConverter]::ToString($bytes, 0, 8) -ne '89-50-4E-47-0D-0A-1A-0A') {
            $findings.Add("$relative [invalid PNG]")
            continue
        }
        $offset = 8
        while ($offset -lt $bytes.Length) {
            if ($offset + 12 -gt $bytes.Length) { throw "PNG truncado: $relative" }
            $length = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, $offset))
            if ($length -lt 0 -or $offset + 12 + $length -gt $bytes.Length) { throw "PNG invalido: $relative" }
            $chunk = [Text.Encoding]::ASCII.GetString($bytes, $offset + 4, 4)
            if ($chunk -in @('tEXt', 'zTXt', 'iTXt', 'eXIf')) { $findings.Add("$relative [image metadata]") }
            $offset += 12 + $length
            if ($chunk -eq 'IEND') { break }
        }
        if ($offset -ne $bytes.Length) { $findings.Add("$relative [trailing image data]") }
        continue
    }

    if ($file.Extension -notin $textExtensions -and $file.Name -notin @('LICENSE', '.gitignore', '.gitattributes', '.editorconfig')) {
        $findings.Add("$relative [unapproved file type]")
        continue
    }
    $text = [Net.WebUtility]::HtmlDecode([uri]::UnescapeDataString([IO.File]::ReadAllText($file.FullName)))
    foreach ($identifier in $identifiers) {
        if ($identifier.allowedFiles -contains $relative) { continue }
        $position = $text.IndexOf($identifier.value, [StringComparison]::OrdinalIgnoreCase)
        if ($position -ge 0) {
            $line = $text.Substring(0, $position).Split("`n").Length
            $findings.Add(('{0}:{1} [{2}]' -f $relative, $line, $identifier.category))
        }
    }
    foreach ($pattern in ($secretPatterns + $emailPattern)) {
        if ([regex]::IsMatch($text, $pattern)) { $findings.Add("$relative [credential or email pattern]") }
    }
    foreach ($match in [regex]::Matches($text, $identityPattern)) {
        $characters = @($match.Groups['id'].Value.Replace('-', '').ToCharArray() | Select-Object -Unique)
        if ($characters.Count -gt 1) { $findings.Add("$relative [resource identity]") }
    }
}

if ($findings.Count -gt 0) {
    throw ("Publicacion bloqueada; no se muestran valores privados:`n" + ($findings -join "`n"))
}

if ($imageCount -gt 0 -and -not $ImagesReviewed -and -not $CheckOnly) {
    throw 'Revisa visualmente las imagenes y usa -ImagesReviewed. El escaner no hace OCR.'
}

[pscustomobject]@{
    FilesChecked = $files.Count
    ImagesChecked = $imageCount
    PrivateIdentifiersChecked = $identifiers.Count
    ImagesVisuallyReviewed = [bool] $ImagesReviewed
    Findings = 0
    ReadOnly = $true
}

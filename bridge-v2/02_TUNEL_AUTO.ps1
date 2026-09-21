$ErrorActionPreference = 'Stop'

$BridgeDir = $PSScriptRoot
$Root = Split-Path $BridgeDir -Parent
$ConfigPath = Join-Path $BridgeDir 'engine-config.json'
$EnvPath = Join-Path $Root '.env.local'
$ReadyPath = Join-Path $BridgeDir 'CURRENT_TUNNEL_URL.txt'

$cloudflared = 'C:\Program Files (x86)\cloudflared\cloudflared.exe'
if (-not (Test-Path $cloudflared)) {
    $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cmd) { $cloudflared = $cmd.Source }
}
if (-not (Test-Path $cloudflared)) {
    Write-Host '[ERRO] cloudflared nao encontrado.' -ForegroundColor Red
    exit 1
}

Remove-Item $ReadyPath -Force -ErrorAction SilentlyContinue

function Read-DotEnv([string]$Path) {
    $out = @{}
    if (-not (Test-Path $Path)) { return $out }
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trim = $line.Trim()
        if (-not $trim -or $trim.StartsWith('#')) { continue }
        $idx = $trim.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $trim.Substring(0, $idx).Trim()
        $value = $trim.Substring($idx + 1)
        $out[$key] = $value
    }
    return $out
}

function Save-EngineConfig([string]$TunnelHost) {
    $cfg = @{}
    if (Test-Path $ConfigPath) {
        $cfg = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
    }

    $frame = @()
    if ($null -ne $cfg.frameAncestors) { $frame = @($cfg.frameAncestors) }
    $frame += 'https://nucel.nuvixgestao.workers.dev'
    $frame += 'http://localhost:3000'
    $frame += 'http://127.0.0.1:3000'
    $frame += 'http://localhost:5159'
    $frame = @($frame | Select-Object -Unique)

    $obj = [ordered]@{
        webPort = 8000
        frameAncestors = $frame
        allowedHosts = @($TunnelHost)
    }

    $json = $obj | ConvertTo-Json -Depth 10
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($ConfigPath, $json + [Environment]::NewLine, $utf8)
}

function Sync-Supabase([string]$Url) {
    $envs = Read-DotEnv $EnvPath
    $supa = $envs['SUPABASE_URL']
    $secret = $envs['SUPABASE_SECRET_KEY']
    if (-not $supa -or -not $secret) {
        throw '.env.local sem SUPABASE_URL/SUPABASE_SECRET_KEY'
    }

    $endpoint = $supa.TrimEnd('/') + '/rest/v1/nucel_bridges?name=eq.PC%20Principal'
    $headers = @{
        apikey = $secret
        Accept = 'application/json'
        Prefer = 'return=representation'
    }
    $body = @{ url = $Url } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Patch -Uri $endpoint -Headers $headers -ContentType 'application/json' -Body $body | Out-Null
}

Write-Host ''
Write-Host '==============================================='
Write-Host '      NuCel TUNEL - AUTO SYNC'
Write-Host '==============================================='
Write-Host ''
Write-Host 'Criando Quick Tunnel e aguardando URL...'
Write-Host ''

$synced = $false
& $cloudflared tunnel --url http://127.0.0.1:8000 2>&1 | ForEach-Object {
    $line = [string]$_
    Write-Host $line

    if (-not $synced -and $line -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
        $url = $Matches[0]
        $hostName = ([Uri]$url).Host

        try {
            Save-EngineConfig $hostName
            Sync-Supabase $url
            [IO.File]::WriteAllText($ReadyPath, $url, (New-Object System.Text.UTF8Encoding($false)))

            Write-Host ''
            Write-Host '===============================================' -ForegroundColor Green
            Write-Host '[OK] TUNEL SINCRONIZADO AUTOMATICAMENTE' -ForegroundColor Green
            Write-Host $url -ForegroundColor Cyan
            Write-Host 'Config do ENGINE + Supabase atualizados.' -ForegroundColor Green
            Write-Host 'NAO FECHE ESTA JANELA.' -ForegroundColor Yellow
            Write-Host '===============================================' -ForegroundColor Green
            Write-Host ''
            $synced = $true
        }
        catch {
            Write-Host ''
            Write-Host ('[ERRO] Falha ao sincronizar tunnel: ' + $_.Exception.Message) -ForegroundColor Red
            Write-Host 'O cloudflared continuara rodando, mas o NuCel nao foi sincronizado.' -ForegroundColor Red
        }
    }
}

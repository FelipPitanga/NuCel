$ErrorActionPreference = 'Stop'

$BridgeDir = $PSScriptRoot
$Root = Split-Path $BridgeDir -Parent
$ConfigPath = Join-Path $BridgeDir 'engine-config.json'
$EnvPath = Join-Path $Root '.env.local'
$ReadyPath = Join-Path $BridgeDir 'CURRENT_TUNNEL_URL.txt'
$StdOutLog = Join-Path $BridgeDir 'cloudflared.stdout.log'
$StdErrLog = Join-Path $BridgeDir 'cloudflared.stderr.log'

$cloudflared = 'C:\Program Files (x86)\cloudflared\cloudflared.exe'
if (-not (Test-Path $cloudflared)) {
    $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cmd) { $cloudflared = $cmd.Source }
}
if (-not (Test-Path $cloudflared)) {
    Write-Host '[ERRO] cloudflared nao encontrado.' -ForegroundColor Red
    exit 1
}

Remove-Item $ReadyPath,$StdOutLog,$StdErrLog -Force -ErrorAction SilentlyContinue

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
    $obj = [ordered]@{
        webPort = 8000
        frameAncestors = @(
            'https://nucel.nuvixgestao.workers.dev',
            'http://localhost:3000',
            'http://127.0.0.1:3000',
            'http://localhost:5159'
        )
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
    if (-not $supa -or -not $secret) { throw '.env.local sem SUPABASE_URL/SUPABASE_SECRET_KEY' }
    $endpoint = $supa.TrimEnd('/') + '/rest/v1/nucel_bridges?name=eq.PC%20Principal'
    $headers = @{
        apikey = $secret
        Authorization = 'Bearer ' + $secret
        Accept = 'application/json'
        Prefer = 'return=representation'
    }
    $body = @{ url = $Url } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Patch -Uri $endpoint -Headers $headers -ContentType 'application/json' -Body $body | Out-Null
}

function Read-AllTunnelLog {
    $parts = @()
    if (Test-Path $StdOutLog) { $parts += Get-Content -Raw -LiteralPath $StdOutLog -ErrorAction SilentlyContinue }
    if (Test-Path $StdErrLog) { $parts += Get-Content -Raw -LiteralPath $StdErrLog -ErrorAction SilentlyContinue }
    return ($parts -join [Environment]::NewLine)
}

Write-Host ''
Write-Host '==============================================='
Write-Host '      NuCel TUNEL - AUTO SYNC'
Write-Host '==============================================='
Write-Host ''
Write-Host 'Criando Quick Tunnel e aguardando URL...'
Write-Host ''

$proc = Start-Process -FilePath $cloudflared -ArgumentList @('tunnel','--url','http://127.0.0.1:8000') -RedirectStandardOutput $StdOutLog -RedirectStandardError $StdErrLog -WindowStyle Hidden -PassThru

$url = $null
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 1
    $log = Read-AllTunnelLog
    if ($log -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
        $url = $Matches[0]
        break
    }
    if ($proc.HasExited) {
        Write-Host '[ERRO] cloudflared encerrou antes de criar o tunnel.' -ForegroundColor Red
        Write-Host ''
        Write-Host $log
        exit 1
    }
    Write-Host -NoNewline '.'
}

if (-not $url) {
    Write-Host ''
    Write-Host '[ERRO] Nao encontrei a URL trycloudflare em 90 segundos.' -ForegroundColor Red
    Write-Host ''
    Write-Host (Read-AllTunnelLog)
    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    exit 1
}

Write-Host ''
Write-Host ('[OK] Quick Tunnel criado: ' + $url) -ForegroundColor Cyan

try {
    $hostName = ([Uri]$url).Host
    Save-EngineConfig $hostName
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($ReadyPath, $url, $utf8)

    Write-Host '[sync] Sincronizando URL do tunnel com o NuCel...' -ForegroundColor DarkGray
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BridgeDir '03_SYNC_BRIDGE.ps1') -Url $url -BridgeName 'PC Principal'
    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao sincronizar a URL do tunnel com o painel NuCel.'
    }
} catch {
    Write-Host ('[ERRO] Falha ao preparar/sincronizar tunnel: ' + $_.Exception.Message) -ForegroundColor Red
    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    exit 1
}

Write-Host ''
Write-Host '===============================================' -ForegroundColor Green
Write-Host '[OK] TUNEL + PAINEL SINCRONIZADOS AUTOMATICAMENTE' -ForegroundColor Green
Write-Host $url -ForegroundColor Cyan
Write-Host 'Config do ENGINE atualizado. O NuCel online fara a sincronizacao.' -ForegroundColor Green
Write-Host 'NAO FECHE ESTA JANELA.' -ForegroundColor Yellow
Write-Host '===============================================' -ForegroundColor Green
Write-Host ''

$shownOut = 0
$shownErr = 0
while (-not $proc.HasExited) {
    Start-Sleep -Seconds 2
    if (Test-Path $StdOutLog) {
        $outLines = @(Get-Content -LiteralPath $StdOutLog -ErrorAction SilentlyContinue)
        if ($outLines.Count -gt $shownOut) {
            $outLines[$shownOut..($outLines.Count - 1)] | ForEach-Object { Write-Host $_ }
            $shownOut = $outLines.Count
        }
    }
    if (Test-Path $StdErrLog) {
        $errLines = @(Get-Content -LiteralPath $StdErrLog -ErrorAction SilentlyContinue)
        if ($errLines.Count -gt $shownErr) {
            $errLines[$shownErr..($errLines.Count - 1)] | ForEach-Object { Write-Host $_ }
            $shownErr = $errLines.Count
        }
    }
}

Write-Host ''
Write-Host ('[ERRO] cloudflared encerrou. ExitCode=' + $proc.ExitCode) -ForegroundColor Red
exit $proc.ExitCode

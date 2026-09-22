$ErrorActionPreference = 'SilentlyContinue'

$BridgeDir = $PSScriptRoot
$Root = Split-Path $BridgeDir -Parent
$ReadyPath = Join-Path $BridgeDir 'CURRENT_TUNNEL_URL.txt'
$StartCmd = Join-Path $BridgeDir '00_NUCEL_100.cmd'
$StopScript = Join-Path $BridgeDir '99_LIMPAR_NUCEL.ps1'
$StartLog = Join-Path $BridgeDir 'NUCEL_START.log'

function Test-Engine {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8000/ws-scrcpy.css' -TimeoutSec 2
        return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500)
    } catch { return $false }
}

function Get-TunnelProcess {
    return @(Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match '(127\.0\.0\.1|localhost):8000' })
}

function Get-TunnelUrl {
    if (-not (Test-Path $ReadyPath)) { return $null }
    $u = (Get-Content -Raw -LiteralPath $ReadyPath -ErrorAction SilentlyContinue).Trim()
    if ($u -match '^https://[a-zA-Z0-9-]+\.trycloudflare\.com$') { return $u }
    return $null
}

function Test-Tunnel {
    $url = Get-TunnelUrl
    if (-not $url) { return $false }
    if ((Get-TunnelProcess).Count -lt 1) { return $false }
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri ($url + '/ws-scrcpy.css') -TimeoutSec 4
        return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500)
    } catch { return $false }
}

function Show-Status {
    $engine = Test-Engine
    $tunnelProc = ((Get-TunnelProcess).Count -gt 0)
    $tunnel = Test-Tunnel
    $url = Get-TunnelUrl

    Write-Host ''
    Write-Host '===============================================' -ForegroundColor DarkGray
    Write-Host '                 NUCEL STATUS'
    Write-Host '===============================================' -ForegroundColor DarkGray
    if ($engine) { Write-Host ' ENGINE     ONLINE' -ForegroundColor Green } else { Write-Host ' ENGINE     OFFLINE' -ForegroundColor Red }
    if ($tunnelProc) { Write-Host ' TUNEL      PROCESSO ATIVO' -ForegroundColor Green } else { Write-Host ' TUNEL      OFFLINE' -ForegroundColor Red }
    if ($tunnel) { Write-Host ' INTERNET   ONLINE' -ForegroundColor Green } else { Write-Host ' INTERNET   OFFLINE/INACESSIVEL' -ForegroundColor Red }
    if ($url) { Write-Host (' URL        ' + $url) -ForegroundColor Cyan }
    Write-Host '===============================================' -ForegroundColor DarkGray

    if ($engine -and $tunnel) {
        Write-Host ' NUCEL ONLINE' -ForegroundColor Green
        Write-Host ''
        return $true
    }

    Write-Host ' NUCEL OFFLINE' -ForegroundColor Red
    Write-Host ''
    return $false
}

$action = if ($args.Count) { [string]$args[0] } else { 'start' }

switch ($action.ToLowerInvariant()) {
    'status' {
        [void](Show-Status)
        exit 0
    }

    'stop' {
        Write-Host ''
        Write-Host '[NuCel] Encerrando...' -ForegroundColor Yellow
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $StopScript | Out-Null
        Remove-Item $ReadyPath -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        Write-Host '[NuCel] OFFLINE' -ForegroundColor Red
        Write-Host ''
        exit 0
    }

    'open' {
        Start-Process 'https://nucel.nuvixgestao.workers.dev/'
        exit 0
    }

    default {
        if ((Test-Engine) -and (Test-Tunnel)) {
            Write-Host ''
            Write-Host '[NuCel] Ja esta ONLINE.' -ForegroundColor Green
            Write-Host 'Use: nucel status' -ForegroundColor DarkGray
            Write-Host ''
            exit 0
        }

        Write-Host ''
        Write-Host '[NuCel] Iniciando em segundo plano...' -ForegroundColor Cyan
        Write-Host '[NuCel] Atualizando e preparando ENGINE + TUNEL.' -ForegroundColor DarkGray

        $cmdArgs = '/d /c ""' + $StartCmd + '" --hidden >> "' + $StartLog + '" 2>&1"'
        Start-Process -FilePath $env:ComSpec -ArgumentList $cmdArgs -WorkingDirectory $BridgeDir -WindowStyle Hidden | Out-Null

        $deadline = (Get-Date).AddMinutes(4)
        $dots = 0
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
            $dots++
            if ((Test-Engine) -and (Test-Tunnel)) {
                Write-Host ''
                Write-Host ''
                Write-Host '===============================================' -ForegroundColor Green
                Write-Host '              NUCEL ONLINE' -ForegroundColor Green
                Write-Host '===============================================' -ForegroundColor Green
                $url = Get-TunnelUrl
                if ($url) { Write-Host ('Tunnel: ' + $url) -ForegroundColor DarkGray }
                Write-Host 'Painel: https://nucel.nuvixgestao.workers.dev/' -ForegroundColor Cyan
                Write-Host ''
                exit 0
            }
            Write-Host -NoNewline '.'
        }

        Write-Host ''
        Write-Host ''
        Write-Host '[NuCel] Nao ficou ONLINE dentro do tempo esperado.' -ForegroundColor Red
        Write-Host ('Log: ' + $StartLog) -ForegroundColor Yellow
        Write-Host 'Rode: nucel status' -ForegroundColor DarkGray
        exit 1
    }
}

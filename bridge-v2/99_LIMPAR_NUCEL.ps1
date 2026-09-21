$ErrorActionPreference = 'SilentlyContinue'

Write-Host '[cleanup] Encerrando listeners antigos nas portas 8000/8001...'

foreach ($port in @(8000, 8001)) {
    $listeners = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    foreach ($listener in $listeners) {
        $pidToStop = $listener.OwningProcess
        if ($pidToStop -and $pidToStop -ne $PID) {
            Write-Host "[cleanup] Finalizando PID $pidToStop da porta $port"
            Stop-Process -Id $pidToStop -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host '[cleanup] Encerrando Quick Tunnels antigos do NuCel...'
Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
        $_.CommandLine -and (
            $_.CommandLine -match '127\.0\.0\.1:8000' -or
            $_.CommandLine -match 'localhost:8000'
        )
    } |
    ForEach-Object {
        Write-Host "[cleanup] Finalizando cloudflared PID $($_.ProcessId)"
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

Start-Sleep -Seconds 2

$still = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
if ($still) {
    Write-Host '[ERRO] A porta 8000 continua ocupada:' -ForegroundColor Red
    $still | Format-Table LocalAddress,LocalPort,OwningProcess -AutoSize
    exit 1
}

Write-Host '[OK] Ambiente local limpo.' -ForegroundColor Green
exit 0

$ErrorActionPreference = 'Stop'

$BridgeDir = $PSScriptRoot
$StartCmd = Join-Path $BridgeDir '00_NUCEL_100.cmd'
$LogPath = Join-Path $BridgeDir 'NUCEL_START.log'

$ws = New-Object -ComObject WScript.Shell
$null = $ws.Popup('NuCel iniciando em segundo plano. Aguarde alguns instantes...', 3, 'NuCel', 64)

try {
    ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] Iniciando NuCel') | Set-Content -LiteralPath $LogPath -Encoding UTF8

    $args = '/d /c ""' + $StartCmd + '" --hidden >> "' + $LogPath + '" 2>&1"'
    $proc = Start-Process -FilePath $env:ComSpec -ArgumentList $args -WorkingDirectory $BridgeDir -WindowStyle Hidden -Wait -PassThru

    if ($proc.ExitCode -ne 0) {
        $null = $ws.Popup("O NuCel nao conseguiu iniciar. O diagnostico foi salvo em:" + [Environment]::NewLine + $LogPath, 12, 'NuCel - erro ao iniciar', 16)
        exit $proc.ExitCode
    }

    $null = $ws.Popup('NuCel pronto.', 2, 'NuCel', 64)
    exit 0
}
catch {
    ('ERRO: ' + $_.Exception.Message) | Add-Content -LiteralPath $LogPath -Encoding UTF8
    $null = $ws.Popup("Falha ao iniciar o NuCel:" + [Environment]::NewLine + $_.Exception.Message + [Environment]::NewLine + [Environment]::NewLine + "Log:" + [Environment]::NewLine + $LogPath, 15, 'NuCel - erro', 16)
    exit 1
}

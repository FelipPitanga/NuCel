@echo off
setlocal EnableExtensions
title NuCel Bridge v2 - Configurar Embed

set "CONFIG=%PROGRAMDATA%\WsScrcpyWeb\config.json"

echo.
echo ===============================================
echo   NuCel Bridge v2 - liberar incorporacao
echo ===============================================
echo.

if not exist "%CONFIG%" (
  echo [ERRO] Configuracao do ws-scrcpy-web nao encontrada em:
  echo %CONFIG%
  echo.
  echo Inicie primeiro o 01_INICIAR_LOCAL.cmd e espere o servidor abrir.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%CONFIG%';" ^
  "$j=Get-Content -Raw -LiteralPath $p | ConvertFrom-Json;" ^
  "$wanted=@('http://localhost:5159','https://nucel.nuvixgestao.workers.dev');" ^
  "$current=@(); if($null -ne $j.frameAncestors){$current=@($j.frameAncestors)};" ^
  "$all=@($current + $wanted | Select-Object -Unique);" ^
  "$j | Add-Member -NotePropertyName frameAncestors -NotePropertyValue $all -Force;" ^
  "$j | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $p -Encoding UTF8"

if errorlevel 1 (
  echo [ERRO] Nao foi possivel atualizar frameAncestors.
  pause
  exit /b 1
)

echo [OK] Liberados para incorporar o player:
echo   http://localhost:5159
echo   https://nucel.nuvixgestao.workers.dev
echo.
echo IMPORTANTE: reinicie o NuCel Bridge v2 ENGINE para aplicar.
pause

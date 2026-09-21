@echo off
setlocal EnableExtensions
title NuCel Bridge v2 - Configurar Embed

set "DATA_DIR=%PROGRAMDATA%\WsScrcpyWeb"
set "CONFIG=%DATA_DIR%\config.json"

echo.
echo ===============================================
echo   NuCel Bridge v2 - liberar incorporacao
echo ===============================================
echo.

if not exist "%DATA_DIR%" (
  echo Criando pasta de configuracao:
  echo %DATA_DIR%
  mkdir "%DATA_DIR%"
  if errorlevel 1 (
    echo.
    echo [ERRO] Nao foi possivel criar a pasta.
    echo Tente executar este arquivo como Administrador.
    pause
    exit /b 1
  )
)

if not exist "%CONFIG%" (
  echo config.json ainda nao existe. Criando configuracao minima...
  >"%CONFIG%" echo {"webPort":8000,"frameAncestors":[]}
  if errorlevel 1 (
    echo.
    echo [ERRO] Nao foi possivel criar:
    echo %CONFIG%
    echo Tente executar este arquivo como Administrador.
    pause
    exit /b 1
  )
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%CONFIG%';" ^
  "$raw=Get-Content -Raw -LiteralPath $p;" ^
  "try {$j=$raw | ConvertFrom-Json} catch {$j=[pscustomobject]@{webPort=8000}};" ^
  "$wanted=@('http://localhost:5159','https://nucel.nuvixgestao.workers.dev');" ^
  "$current=@(); if($null -ne $j.frameAncestors){$current=@($j.frameAncestors)};" ^
  "$all=@($current + $wanted | Select-Object -Unique);" ^
  "$j | Add-Member -NotePropertyName frameAncestors -NotePropertyValue $all -Force;" ^
  "$json=$j | ConvertTo-Json -Depth 20;" ^
  "$utf8=New-Object System.Text.UTF8Encoding($false);" ^
  "[System.IO.File]::WriteAllText($p,$json,$utf8)"

if errorlevel 1 (
  echo.
  echo [ERRO] Nao foi possivel atualizar frameAncestors.
  pause
  exit /b 1
)

echo.
echo [OK] Configuracao atualizada:
echo %CONFIG%
echo.
echo Liberados para incorporar o player:
echo   http://localhost:5159
echo   https://nucel.nuvixgestao.workers.dev
echo.
echo AGORA:
echo 1. Feche somente a janela "NuCel Bridge v2 ENGINE"
echo 2. Rode 01_INICIAR_LOCAL.cmd novamente
echo 3. Mantenha o Tunnel aberto
echo 4. Rode 05_TESTAR_EMBED.cmd
echo.
pause

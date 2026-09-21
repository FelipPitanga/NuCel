@echo off
setlocal EnableExtensions
title NuCel - Gerenciador
cd /d "%~dp0"

set "ROOT=%CD%"
set "ENGINE=%ROOT%\.engine\ws-scrcpy-web"
set "CONFIG=%ROOT%\engine-config.json"
set "CLOUDFLARED=C:\Program Files (x86)\cloudflared\cloudflared.exe"

echo.
echo ===============================================
echo       NuCel Bridge v2 - 3 TELAS
echo ===============================================
echo.

if not exist "%ENGINE%\package.json" (
  echo [ERRO] Motor nao encontrado em:
  echo %ENGINE%
  echo Rode 01_INICIAR_LOCAL.cmd uma vez para instalar o motor.
  pause
  exit /b 1
)

if not exist "%CONFIG%" (
  echo [ERRO] Configuracao nao encontrada:
  echo %CONFIG%
  pause
  exit /b 1
)

echo Abrindo exatamente 3 janelas:
echo   [1] NUCEL ENGINE
echo   [2] NUCEL TUNEL
echo   [3] NUCEL DIRECT LAB
echo.

REM Remove qualquer patch antigo de coordenadas antes do build.
git -C "%ENGINE%" checkout -- src/app/interactionHandler/InteractionHandler.ts >nul 2>nul

start "1 - NUCEL ENGINE" cmd /k "title 1 - NUCEL ENGINE && cd /d ""%ROOT%"" && 01_ENGINE_DIRETO.cmd"

timeout /t 2 /nobreak >nul

if exist "%CLOUDFLARED%" (
  start "2 - NUCEL TUNEL" cmd /k "title 2 - NUCEL TUNEL && ""%CLOUDFLARED%"" tunnel --url http://127.0.0.1:8000"
) else (
  start "2 - NUCEL TUNEL" cmd /k "title 2 - NUCEL TUNEL && cloudflared tunnel --url http://127.0.0.1:8000"
)

start "3 - NUCEL DIRECT LAB" cmd /k "title 3 - NUCEL DIRECT LAB && cd /d ""%ROOT%"" && 03_DIRECT_LAB.cmd"

echo.
echo [OK] As 3 janelas foram abertas.
echo Nao abra nenhum outro CMD.
echo.
timeout /t 3 /nobreak >nul
exit

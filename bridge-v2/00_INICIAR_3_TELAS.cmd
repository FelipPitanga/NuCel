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
echo       NuCel - OPERACAO LOCAL
echo ===============================================
echo.

if not exist "%ENGINE%\package.json" (
  echo [ERRO] Motor nao encontrado.
  echo Rode 01_INICIAR_LOCAL.cmd uma vez.
  pause
  exit /b 1
)

echo Abrindo exatamente 3 janelas:
echo   [1] NUCEL ENGINE
echo   [2] NUCEL DASHBOARD
echo   [3] NUCEL TUNEL
echo.

git -C "%ENGINE%" checkout -- src/app/interactionHandler/InteractionHandler.ts >nul 2>nul

start "1 - NUCEL ENGINE" cmd /k "title 1 - NUCEL ENGINE && cd /d ""%ROOT%"" && 01_ENGINE_DIRETO.cmd"

timeout /t 2 /nobreak >nul

start "2 - NUCEL DASHBOARD" cmd /k "title 2 - NUCEL DASHBOARD && cd /d ""%ROOT%"" && 03_NUCEL_DASHBOARD.cmd"

timeout /t 2 /nobreak >nul

if exist "%CLOUDFLARED%" (
  start "3 - NUCEL TUNEL" "%ComSpec%" /k ""%CLOUDFLARED%" tunnel --url http://127.0.0.1:8000"
) else (
  start "3 - NUCEL TUNEL" "%ComSpec%" /k "cloudflared tunnel --url http://127.0.0.1:8000"
)

echo.
echo [OK] Tudo iniciado.
echo.
echo Use apenas:
echo   http://localhost:3000
echo.
echo O Direct Lab nao e mais necessario.
timeout /t 4 /nobreak >nul
exit

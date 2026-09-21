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
echo   [1] ENGINE
echo   [2] TUNEL
echo   [3] EMBED LAB
echo.

git -C "%ENGINE%" checkout -- src/app/interactionHandler/InteractionHandler.ts >nul 2>nul

start "1 - NUCEL ENGINE" cmd /k "title 1 - NUCEL ENGINE && cd /d ""%ROOT%"" && 01_ENGINE_DIRETO.cmd" && npm start"

timeout /t 3 /nobreak >nul

if exist "%CLOUDFLARED%" (
  start "2 - NUCEL TUNEL" cmd /k "title 2 - NUCEL TUNEL && ""%CLOUDFLARED%"" tunnel --url http://127.0.0.1:8000"
) else (
  start "2 - NUCEL TUNEL" cmd /k "title 2 - NUCEL TUNEL && cloudflared tunnel --url http://127.0.0.1:8000"
)

start "3 - NUCEL EMBED LAB" cmd /k "title 3 - NUCEL EMBED LAB && cd /d ""%ROOT%"" && (py -3 -m http.server 5159 --bind 127.0.0.1 || python -m http.server 5159 --bind 127.0.0.1)"

echo.
echo [OK] Pronto. Nao abra nenhum outro CMD.
echo.
echo Depois que a janela ENGINE terminar de iniciar, abra:
echo http://localhost:5159/embed-lab.html
echo.
timeout /t 4 /nobreak >nul
exit

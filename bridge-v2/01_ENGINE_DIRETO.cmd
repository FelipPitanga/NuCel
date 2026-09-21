@echo off
setlocal EnableExtensions
title 1 - NUCEL ENGINE
cd /d "%~dp0"

set "ROOT=%CD%"
set "ENGINE=%ROOT%\.engine\ws-scrcpy-web"
set "CONFIG=%ROOT%\engine-config.json"
set "LAB=%ROOT%\nucel-direct.html"

if not exist "%ENGINE%\package.json" (
  echo [ERRO] Motor nao encontrado. Rode 01_INICIAR_LOCAL.cmd uma vez.
  pause
  exit /b 1
)

if exist "C:\Program Files\nodejs\node.exe" set "PATH=C:\Program Files\nodejs;%PATH%"

set "WS_SCRCPY_CONFIG=%CONFIG%"
cd /d "%ENGINE%"

echo.
echo ===============================================
echo       NuCel ENGINE - DIRECT API
echo ===============================================
echo.
echo [1/3] Preparando dependencias...
call npm run stage-seed
if errorlevel 1 goto :fail

echo [2/3] Preparando HTTPS do Cloudflare Tunnel...
node "%ROOT%\patch-engine-cloudflare-https.mjs"
if errorlevel 1 goto :fail

echo [2/3] Compilando motor...
call npm run build
if errorlevel 1 goto :fail

echo [3/3] Instalando NuCel Direct Lab...
copy /Y "%LAB%" "%ENGINE%\dist\public\nucel-direct.html" >nul
if errorlevel 1 goto :fail

echo.
echo [OK] Motor pronto.
echo Abra: http://localhost:8000/nucel-direct.html
echo.
node scripts/dev-supervisor.mjs
exit /b %errorlevel%

:fail
echo.
echo [ERRO] Falha ao iniciar o NuCel Direct Engine.
pause
exit /b 1

@echo off
setlocal EnableExtensions
title NuCel Bridge v2 - LAB LOCAL
cd /d "%~dp0"

set "ENGINE_DIR=%CD%\.engine\ws-scrcpy-web"
set "ENGINE_REPO=https://github.com/bilbospocketses/ws-scrcpy-web.git"
set "ENGINE_COMMIT=8fd486cfaf9ab69dc6b97237053979bc1f141b05"

echo.
echo ===============================================
echo   NuCel Bridge v2 - laboratorio LOCAL
echo ===============================================
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [ERRO] Git nao encontrado.
  echo Instale o Git e abra este arquivo novamente.
  pause
  exit /b 1
)

where node >nul 2>nul
if errorlevel 1 (
  echo [ERRO] Node.js nao encontrado.
  echo O motor exige Node.js 24 ou superior.
  echo Rode: winget install OpenJS.NodeJS.LTS
  pause
  exit /b 1
)

for /f "tokens=1 delims=." %%V in ('node -p "process.versions.node"') do set "NODE_MAJOR=%%V"
if %NODE_MAJOR% LSS 24 (
  echo [ERRO] Node.js %NODE_MAJOR% detectado. O motor exige Node.js 24 ou superior.
  echo Atualize com: winget upgrade OpenJS.NodeJS.LTS
  pause
  exit /b 1
)

if not exist "%ENGINE_DIR%\.git" (
  echo [1/4] Baixando motor scrcpy-web...
  if not exist "%CD%\.engine" mkdir "%CD%\.engine"
  git clone "%ENGINE_REPO%" "%ENGINE_DIR%"
  if errorlevel 1 goto :fail
)

echo [2/4] Fixando versao validada...
cd /d "%ENGINE_DIR%"
git fetch origin
if errorlevel 1 goto :fail
git checkout --detach %ENGINE_COMMIT%
if errorlevel 1 goto :fail

echo [3/4] Instalando dependencias...
call npm install
if errorlevel 1 goto :fail

echo [4/4] Iniciando em http://127.0.0.1:8000
echo.
echo IMPORTANTE:
echo - Feche o Agent Python antigo durante este teste.
echo - Teste primeiro LOCAL, sem Cloudflare.
echo - No navegador selecione o serial 0059410259.
echo.
start "" "http://127.0.0.1:8000"
call npm start
exit /b %errorlevel%

:fail
echo.
echo [ERRO] Falha ao preparar o laboratorio Bridge v2.
pause
exit /b 1

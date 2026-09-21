@echo off
setlocal EnableExtensions
title NuCel - Deploy Cloudflare Workers

set "ROOT=%~dp0.."
cd /d "%ROOT%"

if exist "C:\Program Files\nodejs\node.exe" set "PATH=C:\Program Files\nodejs;%PATH%"

echo.
echo ===============================================
echo      NuCel - DEPLOY CLOUDFLARE WORKERS
echo ===============================================
echo.
echo Branch esperada: nucel-bridge-v2
echo Destino: https://nucel.nuvixgestao.workers.dev
echo.

for /f "delims=" %%B in ('git branch --show-current') do set "BRANCH=%%B"
if /I not "%BRANCH%"=="nucel-bridge-v2" (
  echo [ERRO] Voce esta na branch: %BRANCH%
  echo Rode: git switch nucel-bridge-v2
  pause
  exit /b 1
)

echo [1/3] Conferindo dependencias...
if not exist "node_modules" (
  call npm install
  if errorlevel 1 goto :fail
)

echo [2/3] Build Cloudflare...
call npx opennextjs-cloudflare build
if errorlevel 1 goto :fail

echo [3/3] Publicando Worker...
call npx wrangler deploy
if errorlevel 1 goto :fail

echo.
echo ===============================================
echo [OK] NUCEL PUBLICADO
echo ===============================================
echo.
echo Abrindo:
echo https://nucel.nuvixgestao.workers.dev
start "" "https://nucel.nuvixgestao.workers.dev"
echo.
pause
exit /b 0

:fail
echo.
echo ===============================================
echo [ERRO] Deploy interrompido.
echo ===============================================
echo.
echo Mande uma foto das ultimas linhas desta janela.
pause
exit /b 1

@echo off
setlocal EnableExtensions EnableDelayedExpansion
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
  pause
  exit /b 1
)

where node >nul 2>nul
if errorlevel 1 (
  echo [ERRO] Node.js nao encontrado.
  echo O motor exige Node.js 24 ou superior.
  pause
  exit /b 1
)

for /f "tokens=1 delims=." %%V in ('node -p "process.versions.node"') do set "NODE_MAJOR=%%V"
if %NODE_MAJOR% LSS 24 (
  echo [ERRO] Node.js %NODE_MAJOR% detectado. O motor exige Node.js 24 ou superior.
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

if not exist "%ENGINE_DIR%\node_modules" (
  echo [3/4] Instalando dependencias...
  call npm install
  if errorlevel 1 goto :fail
) else (
  echo [3/4] Dependencias ja instaladas.
)

echo [4/4] Iniciando motor...
echo.
echo IMPORTANTE:
echo - Feche o Agent Python antigo durante este teste.
echo - Teste primeiro LOCAL, sem Cloudflare.
echo - Aguarde esta janela avisar quando a porta 8000 estiver pronta.
echo.

start "NuCel Bridge v2 ENGINE" cmd /k "cd /d ""%ENGINE_DIR%"" && npm start"

echo Aguardando http://127.0.0.1:8000 ficar disponivel...
set /a COUNT=0
:wait_port
set /a COUNT+=1
curl.exe -s -o nul --max-time 2 http://127.0.0.1:8000 >nul 2>nul
if not errorlevel 1 goto :ready
if !COUNT! GEQ 180 goto :timeout
<nul set /p "=."
timeout /t 2 /nobreak >nul
goto :wait_port

:ready
echo.
echo.
echo [OK] Bridge v2 LOCAL pronto.
echo Abrindo http://127.0.0.1:8000
start "" "http://127.0.0.1:8000"
echo.
echo Deixe a janela "NuCel Bridge v2 ENGINE" aberta durante o teste.
pause
exit /b 0

:timeout
echo.
echo.
echo [ERRO] O servidor nao respondeu na porta 8000 apos 6 minutos.
echo Verifique a janela "NuCel Bridge v2 ENGINE" e mande as ultimas linhas do erro.
pause
exit /b 1

:fail
echo.
echo [ERRO] Falha ao preparar o laboratorio Bridge v2.
pause
exit /b 1

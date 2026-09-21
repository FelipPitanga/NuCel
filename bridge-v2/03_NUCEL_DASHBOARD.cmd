@echo off
setlocal EnableExtensions
title 2 - NUCEL DASHBOARD

set "ROOT=%~dp0.."
cd /d "%ROOT%"

if exist "C:\Program Files\nodejs\node.exe" set "PATH=C:\Program Files\nodejs;%PATH%"

echo.
echo ===============================================
echo       NuCel Dashboard - LOCAL
echo ===============================================
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo [ERRO] Node.js nao encontrado.
  pause
  exit /b 1
)

echo Node:
node --version
echo NPM:
call npm --version
echo.

if not exist "node_modules" (
  echo [1/2] Instalando dependencias do NuCel...
  call npm install
  if errorlevel 1 goto :fail
) else (
  echo [1/2] Dependencias ja instaladas.
)

echo [2/2] Iniciando dashboard em http://127.0.0.1:3000
echo.
echo Esta janela agora E o servidor do dashboard.
echo Se houver erro, ele aparecera aqui.
echo.

REM Abre o navegador alguns segundos depois, sem esconder o processo principal.
start "" cmd /c "timeout /t 8 /nobreak >nul && start """" http://127.0.0.1:3000"

call npm run dev -- -H 127.0.0.1 -p 3000
if errorlevel 1 goto :fail
exit /b 0

:fail
echo.
echo ===============================================
echo [ERRO] O dashboard NuCel parou.
echo ===============================================
echo.
echo Mande uma foto das ultimas linhas desta janela.
pause
exit /b 1

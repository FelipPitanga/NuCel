@echo off
setlocal EnableExtensions EnableDelayedExpansion
title 2 - NUCEL DASHBOARD

set "ROOT=%~dp0.."
cd /d "%ROOT%"

if exist "C:\Program Files\nodejs\node.exe" set "PATH=C:\Program Files\nodejs;%PATH%"

echo.
echo ===============================================
echo       NuCel Dashboard - LOCAL
echo ===============================================
echo.
echo Iniciando Next.js em http://localhost:3000
echo.

start "NuCel Next Dev" /b cmd /c "npm run dev"

set /a COUNT=0
:wait
set /a COUNT+=1
curl.exe -s -o nul --max-time 2 http://127.0.0.1:3000 >nul 2>nul
if not errorlevel 1 goto :ready
if !COUNT! GEQ 120 goto :timeout
<nul set /p "=."
timeout /t 1 /nobreak >nul
goto :wait

:ready
echo.
echo.
echo [OK] Dashboard pronto.
echo Abrindo http://localhost:3000
start "" "http://localhost:3000"
echo.
echo Deixe esta janela aberta durante o teste.
echo Pressione Ctrl+C apenas quando quiser parar o dashboard.
echo.

:hold
timeout /t 3600 /nobreak >nul
goto :hold

:timeout
echo.
echo [ERRO] Dashboard nao respondeu na porta 3000.
echo Confira os erros acima do npm run dev.
pause
exit /b 1

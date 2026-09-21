@echo off
setlocal EnableExtensions EnableDelayedExpansion
title 3 - NUCEL DIRECT LAB

echo.
echo ===============================================
echo       NuCel Direct Lab
echo ===============================================
echo.
echo Aguardando o ENGINE ficar pronto...
echo.

set /a COUNT=0
:wait
set /a COUNT+=1
curl.exe -s -o nul --max-time 2 http://127.0.0.1:8000/nucel-direct.html >nul 2>nul
if not errorlevel 1 goto :ready
if !COUNT! GEQ 180 goto :timeout
<nul set /p "=."
timeout /t 2 /nobreak >nul
goto :wait

:ready
echo.
echo.
echo [OK] Direct API pronta.
echo Abrindo http://localhost:8000/nucel-direct.html
start "" "http://localhost:8000/nucel-direct.html"
echo.
echo Essa janela pode ficar aberta como status do laboratorio.
echo Pressione R para abrir novamente ou Q para fechar.
echo.

:menu
choice /c RQ /n /m "[R] Reabrir  [Q] Fechar: "
if errorlevel 2 exit /b 0
if errorlevel 1 (
  start "" "http://localhost:8000/nucel-direct.html"
  goto :menu
)

:timeout
echo.
echo.
echo [ERRO] O ENGINE nao ficou pronto em 6 minutos.
echo Veja a janela "1 - NUCEL ENGINE".
pause
exit /b 1

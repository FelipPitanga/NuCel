@echo off
setlocal EnableExtensions EnableDelayedExpansion
title NuCel Bridge v2 - Teste Embed
cd /d "%~dp0"

echo.
echo ===============================================
echo   NuCel Bridge v2 - teste EMBED
echo ===============================================
echo.
echo Requisitos:
echo - ENGINE rodando novamente apos o 04_CONFIGURAR_EMBED.cmd
echo - 02_INICIAR_TUNEL.cmd rodando
echo.

where py >nul 2>nul
if not errorlevel 1 (
  start "NuCel Embed Lab Server" cmd /k "cd /d ""%CD%"" && py -3 -m http.server 5159 --bind 127.0.0.1"
) else (
  where python >nul 2>nul
  if errorlevel 1 (
    echo [ERRO] Python nao encontrado.
    pause
    exit /b 1
  )
  start "NuCel Embed Lab Server" cmd /k "cd /d ""%CD%"" && python -m http.server 5159 --bind 127.0.0.1"
)

echo Aguardando http://localhost:5159...
set /a COUNT=0
:wait_lab
set /a COUNT+=1
curl.exe -s -o nul --max-time 2 http://127.0.0.1:5159/embed-lab.html >nul 2>nul
if not errorlevel 1 goto :ready
if !COUNT! GEQ 30 goto :timeout
<nul set /p "=."
timeout /t 1 /nobreak >nul
goto :wait_lab

:ready
echo.
echo [OK] Laboratorio pronto.
start "" "http://localhost:5159/embed-lab.html"
echo.
echo Se o celular aparecer dentro da pagina, o embed do NuCel esta validado.
pause
exit /b 0

:timeout
echo.
echo [ERRO] O servidor de teste nao respondeu na porta 5159.
echo Verifique a janela "NuCel Embed Lab Server".
pause
exit /b 1

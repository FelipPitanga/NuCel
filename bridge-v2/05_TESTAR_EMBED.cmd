@echo off
setlocal EnableExtensions
title NuCel Bridge v2 - Teste Embed
cd /d "%~dp0"

echo.
echo ===============================================
echo   NuCel Bridge v2 - teste EMBED
echo ===============================================
echo.
echo Requisitos:
echo - 01_INICIAR_LOCAL.cmd / ENGINE rodando
echo - 02_INICIAR_TUNEL.cmd rodando
echo - 04_CONFIGURAR_EMBED.cmd ja executado
echo.
echo Abrindo teste em http://localhost:5159/embed-lab.html
echo.

start "" "http://localhost:5159/embed-lab.html"
py -3 -m http.server 5159 --bind 127.0.0.1
if errorlevel 1 python -m http.server 5159 --bind 127.0.0.1
pause

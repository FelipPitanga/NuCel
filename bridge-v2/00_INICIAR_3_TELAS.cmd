@echo off
setlocal EnableExtensions
title NuCel - Gerenciador

cd /d "%~dp0"

echo.
echo ===============================================
echo       NuCel Bridge v2 - 3 TELAS
echo ===============================================
echo.
echo Abrindo:
echo   [1] NUCEL - ENGINE
echo   [2] NUCEL - TUNEL
echo   [3] NUCEL - EMBED LAB
echo.

REM 1) Motor principal
start "1 - NUCEL ENGINE" cmd /k "title 1 - NUCEL ENGINE && cd /d ""%CD%"" && 01_INICIAR_LOCAL.cmd"

REM Espera o motor comecar a subir
timeout /t 5 /nobreak >nul

REM 2) Cloudflare Tunnel
start "2 - NUCEL TUNEL" cmd /k "title 2 - NUCEL TUNEL && cd /d ""%CD%"" && 02_INICIAR_TUNEL.cmd"

REM 3) Servidor local do laboratorio de embed
start "3 - NUCEL EMBED LAB" cmd /k "title 3 - NUCEL EMBED LAB && cd /d ""%CD%"" && (py -3 -m http.server 5159 --bind 127.0.0.1 || python -m http.server 5159 --bind 127.0.0.1)"

echo.
echo [OK] As 3 janelas foram abertas.
echo.
echo NAO FECHE:
echo   1 - NUCEL ENGINE
echo   2 - NUCEL TUNEL
echo   3 - NUCEL EMBED LAB
echo.
echo Quando quiser testar o embed, abra:
echo http://localhost:5159/embed-lab.html
echo.
timeout /t 4 /nobreak >nul
exit

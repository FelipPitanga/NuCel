@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "NUCEL_HIDDEN=0"
if /I "%~1"=="--hidden" set "NUCEL_HIDDEN=1"
title NuCel - START LIMPO

set "BRIDGE=%~dp0"
set "ROOT=%~dp0.."
set "READY=%BRIDGE%CURRENT_TUNNEL_URL.txt"

echo.
echo ===============================================
echo       NuCel - INICIALIZACAO LIMPA
echo ===============================================
echo.
echo Este processo vai:
echo  1. parar ENGINEs/tuneis antigos do NuCel
echo  2. limpar as portas 8000/8001
echo  3. criar e sincronizar o tunnel
echo  4. iniciar o ENGINE somente na porta 8000
echo  5. abrir o NuCel online
echo.

cd /d "%ROOT%"

echo [1/6] Atualizando codigo...
git restore -- "bridge-v2/engine-config.json" >nul 2>nul
git switch nucel-bridge-v2
if errorlevel 1 goto :fail
git pull origin nucel-bridge-v2
if errorlevel 1 goto :fail

echo [2/6] Encerrando processos antigos do NuCel...
powershell -NoProfile -ExecutionPolicy Bypass -File "%BRIDGE%99_LIMPAR_NUCEL.ps1"
if errorlevel 1 goto :fail

del /q "%READY%" >nul 2>nul
del /q "%PROGRAMDATA%\WsScrcpyWeb\.restart" >nul 2>nul

echo [3/6] Confirmando que a porta 8000 esta livre...
netstat -ano | findstr LISTENING | findstr ":8000" >nul
if not errorlevel 1 (
  echo [ERRO] A porta 8000 continua ocupada.
  netstat -ano | findstr ":8000"
  goto :fail
)

echo [4/6] Criando tunnel e sincronizando Supabase...
if "%NUCEL_HIDDEN%"=="1" (
  wscript.exe "%BRIDGE%START_TUNNEL_HIDDEN.vbs"
) else (
  start "2 - NUCEL TUNEL" powershell.exe -NoExit -ExecutionPolicy Bypass -File "%BRIDGE%02_TUNEL_AUTO.ps1"
)

set /a COUNT=0
:wait_tunnel
set /a COUNT+=1
if exist "%READY%" goto :tunnel_ready
if !COUNT! GEQ 100 (
  echo.
  echo [ERRO] O tunnel nao ficou pronto em 100 segundos.
  goto :fail
)
<nul set /p "=."
timeout /t 1 /nobreak >nul
goto :wait_tunnel

:tunnel_ready
echo.
set /p TUNNEL=<"%READY%"
echo [OK] Tunnel: !TUNNEL!

echo [5/6] Iniciando ENGINE na porta 8000...
if "%NUCEL_HIDDEN%"=="1" (
  wscript.exe "%BRIDGE%START_ENGINE_HIDDEN.vbs"
) else (
  start "1 - NUCEL ENGINE" cmd.exe /k "cd /d ""%BRIDGE%"" && 01_ENGINE_DIRETO.cmd"
)

set /a COUNT=0
:wait_engine
set /a COUNT+=1
curl.exe -s -o nul --max-time 2 http://127.0.0.1:8000/nucel-direct.html >nul 2>nul
if not errorlevel 1 goto :engine_ready
if !COUNT! GEQ 180 (
  echo.
  echo [ERRO] O ENGINE nao respondeu na porta 8000 em 3 minutos.
  goto :fail
)
<nul set /p "=."
timeout /t 1 /nobreak >nul
goto :wait_engine

:engine_ready
echo.
echo [OK] ENGINE respondendo na porta 8000.

echo [6/6] Abrindo NuCel online e sincronizando a conexao...
start "" "https://nucel.nuvixgestao.workers.dev/?bridgeUrl=!TUNNEL!"

echo.
echo ===============================================
echo       NUCEL PRONTO
echo ===============================================
echo.
echo Mantenha abertas APENAS:
echo   1 - NUCEL ENGINE
echo   2 - NUCEL TUNEL
echo.
echo Tunnel sincronizado:
echo   !TUNNEL!
echo.
echo No NuCel: Ctrl+F5 ^> Fechar card antigo ^> Iniciar.
echo.
timeout /t 8 /nobreak >nul
exit /b 0

:fail
echo.
echo ===============================================
echo [ERRO] Inicializacao interrompida.
echo ===============================================
echo.
if "%NUCEL_HIDDEN%"=="1" exit /b 1
pause
exit /b 1

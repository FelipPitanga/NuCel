@echo off
setlocal EnableExtensions
title NuCel Bridge v2 - Cloudflare Tunnel

set "CF=cloudflared"
where cloudflared >nul 2>nul
if errorlevel 1 (
  if exist "C:\Program Files (x86)\cloudflared\cloudflared.exe" (
    set "CF=C:\Program Files (x86)\cloudflared\cloudflared.exe"
  ) else if exist "C:\Program Files\cloudflared\cloudflared.exe" (
    set "CF=C:\Program Files\cloudflared\cloudflared.exe"
  ) else (
    echo [ERRO] cloudflared nao encontrado.
    echo Instale com: winget install --id Cloudflare.cloudflared
    pause
    exit /b 1
  )
)

echo.
echo ===============================================
echo   NuCel Bridge v2 - TUNEL DE TESTE
echo ===============================================
echo.
echo Antes de continuar, confirme que o laboratorio local
echo esta aberto em http://127.0.0.1:8000
echo.
echo A URL trycloudflare sera PUBLICA enquanto esta janela estiver aberta.
echo Use somente durante o teste.
echo.

"%CF%" tunnel --url http://127.0.0.1:8000
pause

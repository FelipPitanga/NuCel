@echo off
setlocal EnableExtensions
title NuCel - Configurar ambiente local

set "ROOT=%~dp0.."
set "ENV_FILE=%ROOT%\.env.local"

echo.
echo ===============================================
echo      NuCel - CONFIGURAR .env.local
echo ===============================================
echo.
echo Esse arquivo fica SOMENTE neste computador.
echo Ele ja esta ignorado pelo Git e nao sera enviado ao GitHub.
echo.

if exist "%ENV_FILE%" (
  echo Ja existe um .env.local.
  choice /c SN /n /m "Deseja substituir? [S/N]: "
  if errorlevel 2 exit /b 0
  copy /Y "%ENV_FILE%" "%ENV_FILE%.bak" >nul
  echo Backup criado em .env.local.bak
  echo.
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$secret=Read-Host 'Cole a SUPABASE_SECRET_KEY (nao aparecera na tela)' -AsSecureString;" ^
  "$b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret);" ^
  "try {$plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)} finally {[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)};" ^
  "if([string]::IsNullOrWhiteSpace($plain)){Write-Error 'Secret key vazia'; exit 1};" ^
  "$lines=@(" ^
  "'SUPABASE_URL=https://zbdusovcakvhsrubdaub.supabase.co'," ^
  "'SUPABASE_PUBLISHABLE_KEY=sb_publishable_OklkSWqNR2XDsnUS8O26iA_sRZkbpos'," ^
  "('SUPABASE_SECRET_KEY='+$plain)," ^
  "'NUCEL_OWNER_EMAIL=nuvixgestao@gmail.com'," ^
  "'NEXT_PUBLIC_NUCEL_BRIDGE_V2_URL='" ^
  ");" ^
  "$utf8=New-Object System.Text.UTF8Encoding($false);" ^
  "[IO.File]::WriteAllLines('%ENV_FILE%',$lines,$utf8)"

if errorlevel 1 (
  echo.
  echo [ERRO] Nao foi possivel criar o .env.local.
  pause
  exit /b 1
)

echo.
echo [OK] Arquivo criado:
echo %ENV_FILE%
echo.
echo Agora reinicie somente a janela "2 - NUCEL DASHBOARD".
echo.
pause

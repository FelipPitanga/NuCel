@echo off
setlocal EnableExtensions EnableDelayedExpansion
title NuCel - Publicar artefato do GitHub

set "ROOT=%~dp0.."
set "DOWNLOADS=%USERPROFILE%\Downloads"
set "TMP=%TEMP%\nucel-open-next-deploy"

cd /d "%ROOT%"

if exist "C:\Program Files\nodejs\node.exe" set "PATH=C:\Program Files\nodejs;%PATH%"

echo.
echo ===============================================
echo    NuCel - PUBLICAR BUILD DO GITHUB
echo ===============================================
echo.

set "ZIP="
for /f "delims=" %%F in ('dir /b /a-d /o-d "%DOWNLOADS%\nucel-open-next*.zip" 2^>nul') do (
  if not defined ZIP set "ZIP=%DOWNLOADS%\%%F"
)

if not defined ZIP (
  echo [ERRO] Nao encontrei o artefato em Downloads.
  echo.
  echo Baixe no GitHub Actions o artefato:
  echo   nucel-open-next
  echo.
  echo Depois rode este arquivo novamente.
  pause
  exit /b 1
)

echo Artefato encontrado:
echo %ZIP%
echo.

if exist "%TMP%" rmdir /s /q "%TMP%"
mkdir "%TMP%"

echo [1/4] Extraindo ZIP do GitHub...
tar -xf "%ZIP%" -C "%TMP%"
if errorlevel 1 goto :fail

set "TGZ="
for /r "%TMP%" %%F in (nucel-open-next.tar.gz) do set "TGZ=%%F"

if not defined TGZ (
  echo [ERRO] nucel-open-next.tar.gz nao encontrado dentro do ZIP.
  goto :fail
)

echo [2/4] Limpando build anterior...
if exist ".open-next" rmdir /s /q ".open-next"

echo [3/4] Instalando build Linux...
tar -xzf "%TGZ%" -C "%ROOT%"
if errorlevel 1 goto :fail

if not exist ".open-next\worker.js" (
  echo [ERRO] .open-next\worker.js nao foi encontrado apos extrair.
  goto :fail
)

echo [4/4] Publicando no Cloudflare Workers...
call npx wrangler deploy
if errorlevel 1 goto :fail

echo.
echo ===============================================
echo [OK] NUCEL ONLINE ATUALIZADO
echo ===============================================
echo.
echo https://nucel.nuvixgestao.workers.dev
start "" "https://nucel.nuvixgestao.workers.dev"
echo.
pause
exit /b 0

:fail
echo.
echo ===============================================
echo [ERRO] Nao foi possivel publicar.
echo ===============================================
echo.
echo Mande uma foto das ultimas linhas desta janela.
pause
exit /b 1

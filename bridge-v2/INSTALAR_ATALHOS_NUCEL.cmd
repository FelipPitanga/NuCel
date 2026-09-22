@echo off
setlocal
cd /d "%~dp0"
set "START=%CD%\INICIAR_NUCEL.vbs"
set "STOP=%CD%\PARAR_NUCEL.vbs"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ws=New-Object -ComObject WScript.Shell; $desktop=[Environment]::GetFolderPath('Desktop');" ^
  "$s=$ws.CreateShortcut((Join-Path $desktop 'NuCel.lnk')); $s.TargetPath=$env:WINDIR+'\System32\wscript.exe'; $s.Arguments='"'+$env:START+'"'; $s.WorkingDirectory=(Split-Path $env:START); $s.Description='Iniciar NuCel em segundo plano'; $s.Save();" ^
  "$p=$ws.CreateShortcut((Join-Path $desktop 'Parar NuCel.lnk')); $p.TargetPath=$env:WINDIR+'\System32\wscript.exe'; $p.Arguments='"'+$env:STOP+'"'; $p.WorkingDirectory=(Split-Path $env:STOP); $p.Description='Encerrar NuCel'; $p.Save()"

if errorlevel 1 (
  echo.
  echo [ERRO] Nao foi possivel criar os atalhos.
  pause
  exit /b 1
)

echo.
echo Atalhos criados na Area de Trabalho:
echo   NuCel
echo   Parar NuCel
echo.
pause

@echo off
setlocal
cd /d "%~dp0"

set "BIN=%LOCALAPPDATA%\NuCel\bin"
if not exist "%BIN%" mkdir "%BIN%" >nul 2>nul

> "%BIN%\nucel.cmd" echo @echo off
>> "%BIN%\nucel.cmd" echo call "%~dp0NUCEL_CLI.cmd" %%*

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$bin=[Environment]::ExpandEnvironmentVariables('%%LOCALAPPDATA%%\NuCel\bin');" ^
  "$p=[Environment]::GetEnvironmentVariable('Path','User');" ^
  "if([string]::IsNullOrWhiteSpace($p)){$p=''};" ^
  "$parts=@($p -split ';' | Where-Object { $_ -and $_.Trim() });" ^
  "if($parts -notcontains $bin){[Environment]::SetEnvironmentVariable('Path',(($parts + $bin) -join ';'),'User')}"

echo.
echo ===============================================
echo        COMANDO NUCEL INSTALADO
echo ===============================================
echo.
echo Feche este CMD e abra um NOVO CMD.
echo Depois use:
echo.
echo   nucel
echo   nucel status
echo   nucel stop
echo   nucel open
echo.
pause

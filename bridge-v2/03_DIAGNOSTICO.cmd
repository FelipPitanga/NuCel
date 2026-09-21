@echo off
setlocal
echo === NuCel Bridge v2 diagnostico ===
echo.
echo Node:
node --version
echo.
echo Git:
git --version
echo.
echo ADB atual:
where adb 2>nul
adb devices 2>nul
echo.
echo Porta 8000:
curl.exe -I --max-time 3 http://127.0.0.1:8000 2>nul
echo.
pause

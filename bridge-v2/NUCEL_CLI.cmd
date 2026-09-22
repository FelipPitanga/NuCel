@echo off
setlocal
set "BRIDGE=%~dp0"
set "ROOT=%~dp0.."

git -C "%ROOT%" switch nucel-bridge-v2 >nul 2>&1
git -C "%ROOT%" pull origin nucel-bridge-v2 >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BRIDGE%NUCEL_CLI.ps1" %*

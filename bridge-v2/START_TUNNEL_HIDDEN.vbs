Option Explicit
Dim shell, fso, dir, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & dir & "\02_TUNEL_AUTO.ps1"""
shell.Run cmd, 0, False

Option Explicit
Dim shell, fso, dir, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "cmd.exe /c """ & dir & "\01_ENGINE_DIRETO.cmd"""
shell.Run cmd, 0, False

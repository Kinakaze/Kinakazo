@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0packages\QQNT.Isolated\scripts\Start.ps1"
if errorlevel 1 pause

@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install.ps1" -TrustCertificate -Start
if errorlevel 1 pause

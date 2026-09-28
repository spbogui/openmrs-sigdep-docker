@echo off
REM Ouvre le port HTTP de SIGDEP dans le pare-feu (demande les droits administrateur)
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sigdep.ps1" firewall
pause

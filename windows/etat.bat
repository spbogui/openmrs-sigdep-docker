@echo off
REM Etat des conteneurs
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sigdep.ps1" status
pause

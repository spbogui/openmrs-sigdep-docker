@echo off
REM Sauvegarde immediate de la base
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sigdep.ps1" backup
pause

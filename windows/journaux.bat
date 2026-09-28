@echo off
REM Journaux OpenMRS en direct (Ctrl+C pour quitter)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sigdep.ps1" logs
pause

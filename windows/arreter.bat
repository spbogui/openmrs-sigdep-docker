@echo off
REM Arrete SIGDEP
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sigdep.ps1" stop
pause

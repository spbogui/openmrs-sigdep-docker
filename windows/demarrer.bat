@echo off
REM Demarre SIGDEP
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sigdep.ps1" start
pause

@echo off
REM Mise a jour - usage : mettre-a-jour.bat 3.0.1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sigdep.ps1" update "%~1"
pause

@echo off
REM Premiere installation - glisser le dump .zip sur ce fichier ou : installer.bat chemin\dump.zip
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sigdep.ps1" install "%~1"
pause

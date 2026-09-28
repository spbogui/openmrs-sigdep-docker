@echo off
REM Restaure une sauvegarde - glisser le fichier .sql.gz sur ce fichier
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sigdep.ps1" restore "%~1"
pause

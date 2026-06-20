@echo off
REM مُشغّل ويندوز — يفتح المتصفح تلقائياً
cd /d "%~dp0"
if "%PORT%"=="" set PORT=2222
start "" http://localhost:%PORT%
node server.js

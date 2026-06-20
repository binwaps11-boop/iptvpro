@echo off
REM مُشغّل ويندوز — يفتح لوحة الإدارة تلقائياً
cd /d "%~dp0"
if "%USER_PORT%"=="" set USER_PORT=2221
if "%ADMIN_PORT%"=="" set ADMIN_PORT=3331
start "" http://localhost:%ADMIN_PORT%/admin
node server.js

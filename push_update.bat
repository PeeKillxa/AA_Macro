@echo off
title AA Macro Studio - Push Update
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0push_update.ps1"
pause

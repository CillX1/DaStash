@echo off
title Installing Questrig
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
if errorlevel 1 (
  echo.
  echo Something went wrong - see the message above.
  pause
) else (
  timeout /t 3 >nul
)

@echo off
chcp 65001 >nul
title n8n + Twenty CRM - stop
rem Double-click this file to stop n8n + Twenty CRM (your data is kept).
if not exist "%~dp0..\scripts\windows\stop.ps1" (
  echo.
  echo [ПОМИЛКА] Не знайдено інші файли проєкту.
  echo Спочатку розпакуйте ZIP-архів і запускайте файл з розпакованої папки.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\windows\stop.ps1"

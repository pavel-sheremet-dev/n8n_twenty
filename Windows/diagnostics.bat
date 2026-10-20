@echo off
chcp 65001 >nul
title n8n + Twenty CRM - diagnostics
rem Double-click this file to create diagnostics.txt for your teacher.
if not exist "%~dp0..\scripts\windows\diagnostics.ps1" (
  echo.
  echo [ПОМИЛКА] Не знайдено інші файли проєкту.
  echo Спочатку розпакуйте ZIP-архів і запускайте файл з розпакованої папки.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\windows\diagnostics.ps1"

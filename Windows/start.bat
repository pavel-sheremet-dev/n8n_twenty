@echo off
chcp 65001 >nul
title n8n + Twenty CRM - start
rem Double-click this file to start n8n + Twenty CRM.
if not exist "%~dp0..\scripts\windows\start.ps1" (
  echo.
  echo [ПОМИЛКА] Не знайдено інші файли проєкту.
  echo Схоже, ви запустили файл прямо з ZIP-архіву.
  echo Спочатку розпакуйте архів: клік правою кнопкою на ZIP -^> "Видобути все" / "Extract All",
  echo а потім запустіть start.bat з розпакованої папки.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\windows\start.ps1"

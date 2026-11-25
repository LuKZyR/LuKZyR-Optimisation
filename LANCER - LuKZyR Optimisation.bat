@echo off
title LuKZyR Optimisation
rem v5.6 : l'exe affiche un message si l'appli ne demarre pas ; sans exe, PowerShell le fait lui-meme
if exist "%~dp0LuKZyR Optimisation.exe" (
  start "" "%~dp0LuKZyR Optimisation.exe"
) else (
  start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0scripts\LuKZyR-Optimisation.ps1"
)

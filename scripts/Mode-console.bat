@echo off
title LuKZyR Optimisation v0.1 beta - mode console
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Fais un clic droit sur ce fichier puis "Executer en tant qu'administrateur".
  pause
  exit /b 1
)
rem Reponses : touche O = Oui, touche N = Non
echo === Guide BIOS personnalise ===
choice /c ON /m "Generer le guide BIOS adapte a ta carte mere (fichier sur le Bureau) ? O = Oui, N = Non"
if %errorlevel% equ 1 powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Guide-BIOS.ps1" -Exporter
echo.
choice /c ON /m "Lancer le nettoyage, les applications et l'optimisation maintenant ? O = Oui, N = Non"
if %errorlevel% neq 1 exit /b 0
echo === 1/3 Nettoyage ===
rem Edge n'est jamais retire ici : il est propose apres l'installation des applis (Brave)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Debloat-PC.ps1" -SansEdge
echo === 2/3 Applications ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Installer-Applis.ps1"
echo.
choice /c ON /m "Desinstaller Microsoft Edge (seulement si un autre navigateur est installe) ? O = Oui, N = Non"
if %errorlevel% equ 1 powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Desinstaller-Edge.ps1"
echo === 3/3 Optimisation ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimisation-PC.ps1"
echo.
echo Tout est fini. Redemarre le PC.
pause

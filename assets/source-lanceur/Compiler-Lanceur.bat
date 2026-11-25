@echo off
rem Recompile "HelixFlux Optimisation.exe" avec l'icone assets\helixflux.ico
rem A lancer apres avoir remplace le logo (assets\helixflux.ico + assets\logo.png).
rem Utilise le compilateur C# fourni avec Windows (.NET Framework 4.x), rien a installer.
setlocal
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
  echo Compilateur csc.exe introuvable ^(.NET Framework 4^).
  pause
  exit /b 1
)
cd /d "%~dp0"
if exist "..\..\HelixFlux Optimisation.exe" attrib -r "..\..\HelixFlux Optimisation.exe"
"%CSC%" /nologo /target:winexe /platform:anycpu /win32icon:..\helixflux.ico /win32manifest:app.manifest /out:"..\..\HelixFlux Optimisation.exe" Lanceur.cs
if errorlevel 1 goto echec
rem v5.3 : ecran de chargement de l'appli (scripts\LkChargement.dll)
if exist "..\..\scripts\LkChargement.dll" attrib -r "..\..\scripts\LkChargement.dll"
"%CSC%" /nologo /target:library /platform:anycpu /out:"..\..\scripts\LkChargement.dll" LkChargement.cs
:echec
if errorlevel 1 (
  echo Echec de la compilation.
) else (
  echo OK : "HelixFlux Optimisation.exe" et scripts\LkChargement.dll recompiles.
)
if not "%1"=="/q" pause

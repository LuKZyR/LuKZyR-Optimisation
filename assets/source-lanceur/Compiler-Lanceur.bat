@echo off
rem Recompile "LuKZyR Optimisation.exe" avec l'icone assets\lukzyr.ico
rem A lancer apres avoir remplace le logo (assets\lukzyr.ico + assets\logo.png).
rem Utilise le compilateur C# fourni avec Windows (.NET Framework 4.x), rien a installer.
setlocal
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
  echo Compilateur csc.exe introuvable ^(.NET Framework 4^).
  if not "%1"=="/q" pause
  exit /b 1
)
cd /d "%~dp0"
set "EXE=echec"
set "DLL=echec"
if exist "..\..\LuKZyR Optimisation.exe" attrib -r "..\..\LuKZyR Optimisation.exe"
"%CSC%" /nologo /target:winexe /platform:anycpu /win32icon:..\lukzyr.ico /win32manifest:app.manifest /out:"..\..\LuKZyR Optimisation.exe" Lanceur.cs
if not errorlevel 1 set "EXE=OK"
rem ecran de chargement de l'appli (scripts\LkChargement.dll)
if exist "..\..\scripts\LkChargement.dll" attrib -r "..\..\scripts\LkChargement.dll"
"%CSC%" /nologo /target:library /platform:anycpu /out:"..\..\scripts\LkChargement.dll" LkChargement.cs
if not errorlevel 1 set "DLL=OK"
echo.
echo "LuKZyR Optimisation.exe"  : %EXE%
echo scripts\LkChargement.dll      : %DLL%
if "%EXE%%DLL%"=="OKOK" (
  echo OK : tout est recompile.
  set "CODE=0"
) else (
  echo Echec d'une partie de la compilation : voir les messages ci-dessus. Un fichier marque OK a bien ete recompile.
  set "CODE=1"
)
if not "%1"=="/q" pause
exit /b %CODE%

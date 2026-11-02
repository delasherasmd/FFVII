@echo off
setlocal
title Luces
cd /d "%~dp0"

rem ---- Buscar Python 3.8 o mas nuevo ----
set "PY="
set "PYW="
where py >nul 2>nul && (set "PY=py -3" & set "PYW=pyw -3")
if not defined PY (
  where python >nul 2>nul && (set "PY=python" & set "PYW=pythonw")
)
if not defined PY goto :sinpython
%PY% -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" >nul 2>nul || goto :sinpython

rem ---- Componente para hablar con Smart Life (solo la primera vez) ----
%PY% -c "import tinytuya" >nul 2>nul || (
  echo Instalando el componente para Smart Life, solo la primera vez...
  %PY% -m pip install --user --disable-pip-version-check -q tinytuya
)

rem Con argumentos (por ejemplo "Luces.bat escena cine") se usa la consola
if not "%~1"=="" (
  %PY% luces.py %*
  exit /b
)
start "" %PYW% luces.py
exit /b

:sinpython
echo.
echo  Falta Python 3. Se abrira la pagina de descarga.
echo  Al instalarlo marca la casilla "Add python.exe to PATH".
echo  Despues vuelve a abrir este archivo.
echo.
start "" https://www.python.org/downloads/
pause

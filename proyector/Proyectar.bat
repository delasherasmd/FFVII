@echo off
setlocal
title Proyectar
cd /d "%~dp0"

rem ---- Buscar Python 3.8 o mas nuevo ----
set "PY="
where py >nul 2>nul && set "PY=py -3"
if not defined PY (
  where python >nul 2>nul && set "PY=python"
)
if not defined PY goto :sinpython
%PY% -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" >nul 2>nul || goto :sinpython

rem ---- Componentes extra (solo la primera vez) ----
%PY% -c "import imageio_ffmpeg" >nul 2>nul || (
  echo Instalando ffmpeg, solo la primera vez - puede tardar un minuto...
  %PY% -m pip install --user --disable-pip-version-check -q imageio-ffmpeg
)
%PY% -c "import soundcard" >nul 2>nul || (
  echo Instalando la captura de sonido, solo la primera vez...
  %PY% -m pip install --user --disable-pip-version-check -q soundcard
)

echo.
echo  Abriendo Proyectar. No cierres esta ventana mientras proyectas.
echo  Si Windows pregunta por el Firewall, marca "Redes privadas" y "Redes publicas" y elige Permitir.
echo.
%PY% proyectar.py --ventana %*
if errorlevel 1 pause
exit /b

:sinpython
echo.
echo  Falta Python 3. Se abrira la pagina de descarga.
echo  Al instalarlo marca la casilla "Add python.exe to PATH".
echo  Despues vuelve a abrir este archivo.
echo.
start "" https://www.python.org/downloads/
pause

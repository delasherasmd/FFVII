@echo off
rem Arma Luces.exe (un solo archivo) en la carpeta dist\. Necesita Python 3.
cd /d "%~dp0"
py -3 -m pip install --user --disable-pip-version-check -q pyinstaller tinytuya
py -3 -m PyInstaller --noconfirm --clean --onefile --windowed --name Luces --icon recursos\icono.ico ^
  --add-data "recursos;recursos" --exclude-module unittest --exclude-module pydoc luces.py
echo.
echo Listo: dist\Luces.exe
pause

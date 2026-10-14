@echo off
rem Junta los discos (.cue o .bin) de esta carpeta en "Final Fantasy VII.pbp".
rem Poner este archivo y pbpack-windows-x86_64.exe junto a los discos y hacer doble clic.
setlocal enabledelayedexpansion
cd /d "%~dp0"
set "EXE=%~dp0pbpack-windows-x86_64.exe"
if not exist "%EXE%" (
	echo Falta pbpack-windows-x86_64.exe en esta carpeta.
	pause
	exit /b 1
)
set "LIST="
set N=0
for /f "delims=" %%F in ('dir /b /a-d /on *.cue 2^>nul') do (
	set "LIST=!LIST! "%%F""
	set /a N+=1
)
if !N! EQU 0 for /f "delims=" %%F in ('dir /b /a-d /on *.bin *.img 2^>nul') do (
	set "LIST=!LIST! "%%F""
	set /a N+=1
)
if !N! EQU 0 (
	echo No encontre discos .bin o .cue en esta carpeta.
	pause
	exit /b 1
)
"%EXE%" -s -V -t "Final Fantasy VII" -o "Final Fantasy VII.pbp" !LIST!
echo.
if errorlevel 1 (
	echo Hubo un error, revisa los mensajes de arriba.
) else (
	echo Copia "Final Fantasy VII.pbp" a la carpeta ports\finalfantasy7 de la tarjeta SD.
)
pause

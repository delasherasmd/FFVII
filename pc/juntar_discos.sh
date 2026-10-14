#!/bin/sh
# Junta los discos (.cue o .bin) de una carpeta en "Final Fantasy VII.pbp".
# uso: ./juntar_discos.sh [carpeta_con_los_discos]
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
DIR=${1:-.}
cd "$DIR"
set -- *.cue
[ -e "$1" ] || set -- *.bin
[ -e "$1" ] || set -- *.img
if [ ! -e "$1" ]; then
	echo "No encontre discos .bin o .cue en $DIR"
	exit 1
fi
chmod +x "$HERE/pbpack-linux-x86_64" 2>/dev/null || true
"$HERE/pbpack-linux-x86_64" -s -V -t "Final Fantasy VII" -o "Final Fantasy VII.pbp" "$@"
echo
echo "Copia \"Final Fantasy VII.pbp\" a la carpeta ports/finalfantasy7 de la tarjeta SD."

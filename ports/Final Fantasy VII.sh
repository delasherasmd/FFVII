#!/bin/bash
# Final Fantasy VII (PlayStation) como "port" para R36S y consolas RK3326
# (ArkOS / dArkOS / ROCKNIX / AmberELEC).
#
# El juego son tus propios discos; el motor es RetroArch + PCSX-ReARMed,
# que ya viene con el sistema de la consola.
#
# La primera vez junta los discos de  finalfantasy7/discos/  (.bin o .cue+.bin)
# en un solo archivo  finalfantasy7/Final Fantasy VII.pbp  y despues arranca
# siempre directo desde ese archivo.

# ---- opciones ----
PREFER_RA=64       # 64 o 32: que RetroArch usar si la consola tiene los dos
BORRAR_DISCOS=0    # 1 = borrar los .bin/.cue originales despues de crear y verificar el .pbp
# ------------------

TITLE="Final Fantasy VII"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAMEDIR="$SCRIPT_DIR/finalfantasy7"
DISCDIR="$GAMEDIR/discos"
PBP="$GAMEDIR/$TITLE.pbp"
LOG="$GAMEDIR/log.txt"

if sudo -n true 2>/dev/null; then
	ESUDO="sudo -n"
else
	ESUDO=""
fi

TTY=""
for t in /dev/tty1 /dev/tty0; do
	if [ -e "$t" ]; then
		$ESUDO chmod 666 "$t" 2>/dev/null
		if [ -w "$t" ]; then
			TTY="$t"
			break
		fi
	fi
done

msg() {
	echo "$*"
	echo "$*" >>"$LOG"
	# stdout is not always the screen (depends on the frontend)
	if [ -n "$TTY" ] && [ ! -t 1 ]; then
		echo "$*" >"$TTY"
	fi
}

clear_screen() {
	[ -n "$TTY" ] && printf "\033c" >"$TTY"
}

pause_exit() {
	msg ""
	msg "Volviendo al menu en 15 segundos..."
	sleep 15
	clear_screen
	exit 1
}

mkdir -p "$DISCDIR"
: >"$LOG"
clear_screen
msg "== $TITLE =="

# ---- CPU at full speed while packing and playing ----
GOV_SAVE=()
for g in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
	[ -f "$g" ] || continue
	GOV_SAVE+=("$g=$(cat "$g")")
	echo performance | $ESUDO tee "$g" >/dev/null 2>&1
done
restore_gov() {
	for e in "${GOV_SAVE[@]}"; do
		echo "${e#*=}" | $ESUDO tee "${e%%=*}" >/dev/null 2>&1
	done
}
trap restore_gov EXIT

# ---- find RetroArch and a PlayStation core ----
elf_bits() {
	case "$(od -An -tu1 -j4 -N1 "$1" 2>/dev/null | tr -d ' ')" in
	1) echo 32 ;;
	2) echo 64 ;;
	esac
}

find_emulator() {
	local order pair ra dir core c bits
	local pairs64=(
		"/usr/local/bin/retroarch|/home/ark/.config/retroarch/cores"
		"/opt/retroarch/bin/retroarch|/home/ark/.config/retroarch/cores"
		"/usr/bin/retroarch|/tmp/cores"
		"/usr/bin/retroarch|/usr/lib/libretro"
		"/usr/bin/retroarch|/usr/lib/aarch64-linux-gnu/libretro"
		"/usr/bin/retroarch|$HOME/.config/retroarch/cores"
	)
	local pairs32=(
		"/usr/local/bin/retroarch32|/home/ark/.config/retroarch32/cores"
		"/opt/retroarch/bin/retroarch32|/home/ark/.config/retroarch32/cores"
		"/usr/bin/retroarch32|/usr/lib32/libretro"
	)
	if [ "$PREFER_RA" = 32 ]; then order="32 64"; else order="64 32"; fi
	for bits in $order; do
		if [ "$bits" = 64 ]; then set -- "${pairs64[@]}"; else set -- "${pairs32[@]}"; fi
		for pair in "$@"; do
			ra="${pair%%|*}"
			dir="${pair#*|}"
			[ -x "$ra" ] && [ -d "$dir" ] || continue
			for c in pcsx_rearmed_libretro.so pcsx_rearmed_rumble_libretro.so \
				swanstation_libretro.so duckstation_libretro.so mednafen_psx_libretro.so; do
				core="$dir/$c"
				[ -f "$core" ] || continue
				[ "$(elf_bits "$core")" = "$bits" ] || continue
				RA="$ra"
				CORE="$core"
				return 0
			done
		done
	done
	return 1
}

if ! find_emulator; then
	msg "No se encontro RetroArch con un nucleo de PlayStation"
	msg "(pcsx_rearmed). Instala/actualiza el nucleo desde el sistema."
	pause_exit
fi

RACONF=()
case "$RA" in
/usr/bin/retroarch*)
	for cfg in /storage/.config/retroarch/retroarch.cfg /storage/roms/gamedata/retroarch/config/retroarch.cfg; do
		if [ -f "$cfg" ]; then
			RACONF=(--config "$cfg")
			break
		fi
	done
	;;
esac
msg "Emulador: $RA"
msg "Nucleo:   $(basename "$CORE")"

# ---- BIOS (recommended, not required) ----
check_bios() {
	local cfg sysdir d f
	cfg="${RACONF[1]}"
	[ -z "$cfg" ] && for f in /home/ark/.config/retroarch/retroarch.cfg "$HOME/.config/retroarch/retroarch.cfg"; do
		[ -f "$f" ] && cfg="$f" && break
	done
	if [ -n "$cfg" ]; then
		sysdir=$(sed -n 's/^[[:space:]]*system_directory[[:space:]]*=[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$cfg" | head -n 1)
		sysdir="${sysdir/#\~/$HOME}"
	fi
	for d in "$sysdir" /roms/bios /roms2/bios /storage/roms/bios "$HOME/.config/retroarch/system"; do
		[ -n "$d" ] && [ -d "$d" ] || continue
		for f in scph5501.bin scph1001.bin scph7001.bin scph101.bin scph5500.bin scph5502.bin \
			scph7003.bin scph7502.bin psxonpsp660.bin ps1_rom.bin; do
			if [ -n "$(find "$d" -maxdepth 1 -iname "$f" 2>/dev/null | head -n 1)" ]; then
				msg "BIOS:     $d/$f"
				return 0
			fi
		done
	done
	msg "BIOS:     no encontrada; se usa la BIOS interna (HLE)."
	msg "          Recomendado: scph1001.bin o scph5501.bin en la carpeta bios."
	return 1
}
check_bios || sleep 3

# ---- pick (or build) the game file ----
shopt -s nullglob nocaseglob

find_game() {
	local f
	if [ -f "$PBP" ]; then
		GAME="$PBP"
		return 0
	fi
	for f in "$GAMEDIR"/*.pbp "$DISCDIR"/*.pbp "$DISCDIR"/*.m3u; do
		GAME="$f"
		return 0
	done
	return 1
}

pack_discs() {
	local inputs=() chds=() f need avail tool status
	inputs=("$DISCDIR"/*.cue)
	if [ ${#inputs[@]} -eq 0 ]; then
		inputs=("$DISCDIR"/*.bin "$DISCDIR"/*.img)
	fi
	if [ ${#inputs[@]} -eq 0 ]; then
		chds=("$DISCDIR"/*.chd)
		if [ ${#chds[@]} -gt 0 ]; then
			# CHD can't go inside a .pbp, but one .m3u gives the same single entry
			: >"$DISCDIR/$TITLE.m3u"
			while IFS= read -r f; do
				basename "$f" >>"$DISCDIR/$TITLE.m3u"
			done < <(printf '%s\n' "${chds[@]}" | sort -V)
			GAME="$DISCDIR/$TITLE.m3u"
			msg "Discos CHD encontrados: se creo $TITLE.m3u"
			return 0
		fi
		msg ""
		msg "No hay discos todavia. Copia los 3 discos de FF7"
		msg "(.bin, o .cue + .bin) en la tarjeta SD, en:"
		msg "  $(basename "$SCRIPT_DIR")/finalfantasy7/discos"
		msg "y volve a abrir $TITLE desde Ports."
		pause_exit
	fi
	if [ ${#inputs[@]} -ne 3 ]; then
		msg "Aviso: se encontraron ${#inputs[@]} discos (FF7 tiene 3)."
	fi

	need=0
	for f in "$DISCDIR"/*.bin "$DISCDIR"/*.img; do
		need=$((need + $(stat -c %s "$f" 2>/dev/null || wc -c <"$f") / 1024))
	done
	need=$((need * 85 / 100 + 51200))
	avail=$(df -Pk "$GAMEDIR" | awk 'NR==2 {print $4}')
	if [ -n "$avail" ] && [ "$avail" -lt "$need" ]; then
		msg "No hay espacio suficiente en la tarjeta: hacen falta"
		msg "unos $((need / 1024)) MB libres y hay $((avail / 1024)) MB."
		pause_exit
	fi

	# exFAT/FAT cards may not keep the executable bit
	tool="/tmp/pbpack.$$"
	if ! { cp "$GAMEDIR/bin/pbpack" "$tool" && chmod +x "$tool" && "$tool" -h >/dev/null; } 2>/dev/null; then
		rm -f "$tool"
		tool="$GAMEDIR/bin/pbpack"
		chmod +x "$tool" 2>/dev/null
	fi

	msg ""
	msg "Primera vez: juntando los discos en un solo archivo."
	msg "Tarda unos minutos, no apagues la consola."
	msg ""
	rm -f "$PBP.tmp"
	"$tool" -s -V -t "$TITLE" -o "$PBP.tmp" "${inputs[@]}" 2>&1 | while IFS= read -r f; do
		msg "${f//"$GAMEDIR/"/}"
	done
	status=${PIPESTATUS[0]}
	[ "$tool" = "/tmp/pbpack.$$" ] && rm -f "$tool"
	if [ "$status" -ne 0 ] || [ ! -s "$PBP.tmp" ]; then
		rm -f "$PBP.tmp"
		msg ""
		msg "No se pudo crear el .pbp (detalles en finalfantasy7/log.txt)."
		pause_exit
	fi
	mv -f "$PBP.tmp" "$PBP"
	sync
	GAME="$PBP"
	if [ "$BORRAR_DISCOS" = 1 ]; then
		rm -f "$DISCDIR"/*.bin "$DISCDIR"/*.cue "$DISCDIR"/*.img
		msg "Discos originales borrados."
	else
		msg "Listo. Ya podes borrar los .bin/.cue de la carpeta discos"
		msg "para liberar espacio: el juego usa el .pbp."
	fi
	sleep 4
}

GAME=""
find_game || pack_discs
shopt -u nullglob nocaseglob

msg ""
msg "Iniciando: $(basename "$GAME")"
cd "$GAMEDIR" || exit 1
"$RA" "${RACONF[@]}" -L "$CORE" "$GAME" >>"$LOG" 2>&1
clear_screen

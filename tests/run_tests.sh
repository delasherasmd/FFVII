#!/bin/sh
# Packs three fake discs and checks the result.
#   PCSX_CORE=/path/pcsx_rearmed_libretro.so  also boots every disc in the
#   real emulator core (build it from https://github.com/libretro/pcsx_rearmed
#   with: make -f Makefile.libretro)
# Needs: cc, zlib headers, python3, genisoimage.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

cc -O2 -Wall -o "$T/pbpack" "$ROOT/src/pbpack.c" -lz -lpthread
python3 -I "$ROOT/tests/make_test_discs.py" "$T/discs"

# .bin only, given in the wrong order: -s must restore it
"$T/pbpack" -q -s -V -t "Final Fantasy VII" -o "$T/bin.pbp" \
	"$T/discs/Final Fantasy VII (Test) (Disc 3).bin" \
	"$T/discs/Final Fantasy VII (Test) (Disc 1).bin" \
	"$T/discs/Final Fantasy VII (Test) (Disc 2).bin"
"$T/pbpack" -q -V -t "Final Fantasy VII" -o "$T/cue.pbp" "$T/discs/"*.cue
cmp "$T/bin.pbp" "$T/cue.pbp"
python3 -I "$ROOT/tests/check_pbp.py" "$T/cue.pbp" "$T/discs/"*.bin

if [ -n "${PCSX_CORE:-}" ]; then
	cc -O1 -o "$T/lrtest" "$ROOT/tests/lrtest.c" -ldl -I"$ROOT/tests"
	mkdir -p "$T/sys"
	for i in 0 1 2; do
		want="SCUS9416$((3 + i))"
		LRTEST_SYSDIR="$T/sys" "$T/lrtest" "$PCSX_CORE" "$T/cue.pbp" 60 "$i" >"$T/core.log" 2>&1
		grep -q "CD-ROM ID: $want" "$T/core.log" || { cat "$T/core.log"; echo "FAIL disc $((i + 1))"; exit 1; }
		grep -q "RESULT discs 3" "$T/core.log" || { echo "FAIL disc count"; exit 1; }
		echo "core: disc $((i + 1)) boots ($want)"
	done
fi
echo "ALL TESTS PASSED"

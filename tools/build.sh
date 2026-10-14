#!/bin/sh
# Builds static pbpack binaries:
#   ports/finalfantasy7/bin/pbpack        R36S / any aarch64 Linux handheld
#   pc/pbpack-linux-x86_64                PC Linux
#   pc/pbpack-windows-x86_64.exe          PC Windows
#
# Needs: gcc, aarch64-linux-gnu-gcc, x86_64-w64-mingw32-gcc, curl
# (Ubuntu/Debian: apt install gcc gcc-aarch64-linux-gnu gcc-mingw-w64-x86-64 curl)
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
ZLIB_VER=1.3.1
ZLIB_SHA256=9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
ZLIB_URL="https://github.com/madler/zlib/releases/download/v$ZLIB_VER/zlib-$ZLIB_VER.tar.gz"

mkdir -p "$BUILD"
if [ ! -d "$BUILD/zlib-$ZLIB_VER" ]; then
	curl -sSLf -o "$BUILD/zlib.tar.gz" "$ZLIB_URL"
	echo "$ZLIB_SHA256  $BUILD/zlib.tar.gz" | sha256sum -c -
	tar -xzf "$BUILD/zlib.tar.gz" -C "$BUILD"
fi
Z="$BUILD/zlib-$ZLIB_VER"
ZSRC="$Z/adler32.c $Z/crc32.c $Z/deflate.c $Z/inflate.c $Z/inffast.c $Z/inftrees.c $Z/trees.c $Z/zutil.c"
CFLAGS="-O2 -Wall -I$Z -DHAVE_UNISTD_H"

build() {
	cc=$1 out=$2
	shift 2
	echo "building $out"
	mkdir -p "$(dirname "$out")"
	# shellcheck disable=SC2086
	$cc $CFLAGS -o "$out" "$ROOT/src/pbpack.c" $ZSRC -static -pthread "$@"
}

build aarch64-linux-gnu-gcc "$ROOT/ports/finalfantasy7/bin/pbpack" -s
build gcc "$ROOT/pc/pbpack-linux-x86_64" -s
build x86_64-w64-mingw32-gcc "$ROOT/pc/pbpack-windows-x86_64.exe" -s -U HAVE_UNISTD_H

file "$ROOT/ports/finalfantasy7/bin/pbpack" "$ROOT/pc/pbpack-linux-x86_64" "$ROOT/pc/pbpack-windows-x86_64.exe"

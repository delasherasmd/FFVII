#!/usr/bin/env python3
"""Validate a .pbp the way DuckStation/SwanStation's cd_image_pbp.cpp does
(PARAM.SFO keys, disc table, PSISOIMG header, TOC points) and optionally
compare every disc against the original raw images.

usage: check_pbp.py file.pbp [disc1.bin disc2.bin ...]
"""
import struct
import sys
import zlib


def fail(msg):
    print("FAIL:", msg)
    sys.exit(1)


def bcd2bin(b):
    return (b >> 4) * 10 + (b & 15)


def is_bcd(b):
    return (b >> 4) < 10 and (b & 15) < 10


def main():
    path, raws = sys.argv[1], sys.argv[2:]
    d = open(path, "rb").read()
    if d[:4] != b"\0PBP":
        fail("magic")
    offs = struct.unpack_from("<8I", d, 8)
    sfo_off, psar = offs[0], offs[7]

    # PARAM.SFO
    if d[sfo_off:sfo_off + 4] != b"\0PSF":
        fail("sfo magic")
    _, key_off, data_off, n = struct.unpack_from("<4I", d, sfo_off + 4)
    sfo = {}
    for i in range(n):
        ko, fmt, dlen, dmax, do = struct.unpack_from("<HHIII", d, sfo_off + 0x14 + 16 * i)
        k = d[sfo_off + key_off + ko:].split(b"\0", 1)[0].decode()
        v = d[sfo_off + data_off + do:sfo_off + data_off + do + dlen]
        sfo[k] = struct.unpack("<I", v)[0] if fmt == 0x0404 else v.split(b"\0", 1)[0].decode()
    print("SFO:", sfo)
    if sfo.get("BOOTABLE") != 1 or sfo.get("CATEGORY") != "ME":
        fail("DuckStation would reject this EBOOT (BOOTABLE/CATEGORY)")

    # disc table
    if d[psar:psar + 16] == b"PSTITLEIMG000000":
        table = struct.unpack_from("<5I", d, psar + 0x200)
        discs = [psar + t for t in table if t]
    elif d[psar:psar + 12] == b"PSISOIMG0000":
        discs = [psar]
    else:
        fail("psar magic")
    print("discs:", len(discs))
    if raws and len(raws) != len(discs):
        fail("expected %d discs" % len(raws))

    for i, base in enumerate(discs):
        if d[base:base + 12] != b"PSISOIMG0000":
            fail("disc %d header" % (i + 1))
        if d[base + 0x400:base + 0x404] == b"\0PGD":
            fail("looks encrypted")
        toc = [d[base + 0x800 + 10 * j:base + 0x800 + 10 * (j + 1)] for j in range(3)]
        if [t[2] for t in toc] != [0xA0, 0xA1, 0xA2]:
            fail("disc %d TOC points" % (i + 1))
        for t in toc[:2]:
            if not all(is_bcd(b) for b in t[7:10]):
                fail("disc %d TOC BCD" % (i + 1))
        first, last = bcd2bin(toc[0][7]), bcd2bin(toc[1][7])
        a2 = toc[2]
        sectors = (bcd2bin(a2[7]) * 60 + bcd2bin(a2[8])) * 75 + bcd2bin(a2[9])
        iso_off = struct.unpack_from("<I", d, base + 0xBFC)[0]
        if first != 1 or last < 1 or iso_off != 0x100000:
            fail("disc %d header fields" % (i + 1))
        t1 = d[base + 0x800 + 30:base + 0x800 + 40]
        print("disc %d: id %s, tracks %d, %d sectors, track1 %s" % (
            i + 1, d[base + 0x400:base + 0x40B].decode(), last, sectors, t1.hex()))

        if raws:
            raw = open(raws[i], "rb").read()
            if len(raw) // 2352 != sectors:
                fail("disc %d sector count %d != %d" % (i + 1, sectors, len(raw) // 2352))
            out = bytearray()
            nblocks = (sectors + 15) // 16
            for b in range(nblocks):
                off, size = struct.unpack_from("<IH", d, base + 0x4000 + 32 * b)
                blk = d[base + iso_off + off:base + iso_off + off + size]
                out += zlib.decompress(blk, -15)
            if bytes(out[:len(raw)]) != raw[:sectors * 2352]:
                fail("disc %d data mismatch" % (i + 1))
            print("disc %d: data identical to %s" % (i + 1, raws[i]))
    print("OK")


if __name__ == "__main__":
    main()

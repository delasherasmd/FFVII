#!/usr/bin/env python3
"""Build small fake PlayStation discs to exercise pbpack and the emulator.

Each disc is a real ISO9660 filesystem (made with genisoimage) with a
SYSTEM.CNF pointing at its own executable, written as raw 2352-byte
Mode 2 Form 1 sectors, followed by Form 2 sectors of random data (like
the XA audio / FMV streams on a real disc).  Disc sizes are deliberately
not multiples of 16 sectors.  On the last disc the boot files are placed at
the very end of the image, so booting it proves the final (partial) block is
readable.

usage: make_test_discs.py OUTDIR
"""
import os
import random
import struct
import subprocess
import sys
import tempfile

IDS = ["SCUS_941.63", "SCUS_941.64", "SCUS_941.65"]

EDC_TABLE = []
for i in range(256):
    e = i
    for _ in range(8):
        e = (e >> 1) ^ (0xD8018001 if e & 1 else 0)
    EDC_TABLE.append(e)


def edc(data):
    e = 0
    for b in data:
        e = EDC_TABLE[(e ^ b) & 0xFF] ^ (e >> 8)
    return e


def bcd(v):
    return ((v // 10) << 4) | (v % 10)


def header(lba):
    a = lba + 150
    return bytes([bcd(a // 75 // 60), bcd(a // 75 % 60), bcd(a % 75), 2])


SYNC = b"\x00" + b"\xff" * 10 + b"\x00"


def form1(lba, user):
    sub = bytes([0, 0, 0x08, 0]) * 2
    body = sub + user
    return SYNC + header(lba) + body + struct.pack("<I", edc(body)) + b"\x00" * 276


def form2(lba, user):
    sub = bytes([1, 1, 0x64, 0]) * 2  # file 1, channel 1, realtime|audio|form2
    body = sub + user
    return SYNC + header(lba) + body + struct.pack("<I", edc(body))


def ps_exe():
    # PS-X EXE that spins forever at 0x80010000
    hdr = bytearray(2048)
    hdr[0:8] = b"PS-X EXE"
    struct.pack_into("<IIIII", hdr, 0x10, 0x80010000, 0, 0x80010000, 2048, 0)
    struct.pack_into("<II", hdr, 0x30, 0x801FFF00, 0)
    hdr[0x4C:0x4C + 20] = b"Sony Computer Entert"
    code = struct.pack("<II", 0x08004000, 0) + bytes(2040)
    return bytes(hdr) + code


def make_disc(outdir, n, rng):
    exe = IDS[n]
    with tempfile.TemporaryDirectory() as root:
        with open(os.path.join(root, "SYSTEM.CNF"), "wb") as f:
            f.write(("BOOT = cdrom:\\%s;1\r\nTCB = 4\r\nEVENT = 10\r\nSTACK = 801FFF00\r\n" % exe).encode())
        with open(os.path.join(root, exe), "wb") as f:
            f.write(ps_exe())
        # compressible and incompressible payload
        with open(os.path.join(root, "TEXT.BIN"), "wb") as f:
            f.write((b"Final Fantasy VII test disc %d " % (n + 1)) * 4000)
        with open(os.path.join(root, "NOISE.BIN"), "wb") as f:
            f.write(rng.randbytes(300 * 1024))
        work = tempfile.mkdtemp()
        iso = os.path.join(work, "disc.iso")
        sort = os.path.join(work, "sort.txt")
        with open(sort, "w") as f:
            # negative weight = placed last on the disc
            f.write("%s -100\n%s -100\n" % (os.path.join(root, "SYSTEM.CNF"), os.path.join(root, exe)))
        subprocess.run(["genisoimage", "-quiet", "-no-pad", "-sort", sort, "-o", iso,
                        "-V", "FF7_TEST_DISC%d" % (n + 1), "-sysid", "PLAYSTATION", root], check=True)
        data = open(iso, "rb").read()
        os.remove(iso)
        os.remove(sort)
        os.rmdir(work)

    base = "Final Fantasy VII (Test) (Disc %d)" % (n + 1)
    sectors = len(data) // 2048
    extra = 0 if n == len(IDS) - 1 else 1000 + 37 * (n + 1)  # odd sizes on purpose
    with open(os.path.join(outdir, base + ".bin"), "wb") as f:
        for i in range(sectors):
            f.write(form1(i, data[i * 2048:(i + 1) * 2048]))
        for i in range(extra):
            f.write(form2(sectors + i, rng.randbytes(2324)))
    with open(os.path.join(outdir, base + ".cue"), "w") as f:
        f.write('FILE "%s.bin" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n' % base)
    return sectors + extra


def main():
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    rng = random.Random(7)
    for n in range(3):
        s = make_disc(outdir, n, rng)
        print("disc %d: %d sectors" % (n + 1, s))


if __name__ == "__main__":
    main()

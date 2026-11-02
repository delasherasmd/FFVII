# -*- coding: utf-8 -*-
"""Chromecast falso para las pruebas: conexión TLS con el protocolo Cast v2 y respuesta a mDNS.

Codifica los mensajes por su cuenta (no usa el código de proyectar.py), para que un error
en un lado no quede tapado por el mismo error en el otro."""

import json
import os
import shutil
import socket
import ssl
import struct
import subprocess
import tempfile
import threading
import time
import uuid

NS_CONN = "urn:x-cast:com.google.cast.tp.connection"
NS_HEART = "urn:x-cast:com.google.cast.tp.heartbeat"
NS_RECV = "urn:x-cast:com.google.cast.receiver"
NS_MEDIA = "urn:x-cast:com.google.cast.media"
APP = "CC1AD845"


def _varint(n):
    out = bytearray()
    while True:
        out.append((n & 0x7F) | (0x80 if n > 0x7F else 0))
        n >>= 7
        if not n:
            return bytes(out)


def encode(source, dest, ns, payload):
    body = bytearray(b"\x08\x00")
    for num, text in ((2, source), (3, dest), (4, ns)):
        b = text.encode()
        body += bytes([num << 3 | 2]) + _varint(len(b)) + b
    body += b"\x28\x00"
    b = json.dumps(payload).encode()
    body += bytes([6 << 3 | 2]) + _varint(len(b)) + b
    return struct.pack(">I", len(body)) + bytes(body)


def decode(data):
    i, out = 0, {}
    while i < len(data):
        key = data[i]
        i += 1
        num, wire = key >> 3, key & 7
        n = shift = 0
        while True:
            b = data[i]
            i += 1
            n |= (b & 0x7F) << shift
            shift += 7
            if not b & 0x80:
                break
        if wire == 2:
            out[num] = data[i:i + n].decode()
            i += n
    return out.get(2, ""), out.get(3, ""), out.get(4, ""), json.loads(out.get(6, "{}"))


class FakeCast:
    def __init__(self, name="Proyector Cast", mdns=True, analyze=True):
        self.name = name
        self.id = uuid.uuid4().hex
        self.analyze = analyze and shutil.which("ffprobe") is not None
        self.log = []                # (namespace, payload) recibidos
        self.launched = False
        self.volume = 1.0
        self.media = None
        self.player = "IDLE"
        self.pos = 0.0
        self._t0 = None
        self.analysis = None
        self.played = threading.Event()
        self.got_pong = threading.Event()
        self._tmp = tempfile.mkdtemp()
        cert, key = os.path.join(self._tmp, "c.pem"), os.path.join(self._tmp, "k.pem")
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                        "-days", "1", "-subj", "/CN=chromecast-falso"], check=True, capture_output=True)
        self.ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.ctx.load_cert_chain(cert, key)
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("0.0.0.0", 0))
        s.listen(5)
        self.sock, self.port = s, s.getsockname()[1]
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("239.255.255.250", 1900))
        self.ip = probe.getsockname()[0]
        probe.close()
        self._closed = False
        threading.Thread(target=self._accept, daemon=True).start()
        self.mdns = None
        if mdns:
            self._start_mdns()

    # --- Cast ---
    def _accept(self):
        while not self._closed:
            try:
                conn, _ = self.sock.accept()
                tls = self.ctx.wrap_socket(conn, server_side=True)
            except (OSError, ssl.SSLError):
                if self._closed:
                    return
                continue
            threading.Thread(target=self._serve, args=(tls,), daemon=True).start()

    def _serve(self, tls):
        buf = b""
        lock = threading.Lock()

        def send(dest, ns, payload, source="receiver-0"):
            with lock:
                tls.sendall(encode(source, dest, ns, payload))
        with tls:
            while True:
                try:
                    chunk = tls.recv(65536)
                except (OSError, ssl.SSLError):
                    return
                if not chunk:
                    return
                buf += chunk
                while len(buf) >= 4 and len(buf) >= 4 + struct.unpack(">I", buf[:4])[0]:
                    n = struct.unpack(">I", buf[:4])[0]
                    src, dst, ns, payload = decode(buf[4:4 + n])
                    buf = buf[4 + n:]
                    self.log.append((ns, payload))
                    try:
                        self._dispatch(send, src, dst, ns, payload)
                    except OSError:
                        return

    def _position(self):
        if self.player == "PLAYING" and self._t0 is not None:
            return self.pos + time.monotonic() - self._t0
        return self.pos

    def _media_status(self, rid):
        st = []
        if self.media is not None:
            st = [{"mediaSessionId": 7, "playerState": self.player, "currentTime": self._position(),
                   "media": dict(self.media, duration=self.media.get("duration", 100.0)), "volume": {"level": self.volume}}]
        return {"type": "MEDIA_STATUS", "status": st, "requestId": rid}

    def _receiver_status(self, rid):
        apps = [{"appId": APP, "displayName": "Default Media Receiver", "transportId": "web-7",
                 "sessionId": "sesion-7"}] if self.launched else []
        return {"type": "RECEIVER_STATUS", "requestId": rid,
                "status": {"applications": apps, "volume": {"level": self.volume, "muted": False}}}

    def _dispatch(self, send, src, dst, ns, p):
        kind, rid = p.get("type"), p.get("requestId", 0)
        if ns == NS_CONN and kind == "CONNECT" and dst == "receiver-0":
            send(src, NS_HEART, {"type": "PING"})  # el cliente debe contestar PONG
        elif ns == NS_HEART and kind == "PONG":
            self.got_pong.set()
        elif ns == NS_HEART and kind == "PING":
            send(src, NS_HEART, {"type": "PONG"})
        elif ns == NS_RECV:
            if kind == "LAUNCH" and p.get("appId") == APP:
                self.launched = True
            elif kind == "SET_VOLUME":
                self.volume = float(p["volume"]["level"])
            send(src, NS_RECV, self._receiver_status(rid))
        elif ns == NS_MEDIA:
            if dst != "web-7" or not self.launched:
                send(src, NS_MEDIA, {"type": "INVALID_REQUEST", "requestId": rid})
                return
            if kind == "LOAD":
                self.media = p["media"]
                self.player, self.pos, self._t0 = "PLAYING", float(p.get("currentTime", 0)), time.monotonic()
                self.played.clear()
                threading.Thread(target=self._analyze, args=(self.media["contentId"],), daemon=True).start()
                send(src, NS_MEDIA, self._media_status(0))  # aviso espontáneo (requestId 0)
            elif kind == "PAUSE":
                self.pos, self.player = self._position(), "PAUSED"
            elif kind == "PLAY":
                self.player, self._t0 = "PLAYING", time.monotonic()
            elif kind == "SEEK":
                self.pos, self._t0 = float(p["currentTime"]), time.monotonic()
            elif kind == "STOP":
                self.media, self.player = None, "IDLE"
            send(src, NS_MEDIA, self._media_status(rid))

    def _analyze(self, url):
        if self.analyze:
            r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,codec_name:format=format_name",
                                "-of", "json", url], capture_output=True, timeout=60)
            try:
                self.analysis = json.loads(r.stdout or b"{}")
            except ValueError:
                self.analysis = {}
        self.played.set()

    # --- mDNS ---
    def _start_mdns(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if hasattr(socket, "SO_REUSEPORT"):
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        s.bind(("", 5353))
        s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                     struct.pack("4s4s", socket.inet_aton("224.0.0.251"), socket.inet_aton(self.ip)))
        self.mdns = s
        threading.Thread(target=self._mdns_loop, daemon=True).start()

    def _mdns_loop(self):
        while not self._closed:
            try:
                data, addr = self.mdns.recvfrom(9000)
            except OSError:
                return
            if b"_googlecast" in data and struct.unpack(">H", data[2:4])[0] & 0x8000 == 0:
                self.mdns.sendto(self._mdns_answer(struct.unpack(">H", data[:2])[0]), addr)

    def _mdns_answer(self, txid):
        def name(n):
            return b"".join(bytes([len(p)]) + p.encode() for p in n.split(".")) + b"\x00"
        service = name("_googlecast._tcp.local")
        msg = bytearray(struct.pack(">6H", txid, 0x8400, 0, 1, 0, 3))
        # PTR: _googlecast._tcp.local -> instancia
        instance = name(f"Chromecast-{self.id}._googlecast._tcp.local")
        msg += service + struct.pack(">HHIH", 12, 1, 120, len(instance))
        inst_off = len(msg)
        msg += instance
        ptr_inst = struct.pack(">H", 0xC000 | inst_off)  # de acá en adelante, nombres comprimidos
        target = name(f"{self.id}.local")
        srv = struct.pack(">HHH", 0, 0, self.port) + target
        msg += ptr_inst + struct.pack(">HHIH", 33, 0x8001, 120, len(srv))
        target_off = len(msg) + 6
        msg += srv
        txt = b"".join(bytes([len(t)]) + t for t in
                       (f"id={self.id}".encode(), f"md=Proyector Falso".encode(), f"fn={self.name}".encode()))
        msg += ptr_inst + struct.pack(">HHIH", 16, 0x8001, 120, len(txt)) + txt
        msg += struct.pack(">H", 0xC000 | target_off) + struct.pack(">HHIH", 1, 0x8001, 120, 4) + socket.inet_aton(self.ip)
        return bytes(msg)

    def close(self):
        self._closed = True
        for s in (self.sock, self.mdns):
            if s is not None:
                try:
                    s.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                s.close()
        shutil.rmtree(self._tmp, ignore_errors=True)

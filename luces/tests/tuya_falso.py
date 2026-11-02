# -*- coding: utf-8 -*-
"""Lamparita Tuya/Smart Life falsa (protocolo local 3.3, cifrado con su clave) para las pruebas."""

import json
import socket
import struct
import threading
import time

from tinytuya.core import header as H
from tinytuya.core.crypto_helper import AESCipher
from tinytuya.core.message_helper import TuyaMessage, pack_message, parse_header, unpack_message

DP_QUERY, CONTROL, STATUS, HEART_BEAT = 10, 7, 8, 9


class FakeBulb:
    def __init__(self, dev_id, key, dps=None):
        self.id = dev_id
        self.key = key.encode()
        self.dps = dict(dps or {"20": True, "21": "white", "22": 1000, "23": 500, "24": "000003e803e8"})
        self.received = []  # cada orden recibida: {"22": 500, ...}
        self.seq = 0
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(5)
        self.port = self.sock.getsockname()[1]
        self._closed = False
        threading.Thread(target=self._accept, daemon=True).start()

    def info(self, name, **extra):
        """Entrada como la que guarda luces.py en dispositivos.json."""
        d = {"id": self.id, "name": name, "key": self.key.decode(), "ip": "127.0.0.1",
             "port": self.port, "version": "3.3", "category": "dj"}
        d.update(extra)
        return d

    def _accept(self):
        while not self._closed:
            try:
                conn, _ = self.sock.accept()
            except OSError:
                return
            threading.Thread(target=self._handle, args=(conn,), daemon=True).start()

    def _handle(self, conn):
        buf = b""
        with conn:
            while True:
                try:
                    data = conn.recv(4096)
                except OSError:
                    return
                if not data:
                    return
                buf += data
                while len(buf) >= 16:
                    head = parse_header(buf)
                    if len(buf) < head.total_length:
                        break
                    msg = unpack_message(buf[:head.total_length], header=head, no_retcode=True)
                    buf = buf[head.total_length:]
                    self._process(conn, msg)

    def _process(self, conn, msg):
        payload = msg.payload
        if payload.startswith(b"3.3"):
            payload = payload[len(H.PROTOCOL_33_HEADER):]
        body = {}
        if payload:
            body = json.loads(AESCipher(self.key).decrypt(payload, False))
        if msg.cmd == DP_QUERY:
            self._reply(conn, DP_QUERY, {"devId": self.id, "dps": self.dps})
        elif msg.cmd == CONTROL:
            changes = {str(k): v for k, v in body.get("dps", {}).items()}
            self.received.append(changes)
            self.dps.update(changes)
            self._reply(conn, CONTROL, None)
            self._reply(conn, STATUS, {"devId": self.id, "dps": changes, "t": int(time.time())}, header=True)
        elif msg.cmd == HEART_BEAT:
            self._reply(conn, HEART_BEAT, None)

    def _reply(self, conn, cmd, obj, header=False):
        payload = b""
        if obj is not None:
            enc = AESCipher(self.key).encrypt(json.dumps(obj).encode(), False)
            payload = (H.PROTOCOL_33_HEADER + enc) if header else enc
        self.seq += 1
        data = pack_message(TuyaMessage(self.seq, cmd, 0, struct.pack(">I", 0) + payload, 0, True,
                                        H.PREFIX_55AA_VALUE, None))
        try:
            conn.sendall(data)
        except OSError:
            pass

    def close(self):
        self._closed = True
        try:
            self.sock.shutdown(socket.SHUT_RDWR)  # despierta al hilo que espera en accept()
        except OSError:
            pass
        self.sock.close()

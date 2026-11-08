# -*- coding: utf-8 -*-
"""Proyector Android falso que habla ADB por red (protocolo real), para probar respaldo_proyector.py.

Pide autorización como un equipo de verdad: la primera vez el cliente manda su clave pública
y el «usuario» la acepta; después alcanza con la firma. Responde comandos de shell con textos
preparados y entrega archivos con el protocolo sync (RECV/DATA/DONE)."""

import os
import socket
import struct
import threading

def _cmd(s):
    return struct.unpack("<I", s)[0]


CNXN, AUTH, OPEN, OKAY, CLSE, WRTE = (_cmd(x) for x in (b"CNXN", b"AUTH", b"OPEN", b"OKAY", b"CLSE", b"WRTE"))
VERSION, MAXDATA = 0x01000000, 256 * 1024
TOKEN, FIRMA, CLAVE = 1, 2, 3


def _msg(cmd, a0, a1, data=b""):
    return struct.pack("<6I", cmd, a0, a1, len(data), sum(data) & 0xFFFFFFFF, cmd ^ 0xFFFFFFFF) + data


class FakeAdbDevice:
    def __init__(self, respuestas: dict, archivos: dict, pedir_permiso=True, propiedades=b"ro.product.model=HY300 Pro;"):
        self.respuestas = respuestas      # comando de shell -> salida (str)
        self.archivos = archivos          # ruta en el equipo -> bytes
        self.pedir_permiso = pedir_permiso
        self.propiedades = propiedades
        self.claves_aceptadas = set()
        self.comandos = []                # todo lo que se ejecutó (para revisar que no se cambió nada)
        self.sock = socket.socket()
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(5)
        self.port = self.sock.getsockname()[1]
        self._cerrado = False
        threading.Thread(target=self._aceptar, daemon=True).start()

    def _aceptar(self):
        while not self._cerrado:
            try:
                c, _ = self.sock.accept()
            except OSError:
                return
            threading.Thread(target=self._atender, args=(c,), daemon=True).start()

    @staticmethod
    def _leer(c):
        h = b""
        while len(h) < 24:
            parte = c.recv(24 - len(h))
            if not parte:
                raise ConnectionError
            h += parte
        cmd, a0, a1, n, _, _ = struct.unpack("<6I", h)
        data = b""
        while len(data) < n:
            parte = c.recv(n - len(data))
            if not parte:
                raise ConnectionError
            data += parte
        return cmd, a0, a1, data

    def _atender(self, c):
        local_id = 100
        try:
            cmd, *_ = self._leer(c)
            assert cmd == CNXN
            banner = b"device::" + self.propiedades + b"\0"
            if self.pedir_permiso:
                c.sendall(_msg(AUTH, TOKEN, 0, os.urandom(20)))
                while True:
                    cmd, a0, _, data = self._leer(c)
                    if cmd == AUTH and a0 == FIRMA:
                        if self.claves_aceptadas:     # (simplificado: la firma de una clave ya aceptada vale)
                            break
                        c.sendall(_msg(AUTH, TOKEN, 0, os.urandom(20)))
                    elif cmd == AUTH and a0 == CLAVE:
                        self.claves_aceptadas.add(data)   # el usuario pulsó «Permitir» en el proyector
                        break
            c.sendall(_msg(CNXN, VERSION, MAXDATA, banner))
            sync = {}
            while True:
                cmd, a0, a1, data = self._leer(c)
                if cmd == OPEN:
                    local_id += 1
                    destino = data.rstrip(b"\0").decode()
                    c.sendall(_msg(OKAY, local_id, a0))
                    if destino.startswith("shell:"):
                        orden = destino[6:]
                        self.comandos.append(orden)
                        salida = self.respuestas.get(orden, "").encode()
                        for i in range(0, len(salida), MAXDATA):
                            c.sendall(_msg(WRTE, local_id, a0, salida[i:i + MAXDATA]))
                            self._esperar_okay(c)
                        c.sendall(_msg(CLSE, local_id, a0))
                    elif destino == "sync:":
                        sync[local_id] = (a0, b"")
                elif cmd == WRTE and a1 in sync:
                    remoto, buf = sync[a1]
                    buf += data
                    c.sendall(_msg(OKAY, a1, remoto))
                    while len(buf) >= 8:
                        ident, largo = struct.unpack("<4sI", buf[:8])
                        if len(buf) < 8 + largo:
                            break
                        ruta, buf = buf[8:8 + largo].decode(), buf[8 + largo:]
                        if ident == b"RECV":
                            self.comandos.append(f"pull {ruta}")
                            contenido = self.archivos.get(ruta)
                            if contenido is None:
                                resp = b"FAIL" + struct.pack("<I", 14) + b"No such file !"
                            else:
                                resp = b"".join(b"DATA" + struct.pack("<I", len(contenido[i:i + 65536])) + contenido[i:i + 65536]
                                                for i in range(0, len(contenido), 65536)) + b"DONE" + struct.pack("<I", 0)
                            c.sendall(_msg(WRTE, a1, remoto, resp))
                    sync[a1] = (remoto, buf)
                elif cmd == CLSE:
                    if a1 in sync:
                        sync.pop(a1)
                        c.sendall(_msg(CLSE, a1, a0))
                # OKAY de los WRTE que mandamos: no hace falta hacer nada
        except (ConnectionError, OSError, AssertionError):
            pass
        finally:
            c.close()

    def _esperar_okay(self, c):
        cmd, *_ = self._leer(c)
        if cmd != OKAY:
            raise ConnectionError

    def close(self):
        self._cerrado = True
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()

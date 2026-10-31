#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Proyector falso: un "DLNA Media Renderer" mínimo para probar proyectar.py sin
hardware. Responde a la búsqueda SSDP, acepta las órdenes UPnP (SetAVTransportURI,
Play, Pause, Seek, volumen…) y, al recibir Play, descarga el video como lo haría
un proyector de verdad (y lo analiza con ffprobe si está instalado).

    python tests/renderer_falso.py            # queda escuchando en la red
"""

import json
import shutil
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.sax.saxutils import escape

AVT = "urn:schemas-upnp-org:service:AVTransport:1"
RC = "urn:schemas-upnp-org:service:RenderingControl:1"
_no_proxy = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def _fmt(sec):
    sec = max(0, int(sec))
    return f"{sec // 3600}:{sec % 3600 // 60:02d}:{sec % 60:02d}"


def _parse(t):
    h, m, s = (t or "0:0:0").split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def _local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("239.255.255.250", 1900))
        return s.getsockname()[0]
    finally:
        s.close()


class Fault(Exception):
    def __init__(self, code, desc):
        self.code, self.desc = code, desc


class FakeRenderer:
    def __init__(self, name="Proyector de prueba", ssdp=True, analyze=True, track_duration="0:01:40"):
        self.name = name
        self.udn = "uuid:" + str(uuid.uuid4())
        self.analyze = analyze and shutil.which("ffprobe") is not None
        self.track_duration = track_duration
        self.actions = []          # [(acción, {args})]
        self.uri = None
        self.meta = None
        self.state = "NO_MEDIA_PRESENT"
        self.volume = 30
        self.pos = 0.0
        self._started = None
        self.analysis = None       # salida de ffprobe del último video
        self.bytes_read = 0
        self.played = threading.Event()
        self.ip = _local_ip()
        self.http = ThreadingHTTPServer(("0.0.0.0", 0), self._handler())
        self.http.daemon_threads = True
        threading.Thread(target=self.http.serve_forever, daemon=True).start()
        self._ssdp_sock = None
        if ssdp:
            self._start_ssdp()

    @property
    def location(self):
        return f"http://{self.ip}:{self.http.server_address[1]}/desc.xml"

    # --- SSDP ---
    def _start_ssdp(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if hasattr(socket, "SO_REUSEPORT"):
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        s.bind(("", 1900))
        mreq = struct.pack("4s4s", socket.inet_aton("239.255.255.250"), socket.inet_aton(self.ip))
        s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
        self._ssdp_sock = s
        threading.Thread(target=self._ssdp_loop, daemon=True).start()

    def _ssdp_loop(self):
        while True:
            try:
                data, addr = self._ssdp_sock.recvfrom(65507)
            except OSError:
                return
            text = data.decode("utf-8", "replace")
            if not text.startswith("M-SEARCH"):
                continue
            st = next((l.split(":", 1)[1].strip() for l in text.splitlines() if l.upper().startswith("ST:")), "")
            if st not in ("ssdp:all", "upnp:rootdevice", AVT, "urn:schemas-upnp-org:device:MediaRenderer:1"):
                continue
            resp = ("HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nEXT:\r\n"
                    f"LOCATION: {self.location}\r\nSERVER: Linux UPnP/1.0 RendererFalso/1.0\r\n"
                    f"ST: {st}\r\nUSN: {self.udn}::{st}\r\n\r\n")
            self._ssdp_sock.sendto(resp.encode(), addr)

    # --- descripción ---
    def description(self):
        return f"""<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
 <specVersion><major>1</major><minor>0</minor></specVersion>
 <device>
  <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
  <friendlyName>{escape(self.name)}</friendlyName>
  <manufacturer>Pruebas</manufacturer><modelName>Falso 3000</modelName>
  <UDN>{self.udn}</UDN>
  <serviceList>
   <service><serviceType>{RC}</serviceType><serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
    <controlURL>/ctl/rc</controlURL><eventSubURL>/evt/rc</eventSubURL><SCPDURL>/rc.xml</SCPDURL></service>
   <service><serviceType>{AVT}</serviceType><serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
    <controlURL>ctl/avt</controlURL><eventSubURL>/evt/avt</eventSubURL><SCPDURL>/avt.xml</SCPDURL></service>
  </serviceList>
 </device>
</root>"""

    # --- reproducción simulada ---
    def position(self):
        if self.state == "PLAYING" and self._started is not None:
            return self.pos + time.monotonic() - self._started
        return self.pos

    def _player(self, uri):
        if self.analyze:
            r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,codec_name",
                                "-of", "json", uri], capture_output=True, timeout=60)
            try:
                self.analysis = json.loads(r.stdout or b"{}").get("streams", [])
            except ValueError:
                self.analysis = []
        else:
            try:
                with _no_proxy.open(uri, timeout=10) as resp:
                    self.bytes_read = len(resp.read(1_000_000))
            except OSError:
                self.bytes_read = -1
        self.played.set()

    def handle(self, action, args):
        self.actions.append((action, args))
        if action == "SetAVTransportURI":
            self.uri, self.meta = args.get("CurrentURI"), args.get("CurrentURIMetaData")
            self.state, self.pos, self._started = "STOPPED", 0.0, None
            return {}
        if action == "Play":
            if not self.uri:
                raise Fault(701, "Transition not available")
            if self.state != "PLAYING":
                if self.state != "PAUSED_PLAYBACK":
                    self.played.clear()
                    threading.Thread(target=self._player, args=(self.uri,), daemon=True).start()
                self.state, self._started = "PLAYING", time.monotonic()
            return {}
        if action == "Pause":
            self.pos, self.state = self.position(), "PAUSED_PLAYBACK"
            return {}
        if action == "Stop":
            self.state, self.pos, self._started = "STOPPED", 0.0, None
            return {}
        if action == "Seek":
            self.pos = _parse(args.get("Target"))
            self._started = time.monotonic()
            return {}
        if action == "GetTransportInfo":
            return {"CurrentTransportState": self.state, "CurrentTransportStatus": "OK", "CurrentSpeed": "1"}
        if action == "GetPositionInfo":
            return {"Track": "1", "TrackDuration": self.track_duration, "TrackMetaData": "",
                    "TrackURI": self.uri or "", "RelTime": _fmt(self.position()), "AbsTime": "NOT_IMPLEMENTED",
                    "RelCount": "2147483647", "AbsCount": "2147483647"}
        if action == "GetVolume":
            return {"CurrentVolume": str(self.volume)}
        if action == "SetVolume":
            self.volume = int(args["DesiredVolume"])
            return {}
        raise Fault(401, "Invalid Action")

    def _handler(self):
        renderer = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_GET(self):
                if self.path != "/desc.xml":
                    self.send_error(404)
                    return
                body = renderer.description().encode()
                self.send_response(200)
                self.send_header("Content-Type", 'text/xml; charset="utf-8"')
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                service, _, action = self.headers.get("SOAPAction", "").strip('"').partition("#")
                args = {}
                for el in ET.fromstring(body).iter():
                    if el.tag.endswith("}" + action) or el.tag == action:
                        args = {c.tag.split("}")[-1]: (c.text or "") for c in el}
                try:
                    out = renderer.handle(action, args)
                    inner = "".join(f"<{k}>{escape(str(v))}</{k}>" for k, v in out.items())
                    xml = (f'<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
                           f'<u:{action}Response xmlns:u="{service}">{inner}</u:{action}Response>'
                           f'</s:Body></s:Envelope>')
                    status = 200
                except Fault as f:
                    xml = ('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>'
                           '<faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail>'
                           '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">'
                           f'<errorCode>{f.code}</errorCode><errorDescription>{f.desc}</errorDescription>'
                           '</UPnPError></detail></s:Fault></s:Body></s:Envelope>')
                    status = 500
                data = xml.encode()
                self.send_response(status)
                self.send_header("Content-Type", 'text/xml; charset="utf-8"')
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
        return H

    def close(self):
        self.http.shutdown()
        self.http.server_close()
        if self._ssdp_sock:
            self._ssdp_sock.close()


if __name__ == "__main__":
    fr = FakeRenderer(name=sys.argv[1] if len(sys.argv) > 1 else "Proyector de prueba")
    print(f"Proyector falso escuchando: {fr.location}")
    try:
        while True:
            time.sleep(1)
            if fr.actions:
                action, args = fr.actions.pop(0)
                print(action, {k: (v[:80] + "…" if len(v) > 80 else v) for k, v in args.items()})
    except KeyboardInterrupt:
        fr.close()

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Proyectar - envía películas (o la pantalla de esta PC) a un proyector o TV
conectado a la misma red WiFi.

Usa DLNA / UPnP AV, el estándar que traen casi todos los proyectores
"smart" (en el menú suele llamarse "DLNA", "Media Renderer", "DMR",
"Screen Mirroring", "EShare" o similar).

    python proyectar.py                       abre la ventana
    python proyectar.py --listar              busca proyectores en la red
    python proyectar.py pelicula.mkv          proyecta una película (en consola)
    python proyectar.py pelicula.mkv --compatible --subs pelicula.srt
    python proyectar.py --pantalla            transmite la pantalla

Sólo necesita Python 3.8+. Opcionales:
    ffmpeg (o `pip install imageio-ffmpeg`)   modos Compatible y Pantalla
    `pip install soundcard`                   sonido de la PC en modo Pantalla
"""

from __future__ import annotations

import argparse
import codecs
import collections
import hashlib
import itertools
import json
import logging
import mimetypes
import os
import queue
import re
import select
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable, Dict, List, Optional, Tuple
from xml.sax.saxutils import escape as xml_escape

try:  # la ventana es opcional: sin tkinter queda el modo consola
    import tkinter as tk
    from tkinter import filedialog, messagebox, simpledialog, ttk
except ImportError:  # pragma: no cover
    tk = None

APP = "Proyectar"
VERSION = "1.0"
HTTP_PORT = 8765
CONFIG_PATH = os.path.join(os.path.expanduser("~"), ".proyectar.json")
LOG_PATH = os.path.join(tempfile.gettempdir(), "proyectar.log")
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)  # sin ventanas negras en Windows

log = logging.getLogger("proyectar")


class ProyectarError(Exception):
    """Error con un mensaje pensado para mostrarle al usuario."""


NOT_FOUND_HELP = """No encontré el proyector en la red (busqué DLNA y Chromecast).

• Verifica que el proyector esté encendido y conectado a la MISMA red WiFi que la PC.
• En el proyector abre la app de «Screen Mirroring», «EShare», «DLNA», «Cast» o similar
  (algunos sólo reciben videos con esa app abierta) y vuelve a buscar.
• Si conoces la IP del proyector (aparece en su menú de red), usa «Por IP…».
• En Windows, permite a Python en el Firewall (redes privadas y públicas).

Igual hay dos caminos que funcionan con casi cualquier proyector:
• «Navegador del proyector» (en la lista): abres una dirección en el navegador
  del proyector y lo manejas desde la PC.
• Pestaña «Pantalla de la PC» → «Miracast (Win + K)»."""

FFMPEG_HELP = """Para este modo hace falta ffmpeg.

Lo más fácil en Windows: abre «Proyectar.bat», que lo instala solo.
O en una terminal escribe:
    py -m pip install imageio-ffmpeg

(También sirve:  winget install Gyan.FFmpeg)"""


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

def fmt_time(seconds: Optional[float], ms: bool = False) -> str:
    """3723.5 -> '1:02:03' (o '1:02:03.500' con ms=True)."""
    seconds = max(0.0, float(seconds or 0))
    h = int(seconds // 3600)
    m = int(seconds % 3600 // 60)
    s = seconds % 60
    if ms:
        return f"{h}:{m:02d}:{s:06.3f}"
    return f"{h}:{m:02d}:{int(s):02d}"


def parse_time(text: Optional[str]) -> Optional[float]:
    """'1:02:03.5' -> 3723.5, '5:30' -> 330, '90' -> 90. None si no se entiende."""
    if not text:
        return None
    text = text.strip().lstrip("+")
    m = re.fullmatch(r"(?:(\d+):)?(\d{1,2}):(\d{1,2}(?:\.\d+)?)", text)
    if m:
        return int(m.group(1) or 0) * 3600 + int(m.group(2)) * 60 + float(m.group(3))
    if re.fullmatch(r"\d+(?:\.\d+)?", text):
        return float(text)
    return None


def looks_like_ip(text: str) -> bool:
    try:
        socket.inet_aton(text)
        return text.count(".") == 3
    except (OSError, TypeError):
        return False


def local_ip_for(host: str) -> Optional[str]:
    """IP de esta PC en la red por la que se llega a `host`."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect((host, 9))  # UDP: no envía nada, sólo elige la interfaz
        return s.getsockname()[0]
    except OSError:
        return None
    finally:
        s.close()


def local_ipv4s() -> List[str]:
    ips = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ips.add(info[4][0])
    except OSError:
        pass
    for target in ("239.255.255.250", "192.168.1.1", "8.8.8.8"):
        ip = local_ip_for(target)
        if ip:
            ips.add(ip)
    return sorted(ip for ip in ips if not ip.startswith("127.") and ip != "0.0.0.0")


# urllib usa los proxies del sistema; para hablar con el proyector en la red
# local nunca queremos pasar por un proxy.
_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def http_get(url: str, timeout: float = 5.0) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": f"{APP}/{VERSION}"})
    with _opener.open(req, timeout=timeout) as resp:
        return resp.read()


def parse_xml(data: bytes) -> ET.Element:
    """Parsea XML y quita los namespaces de las etiquetas (más fácil de buscar)."""
    root = ET.fromstring(data.strip())
    for el in root.iter():
        if isinstance(el.tag, str) and "}" in el.tag:
            el.tag = el.tag.split("}", 1)[1]
    return root


def load_config() -> dict:
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_config(cfg: dict) -> None:
    try:
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Búsqueda de proyectores (SSDP) y control (UPnP AVTransport)
# ---------------------------------------------------------------------------

SSDP_ADDR = ("239.255.255.250", 1900)
SSDP_TARGETS = (
    "urn:schemas-upnp-org:device:MediaRenderer:1",
    "urn:schemas-upnp-org:service:AVTransport:1",
)


def _msearch(st: str) -> bytes:
    return (
        "M-SEARCH * HTTP/1.1\r\n"
        "HOST: 239.255.255.250:1900\r\n"
        'MAN: "ssdp:discover"\r\n'
        "MX: 2\r\n"
        f"ST: {st}\r\n"
        f"USER-AGENT: {sys.platform} UPnP/1.1 {APP}/{VERSION}\r\n\r\n"
    ).encode()


def _parse_headers(data: bytes) -> Dict[str, str]:
    headers = {}
    for line in data.decode("utf-8", "replace").splitlines()[1:]:
        if ":" in line:
            key, value = line.split(":", 1)
            headers[key.strip().lower()] = value.strip()
    return headers


def ssdp_search(timeout: float = 3.0, hosts: Optional[List[str]] = None) -> List[str]:
    """Pregunta en la red quién es un 'Media Renderer'. Devuelve URLs de descripción."""
    socks: List[Tuple[socket.socket, Tuple[str, int]]] = []
    if hosts:  # búsqueda dirigida a una IP concreta
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind(("", 0))
        socks += [(s, (h, 1900)) for h in hosts]
    else:
        for ip in local_ipv4s() or ["0.0.0.0"]:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
            try:
                s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
                if ip != "0.0.0.0":
                    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(ip))
                s.bind((ip, 0))
            except OSError as e:
                log.debug("No se pudo usar la interfaz %s: %s", ip, e)
                s.close()
                continue
            socks.append((s, SSDP_ADDR))

    def send_all():
        for s, dest in socks:
            for st in SSDP_TARGETS:
                try:
                    s.sendto(_msearch(st), dest)
                except OSError as e:
                    log.debug("SSDP no se pudo enviar a %s: %s", dest, e)

    locations: Dict[str, Dict[str, str]] = {}
    unique = list({id(s): s for s, _ in socks}.values())
    start = time.monotonic()
    resent = False
    send_all()
    try:
        while True:
            now = time.monotonic()
            if not resent and now - start > 0.8:  # UDP se pierde: preguntamos dos veces
                send_all()
                resent = True
            remaining = start + timeout - now
            if remaining <= 0 or not unique:
                break
            ready, _, _ = select.select(unique, [], [], min(remaining, 0.25))
            for s in ready:
                try:
                    data, addr = s.recvfrom(65507)
                except OSError:
                    continue
                headers = _parse_headers(data)
                loc = headers.get("location")
                if loc and loc not in locations:
                    log.debug("SSDP: %s responde %s", addr[0], loc)
                    locations[loc] = headers
    finally:
        for s in unique:
            s.close()
    return list(locations)


class DLNAError(ProyectarError):
    def __init__(self, action: str, code: Optional[str], desc: str):
        self.action, self.code, self.desc = action, code, desc
        extra = f" (código {code})" if code else ""
        super().__init__(f"El proyector no aceptó «{action}»: {desc}{extra}")


def _soap(url: str, service: str, action: str, args: Dict[str, object], timeout: float) -> Dict[str, str]:
    body = "".join(f"<{k}>{xml_escape(str(v))}</{k}>" for k, v in args.items())
    envelope = (
        '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        f'<s:Body><u:{action} xmlns:u="{service}">{body}</u:{action}></s:Body></s:Envelope>'
    )
    req = urllib.request.Request(
        url,
        data=envelope.encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": 'text/xml; charset="utf-8"',
            "SOAPAction": f'"{service}#{action}"',
            "User-Agent": f"{APP}/{VERSION} UPnP/1.0 DLNADOC/1.50",
        },
    )
    try:
        with _opener.open(req, timeout=timeout) as resp:
            data = resp.read()
    except urllib.error.HTTPError as e:
        code, desc = None, f"HTTP {e.code}"
        try:
            err = parse_xml(e.read())
            code = err.findtext(".//errorCode")
            desc = err.findtext(".//errorDescription") or desc
        except (ET.ParseError, OSError):
            pass
        raise DLNAError(action, code, desc) from None
    except (urllib.error.URLError, OSError) as e:
        reason = getattr(e, "reason", e)
        raise DLNAError(action, None, f"no responde ({reason})") from None
    out: Dict[str, str] = {}
    try:
        root = parse_xml(data)
    except ET.ParseError:
        return out
    for el in root.iter():
        if el.tag == action + "Response":
            for child in el:
                out[child.tag] = child.text or ""
            break
    return out


@dataclass
class Renderer:
    """Un proyector / TV que acepta videos por DLNA."""
    name: str
    location: str
    udn: str = ""
    manufacturer: str = ""
    model: str = ""
    avt_url: str = ""
    avt_type: str = "urn:schemas-upnp-org:service:AVTransport:1"
    rc_url: str = ""
    rc_type: str = "urn:schemas-upnp-org:service:RenderingControl:1"

    @property
    def host(self) -> str:
        return urllib.parse.urlsplit(self.location).hostname or ""

    kind = "DLNA"
    live_format = "ts"  # formato para videos convertidos en vivo

    @property
    def label(self) -> str:
        return f"{self.name}  —  {self.kind} ({self.host})"

    @property
    def key(self) -> str:
        return self.udn or self.location

    def prefers_compatible(self, path: str) -> bool:
        return False  # los proyectores DLNA suelen abrir casi cualquier formato

    def load(self, url: str, mime: str, title: str, live: bool, features: str,
             duration: Optional[float] = None, size: Optional[int] = None,
             sub_url: Optional[str] = None, sub_mime: str = "text/srt") -> None:
        meta = didl_metadata(title, url, mime, features, duration=duration, size=size,
                             sub_url=sub_url, sub_mime=sub_mime)
        self.set_uri(url, meta)
        error = None
        for _ in range(4):
            try:
                self.play()
                return
            except DLNAError as e:  # algunos todavía están cargando: reintentamos
                error = e
                time.sleep(0.8)
        try:
            if self.transport_state() in ("PLAYING", "TRANSITIONING"):
                return  # empezó solo
        except DLNAError:
            pass
        raise error

    # --- acciones ---
    def avt(self, action: str, _timeout: float = 8.0, **args) -> Dict[str, str]:
        return _soap(self.avt_url, self.avt_type, action, {"InstanceID": 0, **args}, _timeout)

    def rc(self, action: str, _timeout: float = 5.0, **args) -> Dict[str, str]:
        if not self.rc_url:
            raise DLNAError(action, None, "este proyector no permite controlar el volumen")
        return _soap(self.rc_url, self.rc_type, action, {"InstanceID": 0, **args}, _timeout)

    def set_uri(self, uri: str, metadata: str) -> None:
        self.avt("SetAVTransportURI", CurrentURI=uri, CurrentURIMetaData=metadata)

    def play(self) -> None:
        self.avt("Play", Speed="1")

    def pause(self) -> None:
        self.avt("Pause")

    def stop(self) -> None:
        self.avt("Stop", _timeout=5.0)

    def seek(self, seconds: float) -> None:
        target = fmt_time(seconds)
        try:
            self.avt("Seek", Unit="REL_TIME", Target=target)
        except DLNAError as e:
            if not e.code:
                raise
            self.avt("Seek", Unit="ABS_TIME", Target=target)

    def transport_state(self) -> str:
        return self.avt("GetTransportInfo", _timeout=4.0).get("CurrentTransportState", "")

    def position(self) -> Tuple[Optional[float], Optional[float]]:
        r = self.avt("GetPositionInfo", _timeout=4.0)
        return parse_time(r.get("RelTime")), parse_time(r.get("TrackDuration"))

    def get_volume(self) -> int:
        return int(float(self.rc("GetVolume", Channel="Master").get("CurrentVolume") or 0))

    def set_volume(self, value: int) -> None:
        self.rc("SetVolume", Channel="Master", DesiredVolume=int(max(0, min(100, value))))


def load_renderer(location: str, timeout: float = 4.0) -> Optional[Renderer]:
    """Lee la descripción UPnP de un dispositivo; None si no es un reproductor."""
    root = parse_xml(http_get(location, timeout))
    base = (root.findtext("URLBase") or "").strip() or location
    for dev in root.iter("device"):
        services = dev.find("serviceList")
        if services is None:
            continue
        avt = rc = None
        for svc in services.findall("service"):
            stype = (svc.findtext("serviceType") or "").strip()
            ctl = urllib.parse.urljoin(base, (svc.findtext("controlURL") or "").strip())
            if ":service:AVTransport:" in stype:
                avt = (stype, ctl)
            elif ":service:RenderingControl:" in stype:
                rc = (stype, ctl)
        if not avt:
            continue
        r = Renderer(
            name=(dev.findtext("friendlyName") or "").strip() or urllib.parse.urlsplit(location).hostname or "?",
            location=location,
            udn=(dev.findtext("UDN") or "").strip(),
            manufacturer=(dev.findtext("manufacturer") or "").strip(),
            model=(dev.findtext("modelName") or "").strip(),
            avt_type=avt[0],
            avt_url=avt[1],
        )
        if rc:
            r.rc_type, r.rc_url = rc
        return r
    return None


def discover_dlna(timeout: float = 3.0, hosts: Optional[List[str]] = None) -> List[Renderer]:
    """Busca proyectores/TVs DLNA en la red local."""
    locations = ssdp_search(timeout, hosts)
    found: Dict[str, Renderer] = {}
    lock = threading.Lock()

    def load(loc):
        try:
            r = load_renderer(loc)
        except Exception as e:  # dispositivos raros de la red: los ignoramos
            log.debug("No se pudo leer %s: %s", loc, e)
            return
        if r:
            with lock:
                found.setdefault(r.key, r)

    threads = [threading.Thread(target=load, args=(loc,), daemon=True) for loc in locations]
    for t in threads:
        t.start()
    for t in threads:
        t.join(6)
    return sorted(found.values(), key=lambda r: r.name.lower())


def didl_metadata(title: str, url: str, mime: str, features: str, duration: Optional[float] = None,
                  size: Optional[int] = None, sub_url: Optional[str] = None, sub_mime: str = "text/srt") -> str:
    """Ficha DIDL-Lite que acompaña al video (muchos proyectores la exigen)."""
    attrs = f'protocolInfo="http-get:*:{mime}:{features}"'
    if duration:
        attrs += f' duration="{fmt_time(duration, ms=True)}"'
    if size:
        attrs += f' size="{size}"'
    upnp_class = "object.item.audioItem.musicTrack" if mime.startswith("audio/") else "object.item.videoItem"
    item = [
        f"<dc:title>{xml_escape(title)}</dc:title>",
        f"<upnp:class>{upnp_class}</upnp:class>",
        f"<res {attrs}>{xml_escape(url)}</res>",
    ]
    if sub_url:  # subtítulos externos (Samsung y algunos Android los muestran)
        kind = sub_mime.split("/")[-1].replace("x-", "")
        item.append(f'<res protocolInfo="http-get:*:{sub_mime}:*">{xml_escape(sub_url)}</res>')
        item.append(f'<sec:CaptionInfoEx sec:type="{kind}">{xml_escape(sub_url)}</sec:CaptionInfoEx>')
    return (
        '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
        'xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/" '
        'xmlns:sec="http://www.sec.co.kr/">'
        f'<item id="0" parentID="-1" restricted="1">{"".join(item)}</item></DIDL-Lite>'
    )


# ---------------------------------------------------------------------------
# Chromecast / Google Cast (búsqueda por mDNS y protocolo Cast v2)
# ---------------------------------------------------------------------------

MDNS_ADDR = ("224.0.0.251", 5353)
CAST_SERVICE = "_googlecast._tcp.local"
CAST_NS_CONN = "urn:x-cast:com.google.cast.tp.connection"
CAST_NS_HEARTBEAT = "urn:x-cast:com.google.cast.tp.heartbeat"
CAST_NS_RECEIVER = "urn:x-cast:com.google.cast.receiver"
CAST_NS_MEDIA = "urn:x-cast:com.google.cast.media"
CAST_MEDIA_APP = "CC1AD845"  # reproductor estándar de Google


def _dns_name(name: str) -> bytes:
    out = b""
    for part in name.strip(".").split("."):
        b = part.encode("utf-8")
        out += bytes([len(b)]) + b
    return out + b"\x00"


def mdns_query_packet(service: str) -> bytes:
    # una pregunta PTR, pidiendo respuesta directa (unicast) a nuestro puerto
    return struct.pack(">6H", 0, 0, 1, 0, 0, 0) + _dns_name(service) + struct.pack(">HH", 12, 0x8001)


def _read_dns_name(data: bytes, off: int) -> Tuple[str, int]:
    labels, end, hops = [], None, 0
    while True:
        n = data[off]
        if n == 0:
            off += 1
            break
        if n & 0xC0 == 0xC0:  # puntero (compresión de nombres)
            if end is None:
                end = off + 2
            off = ((n & 0x3F) << 8) | data[off + 1]
            hops += 1
            if hops > 30:
                raise ValueError("nombre DNS en bucle")
            continue
        labels.append(data[off + 1:off + 1 + n].decode("utf-8", "replace"))
        off += 1 + n
    return ".".join(labels), (end if end is not None else off)


def parse_mdns(data: bytes) -> List[Tuple[str, int, object]]:
    """Registros de una respuesta mDNS: (nombre, tipo, valor) para PTR, SRV, TXT y A."""
    qd, an, ns, ar = struct.unpack(">4H", data[4:12])
    off = 12
    for _ in range(qd):
        _, off = _read_dns_name(data, off)
        off += 4
    records = []
    for _ in range(an + ns + ar):
        name, off = _read_dns_name(data, off)
        rtype, _, _, rdlen = struct.unpack(">HHIH", data[off:off + 10])
        off += 10
        start, rd = off, data[off:off + rdlen]
        off += rdlen
        if rtype == 12:
            value: object = _read_dns_name(data, start)[0]
        elif rtype == 33:
            value = (struct.unpack(">H", rd[4:6])[0], _read_dns_name(data, start + 6)[0])
        elif rtype == 16:
            txt, i = {}, 0
            while i < len(rd):
                item = rd[i + 1:i + 1 + rd[i]].decode("utf-8", "replace")
                i += 1 + rd[i]
                k, _, v = item.partition("=")
                txt[k.lower()] = v
            value = txt
        elif rtype == 1 and rdlen == 4:
            value = socket.inet_ntoa(rd)
        else:
            continue
        records.append((name, rtype, value))
    return records


def mdns_browse(service: str = CAST_SERVICE, timeout: float = 2.5,
                hosts: Optional[List[str]] = None) -> List[dict]:
    """Busca servicios mDNS (por ejemplo Chromecast). Devuelve [{name, host, port, txt}]."""
    socks: List[Tuple[socket.socket, Tuple[str, int]]] = []
    if hosts:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind(("", 0))
        socks += [(s, (h, 5353)) for h in hosts]
    else:
        for ip in local_ipv4s() or ["0.0.0.0"]:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
            try:
                s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 255)
                if ip != "0.0.0.0":
                    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(ip))
                s.bind((ip, 0))
            except OSError:
                s.close()
                continue
            socks.append((s, MDNS_ADDR))
    query = mdns_query_packet(service)
    unique = list({id(s): s for s, _ in socks}.values())
    ptr: Dict[str, str] = {}
    srv: Dict[str, Tuple[int, str]] = {}
    txt: Dict[str, dict] = {}
    addr_of: Dict[str, str] = {}
    source: Dict[str, str] = {}

    def send_all():
        for s, dest in socks:
            try:
                s.sendto(query, dest)
            except OSError:
                pass
    start, resent = time.monotonic(), False
    send_all()
    try:
        while unique:
            now = time.monotonic()
            if not resent and now - start > 0.8:
                send_all()
                resent = True
            remaining = start + timeout - now
            if remaining <= 0:
                break
            ready, _, _ = select.select(unique, [], [], min(remaining, 0.25))
            for s in ready:
                try:
                    data, addr = s.recvfrom(9000)
                    records = parse_mdns(data)
                except (OSError, ValueError, IndexError, struct.error):
                    continue
                for name, rtype, value in records:
                    key = name.lower()
                    if rtype == 12 and key == service.lower():
                        ptr[str(value).lower()] = str(value)
                        source.setdefault(str(value).lower(), addr[0])
                    elif rtype == 33:
                        srv[key] = value  # type: ignore[assignment]
                    elif rtype == 16:
                        txt[key] = value  # type: ignore[assignment]
                    elif rtype == 1:
                        addr_of[key] = str(value)
    finally:
        for s in unique:
            s.close()
    out = []
    for key, instance in ptr.items():
        port, target = srv.get(key, (8009, ""))
        out.append({"name": instance, "host": addr_of.get(target.lower()) or source.get(key),
                    "port": port, "txt": txt.get(key, {})})
    return out


def _pb_varint(n: int) -> bytes:
    out = b""
    while True:
        byte = n & 0x7F
        n >>= 7
        if n:
            out += bytes([byte | 0x80])
        else:
            return out + bytes([byte])


def cast_encode(source: str, dest: str, namespace: str, payload: str) -> bytes:
    """Mensaje Cast (protobuf CastMessage) con su largo adelante."""
    def text(field_no, value):
        b = value.encode("utf-8")
        return _pb_varint(field_no << 3 | 2) + _pb_varint(len(b)) + b
    msg = b"\x08\x00" + text(2, source) + text(3, dest) + text(4, namespace) + b"\x28\x00" + text(6, payload)
    return struct.pack(">I", len(msg)) + msg


def cast_decode(data: bytes) -> Dict[str, object]:
    fields: Dict[int, object] = {}
    i = 0
    while i < len(data):
        key, shift = 0, 0
        while True:
            b = data[i]
            i += 1
            key |= (b & 0x7F) << shift
            shift += 7
            if not b & 0x80:
                break
        num, wire = key >> 3, key & 7
        if wire == 0:
            val, shift = 0, 0
            while True:
                b = data[i]
                i += 1
                val |= (b & 0x7F) << shift
                shift += 7
                if not b & 0x80:
                    break
            fields[num] = val
        elif wire == 2:
            n, shift = 0, 0
            while True:
                b = data[i]
                i += 1
                n |= (b & 0x7F) << shift
                shift += 7
                if not b & 0x80:
                    break
            fields[num] = data[i:i + n]
            i += n
        elif wire == 1:
            i += 8
        elif wire == 5:
            i += 4
        else:
            raise ValueError("mensaje Cast inválido")

    def s(n):
        v = fields.get(n, b"")
        return v.decode("utf-8", "replace") if isinstance(v, bytes) else str(v)
    return {"source": s(2), "dest": s(3), "ns": s(4), "payload": s(6)}


class CastConnection:
    """Conexión cifrada con un Chromecast (puerto 8009)."""

    def __init__(self, host: str, port: int = 8009, timeout: float = 6.0):
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE  # los Chromecast usan certificados propios
        try:
            raw = socket.create_connection((host, port), timeout=timeout)
            self.sock = ctx.wrap_socket(raw)
        except (OSError, ssl.SSLError) as e:
            raise ProyectarError(f"No pude conectar con el Chromecast ({host}): {e}") from None
        self.sock.settimeout(None)
        self.closed = False
        self.receiver: dict = {}
        self._ids = itertools.count(1)
        self._waiters: Dict[int, list] = {}
        self._send_lock = threading.Lock()
        threading.Thread(target=self._reader, daemon=True, name="cast-rx").start()
        threading.Thread(target=self._heartbeat, daemon=True, name="cast-ping").start()
        self.send(CAST_NS_CONN, {"type": "CONNECT"})

    def send(self, ns: str, obj: dict, dest: str = "receiver-0") -> None:
        data = cast_encode("sender-0", dest, ns, json.dumps(obj))
        with self._send_lock:
            try:
                self.sock.sendall(data)
            except OSError as e:
                self.closed = True
                raise ProyectarError(f"Se cortó la conexión con el Chromecast: {e}") from None

    def request(self, ns: str, obj: dict, dest: str = "receiver-0", timeout: float = 10.0) -> dict:
        rid = next(self._ids)
        waiter: list = [threading.Event(), None]
        self._waiters[rid] = waiter
        self.send(ns, dict(obj, requestId=rid), dest)
        if not waiter[0].wait(timeout) or waiter[1] is None:
            self._waiters.pop(rid, None)
            raise ProyectarError(f"El Chromecast no respondió a «{obj.get('type')}».")
        return waiter[1]

    def _reader(self):
        buf = b""
        try:
            while True:
                chunk = self.sock.recv(65536)
                if not chunk:
                    break
                buf += chunk
                while len(buf) >= 4:
                    n = struct.unpack(">I", buf[:4])[0]
                    if len(buf) < 4 + n:
                        break
                    msg, buf = cast_decode(buf[4:4 + n]), buf[4 + n:]
                    self._handle(msg)
        except (OSError, ValueError, IndexError):
            pass
        finally:
            self.closed = True
            for w in list(self._waiters.values()):
                w[0].set()

    def _handle(self, msg: dict):
        try:
            payload = json.loads(msg.get("payload") or "{}")
        except ValueError:
            return
        kind = payload.get("type")
        if msg.get("ns") == CAST_NS_HEARTBEAT and kind == "PING":
            try:
                self.send(CAST_NS_HEARTBEAT, {"type": "PONG"}, msg.get("source") or "receiver-0")
            except ProyectarError:
                pass
            return
        if kind == "RECEIVER_STATUS":
            self.receiver = payload.get("status") or {}
        waiter = self._waiters.pop(payload.get("requestId") or 0, None)
        if waiter:
            waiter[1] = payload
            waiter[0].set()

    def _heartbeat(self):
        while not self.closed:
            time.sleep(5)
            try:
                self.send(CAST_NS_HEARTBEAT, {"type": "PING"})
            except ProyectarError:
                return

    def close(self):
        try:
            self.send(CAST_NS_CONN, {"type": "CLOSE"})
        except ProyectarError:
            pass
        self.closed = True
        try:
            self.sock.close()
        except OSError:
            pass


class CastRenderer:
    """Proyector o TV con Chromecast / Google Cast integrado."""
    kind = "Chromecast"
    live_format = "mp4"

    def __init__(self, name: str, host: str, port: int = 8009, model: str = "", udn: str = ""):
        self.name, self.host, self.port, self.model, self.udn = name, host, int(port), model, udn
        self.manufacturer = ""
        self.location = f"cast://{host}:{port}"
        self._conn: Optional[CastConnection] = None
        self._transport: Optional[str] = None
        self._session: Optional[int] = None
        self._last: Optional[dict] = None
        self._last_at = 0.0
        self._lock = threading.RLock()

    @property
    def label(self) -> str:
        return f"{self.name}  —  {self.kind} ({self.host})"

    @property
    def key(self) -> str:
        return self.udn or self.location

    def prefers_compatible(self, path: str) -> bool:
        return os.path.splitext(path)[1].lower() not in (".mp4", ".m4v", ".webm")

    def _c(self) -> CastConnection:
        if self._conn is None or self._conn.closed:
            self._conn = CastConnection(self.host, self.port)
            self._transport = None
        return self._conn

    @staticmethod
    def _media_app(status: dict) -> Optional[dict]:
        return next((a for a in (status or {}).get("applications") or []
                     if a.get("appId") == CAST_MEDIA_APP and a.get("transportId")), None)

    def _attach(self, launch: bool) -> Optional[str]:
        """Se conecta al reproductor del Chromecast (abriéndolo si hace falta)."""
        c = self._c()
        app = self._media_app(c.request(CAST_NS_RECEIVER, {"type": "GET_STATUS"}).get("status"))
        if not app and launch:
            resp = c.request(CAST_NS_RECEIVER, {"type": "LAUNCH", "appId": CAST_MEDIA_APP}, timeout=25)
            if resp.get("type") == "LAUNCH_ERROR":
                raise ProyectarError(f"El Chromecast no pudo abrir el reproductor: {resp.get('reason')}")
            app = self._media_app(resp.get("status"))
            end = time.monotonic() + 15
            while not app and time.monotonic() < end:
                time.sleep(0.5)
                app = self._media_app(c.request(CAST_NS_RECEIVER, {"type": "GET_STATUS"}).get("status"))
            if not app:
                raise ProyectarError("El Chromecast no abrió el reproductor.")
        if not app:
            return None
        if app["transportId"] != self._transport:
            c.send(CAST_NS_CONN, {"type": "CONNECT"}, app["transportId"])
            self._transport = app["transportId"]
        return self._transport

    def load(self, url: str, mime: str, title: str, live: bool, features: str = "",
             duration: Optional[float] = None, size: Optional[int] = None,
             sub_url: Optional[str] = None, sub_mime: str = "text/vtt") -> None:
        with self._lock:
            tid = self._attach(launch=True)
            media: dict = {"contentId": url, "contentType": mime, "streamType": "LIVE" if live else "BUFFERED",
                           "metadata": {"metadataType": 0, "title": title}}
            if duration and not live:
                media["duration"] = duration
            req: dict = {"type": "LOAD", "media": media, "autoplay": True, "currentTime": 0}
            if sub_url:
                media["tracks"] = [{"trackId": 1, "type": "TEXT", "trackContentId": sub_url,
                                    "trackContentType": "text/vtt", "subtype": "SUBTITLES", "language": "es",
                                    "name": "Subtítulos"}]
                req["activeTrackIds"] = [1]
            resp = self._c().request(CAST_NS_MEDIA, req, tid, timeout=45)
            if resp.get("type") != "MEDIA_STATUS":
                raise ProyectarError(f"El Chromecast no pudo abrir el video ({resp.get('type')}). "
                                     "Prueba el modo Compatible.")
            st = (resp.get("status") or [{}])[0]
            self._session = st.get("mediaSessionId")
            self._last, self._last_at = st, time.monotonic()

    def _media(self, kind: str, **extra) -> dict:
        with self._lock:
            tid = self._transport if self._conn and not self._conn.closed else None
            tid = tid or self._attach(launch=False)
            if not tid or self._session is None:
                self._status()
                tid = self._transport
            if not tid or self._session is None:
                raise ProyectarError("No hay nada reproduciéndose en el Chromecast.")
            resp = self._c().request(CAST_NS_MEDIA, dict({"type": kind, "mediaSessionId": self._session}, **extra), tid)
            st = (resp.get("status") or [None])[0]
            if st:
                self._last, self._last_at = st, time.monotonic()
            return resp

    def play(self) -> None:
        self._media("PLAY")

    def pause(self) -> None:
        self._media("PAUSE")

    def seek(self, seconds: float) -> None:
        self._media("SEEK", currentTime=float(seconds), resumeState="PLAYBACK_START")

    def stop(self) -> None:
        if self._conn is None or self._session is None:
            return  # no hay nada nuestro reproduciéndose
        try:
            self._media("STOP")
        except ProyectarError:
            pass
        self._session = None

    def _status(self) -> Optional[dict]:
        with self._lock:
            tid = self._attach(launch=False)
            if not tid:
                self._last = None
                return None
            resp = self._c().request(CAST_NS_MEDIA, {"type": "GET_STATUS"}, tid, timeout=5)
            st = (resp.get("status") or [None])[0]
            if st:
                self._session = st.get("mediaSessionId", self._session)
            self._last, self._last_at = st, time.monotonic()
            return st

    def transport_state(self) -> str:
        st = self._status()
        if not st:
            return "NO_MEDIA_PRESENT"
        return {"PLAYING": "PLAYING", "PAUSED": "PAUSED_PLAYBACK", "BUFFERING": "TRANSITIONING",
                "LOADING": "TRANSITIONING"}.get(st.get("playerState"), "STOPPED")

    def position(self) -> Tuple[Optional[float], Optional[float]]:
        st = self._last if time.monotonic() - self._last_at < 1.5 else self._status()
        if not st:
            return None, None
        return st.get("currentTime"), (st.get("media") or {}).get("duration")

    def get_volume(self) -> int:
        st = self._c().request(CAST_NS_RECEIVER, {"type": "GET_STATUS"}).get("status") or {}
        return int(round(float((st.get("volume") or {}).get("level", 1)) * 100))

    def set_volume(self, value: int) -> None:
        level = max(0, min(100, int(value))) / 100
        self._c().request(CAST_NS_RECEIVER, {"type": "SET_VOLUME", "volume": {"level": level}})


def discover_cast(timeout: float = 2.5, hosts: Optional[List[str]] = None) -> List[CastRenderer]:
    found: Dict[str, CastRenderer] = {}
    for svc in mdns_browse(CAST_SERVICE, timeout, hosts):
        if not svc.get("host"):
            continue
        t = svc.get("txt") or {}
        name = t.get("fn") or svc["name"].split("._googlecast")[0]
        r = CastRenderer(name, svc["host"], svc.get("port") or 8009, model=t.get("md", ""), udn=t.get("id", ""))
        found.setdefault(r.key, r)
    if hosts and not found:  # sin mDNS: probar si hay un Chromecast escuchando en esa IP
        for h in hosts:
            try:
                socket.create_connection((h, 8009), timeout=1.5).close()
                found[h] = CastRenderer(f"Chromecast {h}", h)
            except OSError:
                pass
    return list(found.values())


def discover(timeout: float = 3.0, hosts: Optional[List[str]] = None) -> list:
    """Busca en la red todo lo que pueda reproducir video: DLNA y Chromecast."""
    results: Dict[str, list] = {}

    def run(name, fn):
        try:
            results[name] = fn(timeout=timeout, hosts=hosts)
        except Exception as e:  # una búsqueda que falla no debe arruinar la otra
            log.debug("Búsqueda %s falló: %s", name, e)
            results[name] = []
    threads = [threading.Thread(target=run, args=(n, f), daemon=True)
               for n, f in (("dlna", discover_dlna), ("cast", discover_cast))]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout + 8)
    found = results.get("dlna", []) + results.get("cast", [])
    found.sort(key=lambda r: (r.name.lower(), r.kind))
    log.info("Encontrados: %s", ", ".join(r.label for r in found) or "ninguno")
    return found


# ---------------------------------------------------------------------------
# Servidor HTTP que entrega el video al proyector
# ---------------------------------------------------------------------------

FILE_FEATURES = "DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000"
LIVE_FEATURES = "DLNA.ORG_OP=00;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=01700000000000000000000000000000"

MIME_TYPES = {
    ".mp4": "video/mp4", ".m4v": "video/mp4", ".mkv": "video/x-matroska", ".webm": "video/webm",
    ".avi": "video/x-msvideo", ".mov": "video/quicktime", ".wmv": "video/x-ms-wmv",
    ".asf": "video/x-ms-asf", ".flv": "video/x-flv", ".mpg": "video/mpeg", ".mpeg": "video/mpeg",
    ".ts": "video/mpeg", ".m2ts": "video/mpeg", ".mts": "video/mpeg", ".vob": "video/mpeg",
    ".3gp": "video/3gpp", ".ogv": "video/ogg",
    ".mp3": "audio/mpeg", ".m4a": "audio/mp4", ".flac": "audio/flac", ".wav": "audio/wav",
    ".ogg": "audio/ogg", ".srt": "text/srt", ".ass": "text/x-ass", ".ssa": "text/x-ssa",
    ".vtt": "text/vtt",
}
VIDEO_EXTS = ("*.mp4 *.mkv *.avi *.mov *.wmv *.m4v *.webm *.ts *.m2ts *.mts *.mpg *.mpeg "
              "*.flv *.3gp *.vob *.ogv")
SUB_EXTS = (".srt", ".ass", ".ssa", ".vtt")


def mime_for(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    return MIME_TYPES.get(ext) or mimetypes.guess_type(path)[0] or "application/octet-stream"


class FileMedia:
    """Un archivo del disco, con soporte de saltos (Range) para poder adelantar."""
    live = False

    def __init__(self, path: str, mime: Optional[str] = None, transfer: str = "Streaming"):
        self.path = path
        self.mime = mime or mime_for(path)
        self.name = "video" + (os.path.splitext(path)[1].lower() or ".bin")
        self.features = FILE_FEATURES
        self.transfer = transfer
        self.headers: Dict[str, str] = {}
        self.requests = 0
        self.last_error: Optional[str] = None

    @property
    def size(self) -> Optional[int]:
        try:
            return os.path.getsize(self.path)
        except OSError:
            return None

    def close(self) -> None:
        pass

    def serve(self, h: BaseHTTPRequestHandler, head: bool) -> None:
        size = self.size
        if size is None:
            h.send_error(404)
            return
        start, end, status = 0, size - 1, 200
        rng = h.headers.get("Range")
        m = re.fullmatch(r"\s*bytes\s*=\s*(\d*)\s*-\s*(\d*)\s*(?:,.*)?", rng or "")
        if m and (m.group(1) or m.group(2)):
            if m.group(1):
                start = int(m.group(1))
                end = min(int(m.group(2)), size - 1) if m.group(2) else size - 1
            else:  # "bytes=-500": los últimos 500 bytes
                start, end = max(0, size - int(m.group(2))), size - 1
            if start >= size or start > end:
                h.send_response(416)
                h.send_header("Content-Range", f"bytes */{size}")
                h.send_header("Content-Length", "0")
                h.end_headers()
                return
            status = 206
        length = end - start + 1
        h.send_response(status)
        h.send_header("Content-Type", self.mime)
        h.send_header("Content-Length", str(length))
        h.send_header("Accept-Ranges", "bytes")
        if status == 206:
            h.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        h.send_header("transferMode.dlna.org", self.transfer)
        h.send_header("contentFeatures.dlna.org", self.features)
        h.send_header("Access-Control-Allow-Origin", "*")
        for key, value in self.headers.items():
            h.send_header(key, value)
        h.end_headers()
        if head:
            return
        with open(self.path, "rb") as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                chunk = f.read(min(256 * 1024, remaining))
                if not chunk:
                    break
                h.wfile.write(chunk)
                remaining -= len(chunk)


class FFmpegProcess:
    """ffmpeg corriendo en segundo plano; su salida es el video que va al proyector."""

    def __init__(self, args: List[str], feeder: Optional[Callable] = None):
        log.debug("ffmpeg: %s", subprocess.list2cmdline(args))
        self.tail: collections.deque = collections.deque(maxlen=20)
        self._stop = threading.Event()
        self.proc = subprocess.Popen(
            args,
            stdin=subprocess.PIPE if feeder else subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            creationflags=NO_WINDOW,
        )
        threading.Thread(target=self._read_stderr, daemon=True).start()
        if feeder:
            threading.Thread(target=self._feed, args=(feeder,), daemon=True).start()

    def _read_stderr(self):
        try:
            for raw in iter(self.proc.stderr.readline, b""):
                line = raw.decode("utf-8", "replace").rstrip()
                if line:
                    self.tail.append(line)
                    log.debug("ffmpeg> %s", line)
        except (OSError, ValueError):
            pass
        finally:
            self.proc.stderr.close()

    def _feed(self, feeder):
        try:
            feeder(self.proc.stdin, self._stop)
        except (OSError, ValueError):
            pass  # ffmpeg terminó
        except Exception:
            log.exception("Error capturando el sonido")
        finally:
            try:
                self.proc.stdin.close()
            except OSError:
                pass

    def read(self, n: int = 64 * 1024) -> bytes:
        try:
            return self.proc.stdout.read1(n)
        except (OSError, ValueError):
            return b""

    @property
    def error(self) -> str:
        return "\n".join(self.tail)

    def close(self) -> None:
        self._stop.set()
        if self.proc.poll() is None:
            try:
                self.proc.terminate()
                self.proc.wait(3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                try:
                    self.proc.wait(3)
                except subprocess.TimeoutExpired:
                    pass
            except OSError:
                pass
        for stream in (self.proc.stdout, self.proc.stdin):
            try:
                if stream:
                    stream.close()
            except OSError:
                pass


class LiveMedia:
    """Video generado en vivo por ffmpeg (conversión o captura de pantalla).

    `commands` son alternativas que se prueban en orden hasta que una funcione
    (por ejemplo: captura de pantalla moderna y, si falla, la clásica)."""
    live = True

    def __init__(self, name: str, mime: str, commands: List[Callable[[], FFmpegProcess]]):
        self.name = name
        self.mime = mime
        self.commands = commands
        self.features = LIVE_FEATURES
        self.headers: Dict[str, str] = {}
        self.requests = 0
        self.last_error: Optional[str] = None
        self._good = 0
        self._procs: set = set()
        self._lock = threading.Lock()
        self._closed = False

    def _open(self) -> Tuple[Optional[FFmpegProcess], bytes]:
        order = [self._good] + [i for i in range(len(self.commands)) if i != self._good]
        for i in order:
            try:
                proc = self.commands[i]()
            except ProyectarError as e:
                self.last_error = str(e)
                continue
            except OSError as e:
                self.last_error = f"No se pudo ejecutar ffmpeg: {e}"
                continue
            first = proc.read()
            if first:
                self._good = i
                self.last_error = None
                return proc, first
            proc.close()
            self.last_error = proc.error or "ffmpeg terminó sin generar video"
            log.warning("ffmpeg falló (opción %d): %s", i + 1, self.last_error)
        return None, b""

    def serve(self, h: BaseHTTPRequestHandler, head: bool) -> None:
        proc, first = (None, b"") if head else self._open()
        if not head and proc is None:
            h.send_error(500, "ffmpeg no pudo generar el video")
            return
        h.send_response(200)
        h.send_header("Content-Type", self.mime)
        h.send_header("transferMode.dlna.org", "Streaming")
        h.send_header("contentFeatures.dlna.org", self.features)
        h.send_header("Cache-Control", "no-cache")
        h.send_header("Access-Control-Allow-Origin", "*")
        h.send_header("Connection", "close")
        h.end_headers()
        h.close_connection = True
        if head:
            return
        with self._lock:
            if self._closed:
                proc.close()
                return
            self._procs.add(proc)
        try:
            chunk = first
            while chunk:
                h.wfile.write(chunk)
                chunk = proc.read()
            if proc.proc.poll() not in (None, 0) and proc.error and not self._closed:
                self.last_error = proc.error
                log.warning("ffmpeg se detuvo: %s", proc.error)
        finally:
            proc.close()
            with self._lock:
                self._procs.discard(proc)

    def close(self) -> None:
        with self._lock:
            self._closed = True
            procs = list(self._procs)
        for p in procs:
            p.close()


class _Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = os.name != "nt"  # en Windows permitiría dos servidores en el mismo puerto

    def handle_error(self, request, client_address):
        exc = sys.exc_info()[1]
        if isinstance(exc, (ConnectionError, TimeoutError)):
            return  # el proyector cortó la conexión: es normal
        log.debug("Error HTTP con %s", client_address, exc_info=True)


class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = f"{APP}/{VERSION} UPnP/1.0 DLNADOC/1.50"

    def log_message(self, fmt, *args):
        if "/b/" not in self.path:  # la página del navegador consulta muy seguido
            log.debug("http %s %s", self.client_address[0], fmt % args)

    def do_GET(self):
        self._serve(head=False)

    def do_HEAD(self):
        self._serve(head=True)

    def do_POST(self):
        if urllib.parse.urlsplit(self.path).path != "/b/reporte":
            self.send_error(404)
            return
        n = int(self.headers.get("Content-Length") or 0)
        try:
            data = json.loads(self.rfile.read(min(n, 65536)) or b"{}")
        except ValueError:
            data = {}
        self.server.hub.set_report(data)
        self._bytes(b"{}", "application/json", head=False)

    def _bytes(self, body: bytes, ctype: str, head: bool):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if not head:
            self.wfile.write(body)

    def _serve(self, head: bool):
        url = urllib.parse.urlsplit(self.path)
        if url.path in ("/", "/index.html"):
            self._bytes(PAGE_HTML.encode("utf-8"), "text/html; charset=utf-8", head)
            return
        if url.path == "/b/estado":
            q = urllib.parse.parse_qs(url.query)
            try:
                since = int((q.get("desde") or ["0"])[0])
            except ValueError:
                since = 0
            self._bytes(json.dumps(self.server.hub.pending(since)).encode(), "application/json", head)
            return
        parts = url.path.split("/")
        media = self.server.routes.get(parts[2]) if len(parts) >= 3 and parts[1] == "m" else None
        if media is None:
            self.send_error(404)
            return
        if not head:
            media.requests += 1
            level = logging.INFO if media.requests == 1 else logging.DEBUG
            log.log(level, "El proyector (%s) pidió %s %s", self.client_address[0], media.name,
                    self.headers.get("Range", ""))
        try:
            media.serve(self, head)
        except (ConnectionError, TimeoutError):
            pass  # el proyector cerró la conexión (por ejemplo al adelantar)


class MediaServer:
    """Pequeño servidor web: el proyector descarga el video desde acá."""

    def __init__(self, port: int = HTTP_PORT):
        self.routes: Dict[str, object] = {}
        last = None
        for p in (port, 0):  # si el puerto está ocupado, cualquiera libre
            try:
                self.httpd = _Server(("0.0.0.0", p), _Handler)
                break
            except OSError as e:
                last = e
        else:
            raise ProyectarError(f"No se pudo abrir el servidor de video: {last}")
        self.httpd.routes = self.routes
        self.hub = self.httpd.hub = BrowserHub()
        self.port = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True, name="http").start()
        log.debug("Servidor de video en el puerto %d", self.port)

    def add(self, media) -> str:
        token = uuid.uuid4().hex[:12]
        self.routes[token] = media
        return f"/m/{token}/{urllib.parse.quote(media.name)}"

    def clear(self) -> None:
        for media in list(self.routes.values()):
            media.close()
        self.routes.clear()

    def close(self) -> None:
        self.clear()
        self.httpd.shutdown()
        self.httpd.server_close()


# ---------------------------------------------------------------------------
# Navegador del proyector: sirve con cualquier equipo que tenga navegador web
# ---------------------------------------------------------------------------

# Página que se abre en el proyector. JavaScript "viejo" (ES5) a propósito,
# para que funcione también en navegadores antiguos de proyectores y TVs.
PAGE_HTML = """<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Proyectar</title>
<style>
html,body{margin:0;height:100%;background:#000;color:#e8e8e8;font-family:"Segoe UI",Roboto,Arial,sans-serif;overflow:hidden}
#v{position:fixed;top:0;left:0;width:100%;height:100%;background:#000}
#panel{position:fixed;top:0;left:0;right:0;bottom:0;display:flex;flex-direction:column;align-items:center;
 justify-content:center;text-align:center;background:#000}
h1{font-size:3.4em;margin:0 0 .3em;font-weight:600;letter-spacing:.02em}
#msg{font-size:1.7em;color:#b0b0b0;max-width:80%;line-height:1.4}
#go{margin-top:1.3em;font-size:2em;padding:.5em 1.4em;border:0;border-radius:14px;background:#2f7cf6;color:#fff;cursor:pointer}
#go:focus{outline:5px solid #fff;outline-offset:4px}
</style></head><body>
<video id="v" playsinline></video>
<div id="panel"><h1>Proyectar</h1><div id="msg">Conectado. Elige una película en la PC.</div>
<button id="go" autofocus>&#9654; Pulsa OK para empezar</button></div>
<script>
(function(){
var v=document.getElementById('v'),panel=document.getElementById('panel'),
    msg=document.getElementById('msg'),go=document.getElementById('go');
var seq=0,armed=false,cur=null,IDLE='Conectado. Elige una película en la PC.';
function show(p){panel.style.display=p?'flex':'none';}
function ask(t){msg.textContent=t;go.style.display='inline-block';show(true);go.focus();}
function fs(){var e=document.documentElement,f=e.requestFullscreen||e.webkitRequestFullscreen;
 if(f){try{f.call(e);}catch(x){}}}
function play(){var p=v.play();if(p&&p['catch']){p['catch'](function(){
 ask('Pulsa OK para ver «'+(cur?cur.title:'')+'»');});}}
go.onclick=function(){armed=true;go.style.display='none';fs();
 if(cur){show(false);play();}else{msg.textContent=IDLE;}};
function run(c){
 if(c.cmd==='load'){cur=c;v.innerHTML='';v.src=c.src;
  if(c.sub){var t=document.createElement('track');t.kind='subtitles';t.src=c.sub;t.srclang='es';
   t['default']=true;v.appendChild(t);}
  v.load();if(armed){show(false);play();}else{ask('Pulsa OK para ver «'+c.title+'»');}}
 else if(c.cmd==='play'){if(cur){show(false);play();}}
 else if(c.cmd==='pause'){v.pause();}
 else if(c.cmd==='seek'){try{v.currentTime=c.t;}catch(x){}}
 else if(c.cmd==='volume'){v.volume=Math.max(0,Math.min(1,c.v));}
 else if(c.cmd==='stop'){cur=null;v.pause();v.removeAttribute('src');v.innerHTML='';v.load();
  msg.textContent=IDLE;go.style.display=armed?'none':'inline-block';show(true);}
}
function xhr(m,u,b,cb){var r=new XMLHttpRequest();r.open(m,u,true);
 r.onreadystatechange=function(){if(r.readyState===4&&cb){cb(r.status===200?r.responseText:null);}};
 if(b){r.setRequestHeader('Content-Type','application/json');r.send(b);}else{r.send();}}
function report(){xhr('POST','/b/reporte',JSON.stringify({t:v.currentTime||0,
 d:isFinite(v.duration)?v.duration:null,paused:v.paused,ended:v.ended,vol:v.volume,
 err:v.error?v.error.code:null,src:!!cur,armed:armed}),null);}
function poll(){xhr('GET','/b/estado?desde='+seq+'&_='+(new Date()).getTime(),null,function(t){
 if(t){try{var d=JSON.parse(t);for(var i=0;i<d.cmds.length;i++){run(d.cmds[i]);}seq=d.seq;}catch(x){}}
 report();setTimeout(poll,700);});}
v.onerror=function(){if(cur){ask('Este navegador no puede reproducir el video. En la PC usa el modo Compatible.');}};
v.onended=function(){msg.textContent='Terminó.';show(true);};
document.onkeydown=function(e){var k=e.keyCode;
 if(!cur||panel.style.display!=='none'){return;}
 if(k===13||k===32||k===179||k===85||k===415||k===19){if(v.paused){play();}else{v.pause();}}};
poll();
})();
</script></body></html>
"""


class BrowserHub:
    """Cola de órdenes para la página abierta en el navegador del proyector."""

    def __init__(self):
        self.lock = threading.Lock()
        self.cmds: List[dict] = []
        self.seq = 0
        self.report: dict = {}
        self.seen = 0.0

    def push(self, cmd: dict) -> None:
        with self.lock:
            self.seq += 1
            self.cmds.append(dict(cmd, seq=self.seq))
            del self.cmds[:-50]

    def pending(self, since: int) -> dict:
        with self.lock:
            self.seen = time.monotonic()
            if since <= 0 or since > self.seq:  # página recién abierta: desde el último video
                starts = [i for i, c in enumerate(self.cmds) if c["cmd"] in ("load", "stop")]
                cmds = self.cmds[starts[-1]:] if starts else []
            else:
                cmds = [c for c in self.cmds if c["seq"] > since]
            return {"seq": self.seq, "cmds": cmds}

    def set_report(self, data: dict) -> None:
        with self.lock:
            self.report = data if isinstance(data, dict) else {}
            self.seen = time.monotonic()

    @property
    def connected(self) -> bool:
        return time.monotonic() - self.seen < 6


class BrowserRenderer:
    """El navegador web del proyector, manejado desde la PC."""
    kind = "Navegador"
    live_format = "mp4"
    name = "Navegador del proyector"
    host = udn = manufacturer = model = ""
    location = key = "navegador"

    def __init__(self, hub: BrowserHub, page_url: Callable[[], str]):
        self.hub = hub
        self.page_url = page_url

    @property
    def label(self) -> str:
        return "Navegador del proyector  —  sirve con cualquier proyector con navegador web"

    @property
    def connected(self) -> bool:
        return self.hub.connected

    def prefers_compatible(self, path: str) -> bool:
        return os.path.splitext(path)[1].lower() not in (".mp4", ".m4v", ".webm")

    def load(self, url: str, mime: str, title: str, live: bool, features: str = "", duration=None,
             size=None, sub_url: Optional[str] = None, sub_mime: str = "") -> None:
        path = urllib.parse.urlsplit(url).path
        sub = urllib.parse.urlsplit(sub_url).path if sub_url else None
        self.hub.push({"cmd": "load", "src": path, "title": title, "live": live, "sub": sub})

    def play(self) -> None:
        self.hub.push({"cmd": "play"})

    def pause(self) -> None:
        self.hub.push({"cmd": "pause"})

    def stop(self) -> None:
        self.hub.push({"cmd": "stop"})

    def seek(self, seconds: float) -> None:
        self.hub.push({"cmd": "seek", "t": float(seconds)})

    def transport_state(self) -> str:
        rep = self.hub.report
        if not self.connected or not rep.get("src"):
            return "NO_MEDIA_PRESENT"
        if rep.get("ended") or rep.get("err"):
            return "STOPPED"
        return "PAUSED_PLAYBACK" if rep.get("paused") else "PLAYING"

    def position(self) -> Tuple[Optional[float], Optional[float]]:
        rep = self.hub.report
        return rep.get("t"), rep.get("d")

    def get_volume(self) -> int:
        return int(round(float(self.hub.report.get("vol", 1)) * 100))

    def set_volume(self, value: int) -> None:
        self.hub.push({"cmd": "volume", "v": max(0, min(100, int(value))) / 100})


def srt_to_vtt(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n").lstrip("﻿")
    if text.lstrip().startswith("WEBVTT"):
        return text
    return "WEBVTT\n\n" + re.sub(r"(\d{1,2}:\d{2}:\d{2}),(\d{3})", r"\1.\2", text)


class TextMedia:
    """Texto generado en memoria (por ejemplo, subtítulos convertidos a WebVTT)."""
    live = False

    def __init__(self, name: str, mime: str, data: bytes):
        self.name, self.mime, self.data = name, mime, data
        self.features = FILE_FEATURES
        self.headers: Dict[str, str] = {}
        self.requests = 0
        self.last_error: Optional[str] = None

    @property
    def size(self) -> int:
        return len(self.data)

    def close(self) -> None:
        pass

    def serve(self, h: BaseHTTPRequestHandler, head: bool) -> None:
        h.send_response(200)
        h.send_header("Content-Type", self.mime)
        h.send_header("Content-Length", str(len(self.data)))
        h.send_header("Access-Control-Allow-Origin", "*")
        h.end_headers()
        if not head:
            h.wfile.write(self.data)


def vtt_media(path: str) -> TextMedia:
    with open(path, "rb") as f:
        raw = f.read()
    enc = subtitle_charenc(path) or "utf-8-sig"
    text = raw.decode({"CP1252": "cp1252", "UTF-16": "utf-16"}.get(enc, enc), "replace")
    return TextMedia("subtitulos.vtt", "text/vtt", srt_to_vtt(text).encode("utf-8"))


# ---------------------------------------------------------------------------
# ffmpeg: búsqueda, análisis de archivos y armado de comandos
# ---------------------------------------------------------------------------

_ffmpeg_path: List[Optional[str]] = []
_caps_cache: Dict[str, Dict[str, bool]] = {}


def find_ffmpeg() -> Optional[str]:
    if _ffmpeg_path:
        return _ffmpeg_path[0]
    here = os.path.dirname(os.path.abspath(__file__))
    exe = "ffmpeg.exe" if os.name == "nt" else "ffmpeg"
    candidates = [os.environ.get("PROYECTAR_FFMPEG"), os.path.join(here, exe),
                  os.path.join(here, "ffmpeg", "bin", exe), os.path.join(here, "ffmpeg", exe),
                  shutil.which("ffmpeg")]
    found = next((c for c in candidates if c and os.path.isfile(c)), None)
    if not found:
        try:
            import imageio_ffmpeg  # pip install imageio-ffmpeg
            found = imageio_ffmpeg.get_ffmpeg_exe()
        except Exception:
            found = None
    log.debug("ffmpeg: %s", found or "no encontrado")
    _ffmpeg_path.append(found)
    return found


def require_ffmpeg() -> str:
    ff = find_ffmpeg()
    if not ff:
        raise ProyectarError(FFMPEG_HELP)
    return ff


def _run_text(args: List[str], timeout: float = 20) -> Tuple[str, str]:
    try:
        r = subprocess.run(args, capture_output=True, timeout=timeout, creationflags=NO_WINDOW,
                           stdin=subprocess.DEVNULL)
        return r.stdout.decode("utf-8", "replace"), r.stderr.decode("utf-8", "replace")
    except (OSError, subprocess.TimeoutExpired):
        return "", ""


def ffmpeg_caps(ff: str) -> Dict[str, bool]:
    """Qué sabe hacer este ffmpeg (no todas las versiones traen lo mismo)."""
    if ff not in _caps_cache:
        enc = _run_text([ff, "-hide_banner", "-encoders"])[0]
        flt = _run_text([ff, "-hide_banner", "-filters"])[0]

        def has(text, name):
            return re.search(rf"^\s*\S+\s+{name}\s", text, re.M) is not None

        _caps_cache[ff] = {
            "libx264": has(enc, "libx264"),
            "subtitles": has(flt, "subtitles"),
            "ddagrab": has(flt, "ddagrab"),
        }
        log.debug("Capacidades de ffmpeg: %s", _caps_cache[ff])
    return _caps_cache[ff]


TEXT_SUB_CODECS = {"subrip", "srt", "ass", "ssa", "mov_text", "webvtt", "text", "subviewer", "microdvd"}
IMAGE_SUB_CODECS = {"hdmv_pgs_subtitle", "pgssub", "dvd_subtitle", "dvdsub", "dvb_subtitle", "dvbsub"}
HARD_AUDIO = {"ac3", "eac3", "dts", "truehd", "mlp", "dca"}
HARD_VIDEO = {"hevc", "av1", "vp9", "mpeg4", "msmpeg4v3", "vc1", "wmv3"}
LANGS = {
    "spa": "Español", "es": "Español", "eng": "Inglés", "en": "Inglés", "por": "Portugués",
    "pt": "Portugués", "fre": "Francés", "fra": "Francés", "fr": "Francés", "ita": "Italiano",
    "it": "Italiano", "ger": "Alemán", "deu": "Alemán", "de": "Alemán", "jpn": "Japonés",
    "ja": "Japonés", "kor": "Coreano", "chi": "Chino", "zho": "Chino", "rus": "Ruso",
    "cat": "Catalán", "glg": "Gallego", "eus": "Euskera", "baq": "Euskera",
}


@dataclass
class Stream:
    index: int          # número global de pista dentro del archivo
    kind: str           # video / audio / subtitle
    codec: str
    type_index: int     # número dentro de su tipo (0:a:N)
    lang: str = ""
    title: str = ""
    detail: str = ""
    default: bool = False

    @property
    def size(self) -> Tuple[Optional[int], Optional[int]]:
        m = re.search(r"\b(\d{2,5})x(\d{2,5})\b", self.detail)
        return (int(m.group(1)), int(m.group(2))) if m else (None, None)

    @property
    def pix_fmt(self) -> str:
        m = re.search(r"\b(yuvj?\d{3}p\w*|nv12|p010\w*|rgb\w*|bgr\w*|gray\w*)", self.detail)
        return m.group(1) if m else ""

    @property
    def channels(self) -> str:
        m = re.search(r"\b(mono|stereo|quad|\d\.\d(?:\(\w+\))?|\d+ channels)", self.detail)
        return m.group(1) if m else ""

    @property
    def is_cover(self) -> bool:
        return "attached pic" in self.detail

    @property
    def language(self) -> str:
        if not self.lang or self.lang == "und":
            return ""
        return LANGS.get(self.lang.lower(), self.lang)

    def label(self, n: int) -> str:
        name = self.title or self.language or "Pista"
        if self.title and self.language and self.language.lower() not in self.title.lower():
            name += f" ({self.language})"
        codec = self.codec.upper().replace("HDMV_PGS_SUBTITLE", "PGS").replace("SUBRIP", "SRT")
        extra = f" {self.channels}" if self.kind == "audio" and self.channels else ""
        mark = " ★" if self.default else ""
        return f"{n}. {name} – {codec}{extra}{mark}"


@dataclass
class MediaInfo:
    duration: Optional[float] = None
    streams: List[Stream] = field(default_factory=list)

    def of(self, kind: str) -> List[Stream]:
        return [s for s in self.streams if s.kind == kind and not s.is_cover]

    @property
    def video(self) -> Optional[Stream]:
        v = self.of("video")
        return v[0] if v else None

    @property
    def audios(self) -> List[Stream]:
        return self.of("audio")

    @property
    def subtitles(self) -> List[Stream]:
        return self.of("subtitle")

    @property
    def default_audio(self) -> Optional[Stream]:
        return next((a for a in self.audios if a.default), None) or (self.audios[0] if self.audios else None)


_STREAM_RE = re.compile(
    r"^\s*Stream #0:(\d+)(?:\[0x[0-9a-fA-F]+\])?(?:\(([^)]*)\))?(?:\[0x[0-9a-fA-F]+\])?:\s*"
    r"(Video|Audio|Subtitle|Data|Attachment):\s*([^\s,]+)(.*)$"
)


def parse_probe(text: str) -> MediaInfo:
    """Interpreta lo que ffmpeg muestra con `ffmpeg -i archivo`."""
    info = MediaInfo()
    m = re.search(r"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)", text)
    if m:
        info.duration = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))
    counters: Dict[str, int] = collections.Counter()
    current: Optional[Stream] = None
    for line in text.splitlines():
        sm = _STREAM_RE.match(line)
        if sm:
            kind = sm.group(3).lower()
            current = Stream(index=int(sm.group(1)), kind=kind, codec=sm.group(4).lower(),
                             type_index=counters[kind], lang=(sm.group(2) or "").strip(),
                             detail=sm.group(5), default="(default)" in sm.group(5))
            counters[kind] += 1
            info.streams.append(current)
            continue
        if current is not None:
            tm = re.match(r"^\s+title\s*:\s*(.+)$", line)
            if tm and not current.title:
                current.title = tm.group(1).strip()
            elif re.match(r"^\S", line):  # terminó el bloque de la pista
                current = None
    return info


def probe(path: str) -> MediaInfo:
    ff = find_ffmpeg()
    if not ff:
        return MediaInfo()
    return parse_probe(_run_text([ff, "-hide_banner", "-nostdin", "-i", path], timeout=40)[1])


def find_external_subs(video_path: str) -> List[str]:
    """Subtítulos con el mismo nombre que la película (peli.srt, peli.es.srt, ...)."""
    folder = os.path.dirname(os.path.abspath(video_path))
    base = os.path.splitext(os.path.basename(video_path))[0].lower()
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return []
    out = []
    for name in names:
        stem, ext = os.path.splitext(name)
        if ext.lower() in SUB_EXTS and (stem.lower() == base or stem.lower().startswith(base + ".")):
            out.append(os.path.join(folder, name))
    return out


def subtitle_charenc(path: str) -> Optional[str]:
    """Muchos .srt en español vienen en Windows-1252 en vez de UTF-8."""
    try:
        with open(path, "rb") as f:
            data = f.read(4_000_000)
    except OSError:
        return None
    if data.startswith(codecs.BOM_UTF8):
        return None
    if data[:2] in (codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE):
        return "UTF-16"
    try:
        data.decode("utf-8")
        return None
    except UnicodeDecodeError:
        return "CP1252"


def ffmpeg_filter_quote(value: str) -> str:
    """Escapa un valor para una opción de filtro de ffmpeg (ffmpeg lo desescapa dos veces)."""
    level2 = "'" + value.replace("'", r"'\''") + "'"
    return re.sub(r"([\\'\[\],;])", r"\\\1", level2)


def subtitles_filter(sub_file: str) -> str:
    path = sub_file.replace("\\", "/") if os.name == "nt" else sub_file
    opt = "filename=" + ffmpeg_filter_quote(path)
    enc = subtitle_charenc(sub_file)
    if enc:
        opt += ":charenc=" + enc
    return "subtitles=" + opt


def video_encoder_args(caps: Dict[str, bool], crf: int, maxrate_mbps: int, zerolatency: bool = False) -> List[str]:
    if caps.get("libx264"):
        args = ["-c:v", "libx264", "-preset", "veryfast", "-crf", str(crf),
                "-maxrate", f"{maxrate_mbps}M", "-bufsize", f"{maxrate_mbps * 2}M", "-profile:v", "high"]
        if zerolatency:
            args += ["-tune", "zerolatency"]
        return args
    # ffmpeg sin H.264: MPEG-2, que cualquier proyector reproduce
    return ["-c:v", "mpeg2video", "-q:v", "3", "-maxrate", f"{maxrate_mbps * 2}M", "-bufsize", "8M"]


LIVE_FORMATS = {  # contenedor: (nombre del archivo, tipo MIME)
    "ts": ("video/mpeg", ".ts"),      # DLNA
    "mp4": ("video/mp4", ".mp4"),     # Chromecast y navegadores (MP4 fragmentado)
}


def output_args(container: str) -> List[str]:
    if container == "mp4":
        return ["-f", "mp4", "-movflags", "frag_keyframe+empty_moov+default_base_moof",
                "-frag_duration", "1000000", "pipe:1"]
    return ["-f", "mpegts", "-mpegts_flags", "+resend_headers", "pipe:1"]


def build_transcode_args(ff: str, path: str, info: MediaInfo, offset: float = 0.0,
                         audio: Optional[Stream] = None, sub_file: Optional[str] = None,
                         sub_stream: Optional[Stream] = None, caps: Optional[Dict[str, bool]] = None,
                         max_height: int = 1080, container: str = "ts") -> List[str]:
    """Comando ffmpeg que convierte la película en vivo a H.264 + AAC."""
    caps = caps if caps is not None else ffmpeg_caps(ff)
    if sub_file and not caps.get("subtitles"):
        raise ProyectarError("Este ffmpeg no puede dibujar subtítulos de texto (le falta libass).")
    args = [ff, "-hide_banner", "-nostdin", "-loglevel", "error"]
    if offset > 0:
        args += ["-ss", f"{offset:.3f}"]
    args += ["-i", path]

    v = info.video
    unknown = not info.streams  # no se pudo analizar: convertimos todo por las dudas
    if v or unknown:
        vmap = f"0:v:{v.type_index}" if v else "0:v:0"
        height = v.size[1] if v else None
        copy = (v is not None and v.codec == "h264" and v.pix_fmt in ("yuv420p", "yuvj420p")
                and not sub_file and sub_stream is None and (height or 0) <= max_height)
        if copy:  # el video ya es compatible: sólo se convierte el audio (casi no usa CPU)
            args += ["-map", vmap, "-c:v", "copy"]
        else:
            if sub_stream is not None:  # subtítulos de imagen (Blu-ray/DVD): se superponen
                graph, chain = f"[{vmap}][0:s:{sub_stream.type_index}]overlay=(W-w)/2:H-h", []
            else:
                graph, chain = f"[{vmap}]", []
            if sub_file:
                if offset > 0:  # los subtítulos necesitan los tiempos originales
                    chain.append(f"setpts=PTS+{offset:.3f}/TB")
                chain.append(subtitles_filter(sub_file))
                if offset > 0:
                    chain.append("setpts=PTS-STARTPTS")
            if height and height > max_height:
                chain.append(f"scale=-2:{max_height}")
            chain.append("format=yuv420p")
            graph += ("," if sub_stream is not None else "") + ",".join(chain) + "[v]"
            args += ["-filter_complex", graph, "-map", "[v]"]
            args += video_encoder_args(caps, crf=20, maxrate_mbps=15) + ["-g", "48"]
    if info.audios or unknown:
        amap = f"0:a:{(audio or info.default_audio).type_index}" if info.audios else "0:a:0?"
        args += ["-map", amap, "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-ar", "48000"]
    return args + output_args(container)


# --- captura de pantalla y sonido ---

LOOPBACK_HINTS = ("stereo mix", "mezcla est", "what u hear", "loopback", "cable output",
                  "virtual-audio-capturer", "voicemeeter", "wave out", "monitor")


def soundcard_available() -> bool:
    try:
        import soundcard  # noqa: F401  (pip install soundcard)
        return True
    except Exception:
        return False


def dshow_audio_devices(ff: str) -> List[str]:
    return parse_dshow_devices(_run_text([ff, "-hide_banner", "-list_devices", "true", "-f", "dshow", "-i", "dummy"])[1])


def parse_dshow_devices(err: str) -> List[str]:
    """Dispositivos de audio de Windows (los que capturan 'lo que suena' primero)."""
    names, section = [], None
    for line in err.splitlines():
        if "DirectShow audio devices" in line:
            section = "audio"
            continue
        if "DirectShow video devices" in line:
            section = "video"
            continue
        if "Alternative name" in line:
            continue
        m = re.search(r'"([^"]+)"(?:\s+\(([^)]*)\))?', line)
        if m and ((m.group(2) and "audio" in m.group(2)) or (not m.group(2) and section == "audio")):
            if m.group(1) not in names:
                names.append(m.group(1))
    return sorted(names, key=lambda n: not any(h in n.lower() for h in LOOPBACK_HINTS))


def pulse_monitor() -> Optional[str]:
    out = _run_text(["pactl", "get-default-sink"], timeout=5)[0].strip()
    if not out:
        m = re.search(r"Default Sink:\s*(\S+)", _run_text(["pactl", "info"], timeout=5)[0])
        out = m.group(1) if m else ""
    return out + ".monitor" if out else None


def avfoundation_audio_devices(ff: str) -> List[str]:
    return parse_avfoundation_devices(
        _run_text([ff, "-hide_banner", "-f", "avfoundation", "-list_devices", "true", "-i", ""])[1])


def parse_avfoundation_devices(err: str) -> List[str]:
    names, audio = [], False
    for line in err.splitlines():
        if "audio devices" in line:
            audio = True
            continue
        m = re.search(r"\]\s*\[(\d+)\]\s*(.+)$", line)
        if audio and m:
            names.append(m.group(2).strip())
    return names


def audio_sources(ff: Optional[str]) -> List[Tuple[str, Optional[tuple]]]:
    """Opciones de sonido para el modo Pantalla: [(texto, especificación)]."""
    opts: List[Tuple[str, Optional[tuple]]] = []
    if ff:
        if os.name == "nt":
            if soundcard_available():
                opts.append(("Sonido de la PC (automático)", ("loopback",)))
            opts += [(name, ("dshow", name)) for name in dshow_audio_devices(ff)]
        elif sys.platform == "darwin":
            opts += [(name, ("avfoundation", name)) for name in avfoundation_audio_devices(ff)]
        else:
            mon = pulse_monitor()
            if mon:
                opts.append(("Sonido de la PC", ("pulse", mon)))
    opts.append(("Sin sonido", None))
    return opts


def pace_audio(get_chunk: Callable[[float], Optional[bytes]], write: Callable[[bytes], object],
               stop: threading.Event, rate: int = 48000, channels: int = 2,
               clock: Callable[[], float] = time.monotonic, max_drift: float = 0.12) -> None:
    """Entrega audio a ffmpeg al ritmo del reloj real.

    Windows no entrega nada mientras la PC está en silencio; si no rellenamos,
    ffmpeg esperaría el audio y el video se congelaría. También descarta audio
    si la placa de sonido corre más rápido que el reloj, para no desincronizar."""
    frame = 4 * channels  # float32
    limit = int(max_drift * rate)
    start = clock()
    written = 0
    while not stop.is_set():
        chunk = get_chunk(0.02)
        due = int((clock() - start) * rate)
        if chunk:
            n = len(chunk) // frame
            if written + n <= due + limit:
                write(chunk[: n * frame])
                written += n
        gap = due - written
        if gap > limit:
            n = gap - limit // 2
            write(bytes(n * frame))
            written += n


def loopback_feeder(stdin, stop: threading.Event, rate: int = 48000, channels: int = 2) -> None:
    """Captura 'lo que suena' en la PC (WASAPI loopback) y se lo pasa a ffmpeg."""
    chunks: queue.Queue = queue.Queue(maxsize=100)
    block = rate // 100  # 10 ms

    def capture():
        try:
            if os.name == "nt":
                import ctypes
                ctypes.windll.ole32.CoInitializeEx(None, 0)
            import warnings
            warnings.filterwarnings("ignore", message=".*discontinuity.*")
            import numpy as np
            import soundcard as sc
            mic = sc.get_microphone(id=str(sc.default_speaker().name), include_loopback=True)
            with mic.recorder(samplerate=rate, channels=channels, blocksize=block) as rec:
                while not stop.is_set():
                    data = rec.record(numframes=block)
                    try:
                        chunks.put_nowait(np.ascontiguousarray(data, dtype=np.float32).tobytes())
                    except queue.Full:
                        pass
        except Exception:
            log.exception("No se pudo capturar el sonido de la PC")

    threading.Thread(target=capture, daemon=True, name="audio").start()

    def get(timeout):
        try:
            return chunks.get(timeout=timeout)
        except queue.Empty:
            return None

    def write(data):
        stdin.write(data)
        stdin.flush()

    pace_audio(get, write, stop, rate, channels)


def screen_commands(ff: str, caps: Dict[str, bool], height: int = 1080, fps: int = 30,
                    audio: Optional[tuple] = None, container: str = "ts") -> List[Tuple[List[str], Optional[Callable]]]:
    """Comandos ffmpeg para capturar la pantalla (+ sonido), de mejor a peor opción."""
    a_in: List[str] = []
    feeder = None
    if audio:
        kind = audio[0]
        if kind == "loopback":
            a_in = ["-f", "f32le", "-ar", "48000", "-ac", "2", "-i", "pipe:0"]
            feeder = loopback_feeder
        elif kind == "dshow":
            a_in = ["-f", "dshow", "-audio_buffer_size", "50", "-i", f"audio={audio[1]}"]
        elif kind == "pulse":
            a_in = ["-f", "pulse", "-i", audio[1]]
        elif kind == "avfoundation":
            a_in = ["-f", "avfoundation", "-i", f":{audio[1]}"]
        a_in = ["-thread_queue_size", "1024"] + a_in

    if os.name == "nt":
        video_inputs = []
        if caps.get("ddagrab"):  # Desktop Duplication: rápido y respeta el escalado de Windows
            video_inputs.append(["-f", "lavfi", "-i",
                                 f"ddagrab=output_idx=0:framerate={fps}:draw_mouse=1,hwdownload,format=bgra"])
        video_inputs.append(["-f", "gdigrab", "-framerate", str(fps), "-draw_mouse", "1", "-i", "desktop"])
    elif sys.platform == "darwin":
        video_inputs = [["-f", "avfoundation", "-framerate", str(fps), "-capture_cursor", "1",
                         "-i", "Capture screen 0:none"]]
    else:
        video_inputs = [["-f", "x11grab", "-framerate", str(fps), "-draw_mouse", "1",
                         "-i", os.environ.get("DISPLAY") or ":0"]]

    vf = f"scale=-2:'trunc(min({int(height)},ih)/2)*2':flags=bicubic,format=yuv420p"
    tail = ["-map", "0:v:0", "-vf", vf]
    tail += video_encoder_args(caps, crf=23, maxrate_mbps=10, zerolatency=True)
    tail += ["-g", str(max(30, 2 * fps)), "-r", str(fps)]
    if a_in:
        tail += ["-map", "1:a:0", "-af", "aresample=async=1000", "-c:a", "aac", "-b:a", "160k",
                 "-ac", "2", "-ar", "48000"]
    tail += ["-muxdelay", "0", "-muxpreload", "0"] + output_args(container)
    head = [ff, "-hide_banner", "-nostdin", "-loglevel", "error"]
    return [(head + ["-thread_queue_size", "512"] + v + a_in + tail, feeder) for v in video_inputs]


# ---------------------------------------------------------------------------
# Lógica de reproducción (la usan la ventana y la consola)
# ---------------------------------------------------------------------------

STATE_TEXT = {
    "PLAYING": "Reproduciendo", "PAUSED_PLAYBACK": "En pausa", "STOPPED": "Detenido",
    "TRANSITIONING": "Cargando", "NO_MEDIA_PRESENT": "Sin video", "": "—",
}


class Caster:
    """Une un proyector con el servidor de video y recuerda qué se está mostrando."""

    def __init__(self):
        self.server: Optional[MediaServer] = None
        self.renderer: Optional[Renderer] = None
        self.mode: Optional[str] = None  # "archivo" | "convertido" | "pantalla"
        self.title = ""
        self.path: Optional[str] = None
        self.info = MediaInfo()
        self.duration: Optional[float] = None
        self.offset = 0.0
        self.media = None
        self.sent_at = 0.0
        self._tc: dict = {}
        self._tmp: Optional[str] = None
        self._clock = 0.0
        self._last_poll: Optional[float] = None
        self._was_playing = False
        self._browser: Optional[BrowserRenderer] = None
        self.auto_compatible = False

    # --- infraestructura ---
    def ensure_server(self) -> MediaServer:
        if self.server is None:
            self.server = MediaServer()
        return self.server

    def page_url(self) -> str:
        """Dirección para abrir en el navegador del proyector."""
        ip = local_ip_for("239.255.255.250") or (local_ipv4s() or ["127.0.0.1"])[0]
        return f"http://{ip}:{self.ensure_server().port}"

    def browser(self) -> BrowserRenderer:
        if self._browser is None:
            self._browser = BrowserRenderer(self.ensure_server().hub, self.page_url)
        return self._browser

    def _url(self, path: str) -> str:
        host = getattr(self.renderer, "host", "")
        ip = (local_ip_for(host) if host else None) or local_ip_for("239.255.255.250") \
            or (local_ipv4s() or ["127.0.0.1"])[0]
        return f"http://{ip}:{self.server.port}{path}"

    def _switch_renderer(self, renderer) -> None:
        if self.renderer and self.mode and self.renderer.key != renderer.key:
            try:
                self.renderer.stop()
            except ProyectarError:
                pass
        self.renderer = renderer

    def _send(self, media, title: str, sub=None) -> None:
        self.ensure_server()
        r = self.renderer
        try:
            r.stop()
            time.sleep(0.2)
        except ProyectarError:
            pass
        self.server.clear()
        url = self._url(self.server.add(media))
        sub_url = None
        if sub:
            sub_url = self._url(self.server.add(sub))
            media.headers["CaptionInfo.sec"] = sub_url
        log.info("Enviando %s a %s", url, r.label)
        self.media = media
        self.sent_at = time.monotonic()
        self._clock, self._last_poll, self._was_playing = 0.0, None, False
        r.load(url, media.mime, title, media.live, media.features,
               duration=None if media.live else self.duration,
               size=None if media.live else media.size,
               sub_url=sub_url, sub_mime=sub.mime if sub else "text/srt")

    def _sub_media(self, path: str):
        """Subtítulos externos en el formato que entiende cada tipo de proyector."""
        if self.renderer.kind == "DLNA":
            return FileMedia(path, transfer="Interactive")
        if os.path.splitext(path)[1].lower() in (".srt", ".vtt"):
            return vtt_media(path)  # Chromecast y navegadores usan WebVTT
        return None

    def tmpdir(self) -> str:
        if not self._tmp:
            self._tmp = tempfile.mkdtemp(prefix="proyectar_")
        return self._tmp

    def _extract_sub(self, ff: str, path: str, stream: Stream) -> str:
        """Copia los subtítulos internos de texto a un archivo (una sola vez)."""
        key = hashlib.md5(f"{path}|{stream.type_index}".encode("utf-8")).hexdigest()[:10]
        out = os.path.join(self.tmpdir(), f"subs_{key}.ass")
        if not os.path.exists(out):
            log.info("Extrayendo subtítulos internos (pista %d)…", stream.type_index + 1)
            r = subprocess.run([ff, "-hide_banner", "-nostdin", "-loglevel", "error", "-y", "-i", path,
                                "-map", f"0:s:{stream.type_index}", "-c:s", "ass", out],
                               capture_output=True, timeout=900, creationflags=NO_WINDOW)
            if r.returncode != 0 or not os.path.exists(out):
                raise ProyectarError("No pude leer esos subtítulos internos:\n"
                                     + r.stderr.decode("utf-8", "replace")[-400:])
        return out

    # --- acciones ---
    def play_file(self, renderer: Renderer, path: str, compatible: bool = False,
                  audio: Optional[Stream] = None, subtitle=None, info: Optional[MediaInfo] = None) -> None:
        """subtitle: None, ruta a un .srt/.ass, o una pista interna (Stream)."""
        if not os.path.isfile(path):
            raise ProyectarError(f"No encuentro el archivo:\n{path}")
        self._switch_renderer(renderer)
        self.mode = None
        self.path = path
        self.title = os.path.splitext(os.path.basename(path))[0]
        self.info = info if info is not None else probe(path)
        self.duration = self.info.duration
        # Chromecast y navegadores sólo abren MP4/WebM: el resto se convierte solo
        self.auto_compatible = not compatible and renderer.prefers_compatible(path) and bool(find_ffmpeg())
        compatible = compatible or self.auto_compatible
        if compatible:
            ff = require_ffmpeg()
            sub_file = sub_stream = None
            if isinstance(subtitle, Stream):
                if subtitle.codec in TEXT_SUB_CODECS:
                    sub_file = self._extract_sub(ff, path, subtitle)
                else:
                    sub_stream = subtitle
            elif subtitle:
                sub_file = subtitle
            self._tc = {"ff": ff, "audio": audio, "sub_file": sub_file, "sub_stream": sub_stream}
            self._start_converted(0.0)
            self.mode = "convertido"
        else:
            if isinstance(subtitle, Stream):
                raise ProyectarError("Los subtítulos internos sólo se pueden mostrar en modo Compatible.")
            sub = self._sub_media(subtitle) if subtitle else None
            self.offset = 0.0
            self._send(FileMedia(path), self.title, sub)
            self.mode = "archivo"

    def _start_converted(self, offset: float) -> None:
        o = self._tc
        caps = ffmpeg_caps(o["ff"])
        container = self.renderer.live_format
        args = build_transcode_args(o["ff"], self.path, self.info, offset, o["audio"],
                                    o["sub_file"], o["sub_stream"], caps, container=container)
        mime, ext = LIVE_FORMATS[container]
        media = LiveMedia("pelicula" + ext, mime, [lambda: FFmpegProcess(args)])
        self.offset = offset
        self._send(media, self.title)

    def play_screen(self, renderer: Renderer, height: int = 1080, fps: int = 30,
                    audio: Optional[tuple] = None) -> None:
        ff = require_ffmpeg()
        if sys.platform.startswith("linux") and os.environ.get("XDG_SESSION_TYPE") == "wayland":
            log.warning("En Wayland la captura de pantalla puede salir negra; usa una sesión X11.")
        self._switch_renderer(renderer)
        self.mode = None
        container = renderer.live_format
        cmds = [(lambda a=a, f=f: FFmpegProcess(a, f))
                for a, f in screen_commands(ff, ffmpeg_caps(ff), height, fps, audio, container)]
        self.title = f"Pantalla de {socket.gethostname()}"
        self.duration, self.offset, self.path = None, 0.0, None
        mime, ext = LIVE_FORMATS[container]
        self._send(LiveMedia("pantalla" + ext, mime, cmds), self.title)
        self.mode = "pantalla"

    def toggle_pause(self) -> str:
        r = self.renderer
        if not r or not self.mode:
            raise ProyectarError("No se está proyectando nada.")
        if r.transport_state() == "PLAYING":
            r.pause()
            return "PAUSED_PLAYBACK"
        if self.mode == "pantalla":  # volver a conectar para ver la pantalla "en vivo" otra vez
            self._send(self.media, self.title)
        else:
            r.play()
        return "PLAYING"

    def stop(self) -> None:
        if self.renderer and self.mode:
            try:
                self.renderer.stop()
            except ProyectarError:
                pass
        if self.server:
            self.server.clear()
        self.mode = None
        self.media = None

    def seek(self, seconds: float) -> None:
        if self.mode == "pantalla":
            raise ProyectarError("La transmisión de pantalla no se puede adelantar ni atrasar.")
        if not self.mode:
            return
        seconds = max(0.0, seconds)
        if self.duration:
            seconds = min(seconds, max(0.0, self.duration - 3))
        if self.mode == "convertido":  # se reinicia la conversión desde ese punto
            self._start_converted(seconds)
        else:
            self.renderer.seek(seconds)
            self._clock = seconds

    def seek_relative(self, delta: float) -> None:
        self.seek(self.status()["position"] + delta)

    def status(self) -> dict:
        r = self.renderer
        if not r or not self.mode:
            return {"state": "", "position": 0.0, "duration": None, "mode": None,
                    "requests": 0, "error": None, "since": 0.0, "kind": "", "connected": True}
        state = r.transport_state()
        try:
            rel, dur = r.position()
        except ProyectarError:
            rel, dur = None, None
        now = time.monotonic()
        # Reloj propio por si el proyector no informa la posición
        if self._was_playing and self._last_poll is not None:
            self._clock += now - self._last_poll
        self._last_poll, self._was_playing = now, state == "PLAYING"
        if rel:
            self._clock = rel
        pos = self._clock
        if self.mode == "convertido":
            pos += self.offset
            dur = self.duration
        elif self.mode == "archivo":
            dur = dur or self.duration
        else:
            dur = None
        media = self.media
        return {
            "state": state, "position": pos, "duration": dur, "mode": self.mode,
            "requests": getattr(media, "requests", 0), "error": getattr(media, "last_error", None),
            "since": now - self.sent_at, "kind": r.kind, "connected": getattr(r, "connected", True),
        }

    def close(self) -> None:
        try:
            self.stop()
        except Exception:
            pass
        if self.server:
            self.server.close()
            self.server = None
        if self._tmp:
            shutil.rmtree(self._tmp, ignore_errors=True)
            self._tmp = None


def cargar_luces():
    """El programa «Luces» (carpeta luces/ al lado) si está instalado y conectado a Smart Life."""
    here = os.path.dirname(os.path.abspath(__file__))
    for folder in (here, os.path.join(os.path.dirname(here), "luces"), os.path.join(here, "luces")):
        if os.path.isfile(os.path.join(folder, "luces.py")):
            if folder not in sys.path:
                sys.path.append(folder)
            try:
                import luces
                hogar = luces.Hogar()
                return hogar if hogar.configurado and hogar.luces else None
            except Exception as e:
                log.debug("No se pudo cargar Luces: %s", e)
                return None
    return None


def abrir_miracast() -> None:
    """Abre el panel «Transmitir» de Windows (lo mismo que pulsar Win + K)."""
    if os.name != "nt":
        raise ProyectarError("Miracast se usa desde Windows (Win + K).")
    try:
        import ctypes
        user32 = ctypes.windll.user32
        win, k, up = 0x5B, 0x4B, 0x0002
        user32.keybd_event(win, 0, 0, 0)
        user32.keybd_event(k, 0, 0, 0)
        user32.keybd_event(k, 0, up, 0)
        user32.keybd_event(win, 0, up, 0)
    except Exception:
        os.startfile("ms-settings-connectabledevices:devicediscovery")  # type: ignore[attr-defined]


BROWSER_HELP = """En el proyector abre el navegador de internet
(puede llamarse «Navegador», «Browser», «Chrome» o «Internet»)
y escribe esta dirección:

        {url}

Cuando aparezca «Proyectar», pulsa OK en el control remoto.
Desde ahí todo se maneja desde la PC. Puedes guardar la dirección
en favoritos del proyector para la próxima vez."""


def media_summary(info: MediaInfo, external_subs: int = 0) -> Tuple[str, List[str]]:
    """Resumen legible del archivo + advertencias."""
    parts, warnings = [], []
    if info.duration:
        parts.append(f"Duración {fmt_time(info.duration)}")
    v = info.video
    if v:
        w, h = v.size
        parts.append(f"Video {v.codec.upper()}" + (f" {w}×{h}" if w else ""))
        if v.codec in HARD_VIDEO:
            warnings.append(f"Video {v.codec.upper()}: si el proyector no muestra la imagen, usa el modo Compatible.")
    a = info.default_audio
    if a:
        n = len(info.audios)
        parts.append(f"Audio {a.codec.upper()} {a.channels}".strip() + (f" ({n} pistas)" if n > 1 else ""))
        if a.codec in HARD_AUDIO:
            warnings.append(f"Audio {a.codec.upper()}: muchos proyectores no lo reproducen. "
                            "Si no se escucha, usa el modo Compatible.")
    subs = len(info.subtitles)
    if subs or external_subs:
        parts.append("Subtítulos: " + ", ".join(
            x for x in (f"{subs} internos" if subs else "", f"{external_subs} en archivo" if external_subs else "") if x))
    return " · ".join(parts), warnings


# ---------------------------------------------------------------------------
# Ventana
# ---------------------------------------------------------------------------

class App:
    POLL_MS = 1000

    def __init__(self, root, initial_file: Optional[str] = None):
        self.root = root
        self.cfg = load_config()
        self.caster = Caster()
        self.renderers: List[Renderer] = []
        self.file_path: Optional[str] = None
        self.file_info = MediaInfo()
        self.audio_options: List[Tuple[str, Optional[Stream]]] = []
        self.sub_options: List[Tuple[str, object]] = []
        self.screen_audio: List[Tuple[str, Optional[tuple]]] = []
        self.results: queue.Queue = queue.Queue()
        self.jobs = ThreadPoolExecutor(max_workers=1)  # las órdenes al proyector van de a una
        self.polling = False
        self.dragging = False
        self.last_state = ""
        self.warned = False
        self.hogar_luces = cargar_luces()
        self._luces_foto: Optional[dict] = None
        try:
            self.caster.ensure_server()  # para que la página del navegador ya responda
        except ProyectarError as e:
            log.warning("%s", e)

        root.title(f"{APP} – películas al proyector")
        self._style()
        self._build()
        root.protocol("WM_DELETE_WINDOW", self.close)
        root.after(100, self._pump)
        root.after(self.POLL_MS, self._tick)
        self.search()
        self._load_screen_audio()
        if initial_file:
            self.load_file(initial_file)

    # --- hilos: el trabajo lento va en segundo plano y vuelve por la cola ---
    def _post(self, fn, *args):
        self.results.put((fn, args))

    def _pump(self):
        try:
            while True:
                fn, args = self.results.get_nowait()
                try:
                    fn(*args)
                except Exception:
                    log.exception("Error en la ventana")
        except queue.Empty:
            pass
        self.root.after(100, self._pump)

    def bg(self, work, done=None, quiet=False, serial=True):
        def run():
            try:
                result = work()
            except Exception as e:
                if not isinstance(e, ProyectarError):
                    log.exception("Error")
                self._post(self._failed, e, quiet)
            else:
                if done:
                    self._post(done, result)
        if serial:
            self.jobs.submit(run)
        else:
            threading.Thread(target=run, daemon=True).start()

    def _failed(self, e, quiet):
        msg = str(e) if isinstance(e, ProyectarError) else f"Error inesperado: {e}"
        self.set_status(msg.splitlines()[0], error=True)
        if not quiet:
            messagebox.showerror(APP, msg, parent=self.root)

    # --- armado de la ventana ---
    def _style(self):
        st = ttk.Style(self.root)
        if os.name != "nt" and "clam" in st.theme_names():
            st.theme_use("clam")
        st.configure("Big.TButton", font=("Segoe UI" if os.name == "nt" else "TkDefaultFont", 11, "bold"),
                     padding=(18, 8))
        st.configure("Hint.TLabel", foreground="#666666")
        st.configure("Warn.TLabel", foreground="#a15c00")
        st.configure("Status.TLabel", foreground="#333333")
        st.configure("Error.TLabel", foreground="#b00020")

    def _build(self):
        r = self.root
        r.columnconfigure(0, weight=1)
        r.rowconfigure(1, weight=1)
        pad = {"padx": 12, "pady": (10, 0)}

        top = ttk.LabelFrame(r, text="Proyector", padding=8)
        top.grid(row=0, column=0, sticky="ew", **pad)
        top.columnconfigure(0, weight=1)
        self.dev_combo = ttk.Combobox(top, state="readonly")
        self.dev_combo.grid(row=0, column=0, sticky="ew")
        self.dev_combo.bind("<<ComboboxSelected>>", self._device_selected)
        self.btn_search = ttk.Button(top, text="Buscar", command=self.search)
        self.btn_search.grid(row=0, column=1, padx=(8, 0))
        ttk.Button(top, text="Por IP…", command=self.add_by_ip).grid(row=0, column=2, padx=(6, 0))

        nb = ttk.Notebook(r)
        nb.grid(row=1, column=0, sticky="nsew", **pad)
        film, screen = ttk.Frame(nb, padding=12), ttk.Frame(nb, padding=12)
        nb.add(film, text="  Película  ")
        nb.add(screen, text="  Pantalla de la PC  ")
        self._build_film(film)
        self._build_screen(screen)

        ctl = ttk.LabelFrame(r, text="Reproducción", padding=8)
        ctl.grid(row=2, column=0, sticky="ew", **pad)
        ctl.columnconfigure(1, weight=1)
        self.pos_lbl = ttk.Label(ctl, text="0:00:00", width=8, anchor="e")
        self.pos_lbl.grid(row=0, column=0)
        self.seek_bar = ttk.Scale(ctl, from_=0, to=1, orient="horizontal", command=self._seek_drag)
        self.seek_bar.grid(row=0, column=1, sticky="ew", padx=8)
        self.seek_bar.bind("<ButtonPress-1>", lambda e: setattr(self, "dragging", True))
        self.seek_bar.bind("<ButtonRelease-1>", self._seek_release)
        self.dur_lbl = ttk.Label(ctl, text="0:00:00", width=8)
        self.dur_lbl.grid(row=0, column=2)

        btns = ttk.Frame(ctl)
        btns.grid(row=1, column=0, columnspan=3, sticky="ew", pady=(8, 0))
        ttk.Button(btns, text="⏪ 10 s", width=8, command=lambda: self.jump(-10)).pack(side="left")
        self.btn_pause = ttk.Button(btns, text="⏸ Pausa", width=10, command=self.toggle_pause)
        self.btn_pause.pack(side="left", padx=4)
        ttk.Button(btns, text="30 s ⏩", width=8, command=lambda: self.jump(30)).pack(side="left")
        ttk.Button(btns, text="⏹ Detener", width=10, command=self.stop).pack(side="left", padx=(4, 0))
        self.vol_lbl = ttk.Label(btns, text="–", width=4)
        self.vol_lbl.pack(side="right")
        self.vol = ttk.Scale(btns, from_=0, to=100, orient="horizontal", length=130,
                             command=lambda v: self.vol_lbl.configure(text=f"{float(v):.0f}"))
        self.vol.pack(side="right", padx=4)
        self.vol.bind("<ButtonRelease-1>", self._vol_release)
        ttk.Label(btns, text="Volumen").pack(side="right")

        self.cine_var = tk.BooleanVar(value=bool(self.cfg.get("modo_cine", True)))
        if self.hogar_luces:
            ttk.Checkbutton(ctl, text="Modo cine: bajar las luces de Smart Life mientras se proyecta",
                            variable=self.cine_var, command=self._cine_cambiado).grid(
                row=2, column=0, columnspan=3, sticky="w", pady=(8, 0))

        self.status_lbl = ttk.Label(r, text="", style="Status.TLabel", anchor="w", padding=(14, 8))
        self.status_lbl.grid(row=3, column=0, sticky="ew")
        r.update_idletasks()
        r.minsize(max(620, r.winfo_reqwidth()), r.winfo_reqheight())

    def _build_film(self, f):
        f.columnconfigure(1, weight=1)
        ttk.Label(f, text="Archivo:").grid(row=0, column=0, sticky="w")
        self.file_lbl = ttk.Label(f, text="(ninguno)", font=("TkDefaultFont", 10, "bold"))
        self.file_lbl.grid(row=0, column=1, sticky="ew", padx=8)
        ttk.Button(f, text="Elegir película…", command=self.choose_file).grid(row=0, column=2)
        self.info_lbl = ttk.Label(f, text="Elige un video de tu PC (MP4, MKV, AVI…).", style="Hint.TLabel",
                                  wraplength=560, justify="left")
        self.info_lbl.grid(row=1, column=0, columnspan=3, sticky="w", pady=(4, 0))
        self.warn_lbl = ttk.Label(f, text="", style="Warn.TLabel", wraplength=560, justify="left")
        self.warn_lbl.grid(row=2, column=0, columnspan=3, sticky="w")

        ttk.Label(f, text="Modo:").grid(row=3, column=0, sticky="nw", pady=(10, 0))
        self.mode_var = tk.StringVar(value="original")
        modes = ttk.Frame(f)
        modes.grid(row=3, column=1, columnspan=2, sticky="w", padx=8, pady=(10, 0))
        ttk.Radiobutton(modes, text="Original — máxima calidad (recomendado)", value="original",
                        variable=self.mode_var).pack(anchor="w")
        ttk.Radiobutton(modes, text="Compatible — convierte en vivo; elige audio y subtítulos",
                        value="compatible", variable=self.mode_var).pack(anchor="w")

        ttk.Label(f, text="Audio:").grid(row=4, column=0, sticky="w", pady=(10, 0))
        self.audio_combo = ttk.Combobox(f, state="readonly")
        self.audio_combo.grid(row=4, column=1, columnspan=2, sticky="ew", padx=8, pady=(10, 0))
        self.audio_combo.bind("<<ComboboxSelected>>", self._audio_selected)
        ttk.Label(f, text="Subtítulos:").grid(row=5, column=0, sticky="w", pady=(6, 0))
        self.sub_combo = ttk.Combobox(f, state="readonly")
        self.sub_combo.grid(row=5, column=1, columnspan=2, sticky="ew", padx=8, pady=(6, 0))
        self.sub_combo.bind("<<ComboboxSelected>>", self._sub_selected)
        self._fill_tracks()

        ttk.Button(f, text="▶  Proyectar película", style="Big.TButton",
                   command=self.play_film).grid(row=6, column=0, columnspan=3, pady=(16, 0))

    def _build_screen(self, f):
        f.columnconfigure(1, weight=1)
        ttk.Label(f, text="Muestra en el proyector todo lo que se ve y se escucha en la PC "
                          "(por ejemplo, una película en el navegador).",
                  wraplength=560, justify="left").grid(row=0, column=0, columnspan=2, sticky="w")
        ttk.Label(f, text="Calidad:").grid(row=1, column=0, sticky="w", pady=(12, 0))
        self.q_combo = ttk.Combobox(f, state="readonly",
                                    values=["1080p (Full HD)", "720p (HD)", "480p (más liviano)"])
        self.q_combo.current(0)
        self.q_combo.grid(row=1, column=1, sticky="ew", padx=8, pady=(12, 0))
        ttk.Label(f, text="Fluidez:").grid(row=2, column=0, sticky="w", pady=(6, 0))
        self.fps_combo = ttk.Combobox(f, state="readonly",
                                      values=["30 cuadros por segundo", "60 cuadros por segundo",
                                              "24 cuadros por segundo"])
        self.fps_combo.current(0)
        self.fps_combo.grid(row=2, column=1, sticky="ew", padx=8, pady=(6, 0))
        ttk.Label(f, text="Sonido:").grid(row=3, column=0, sticky="w", pady=(6, 0))
        self.sa_combo = ttk.Combobox(f, state="readonly", values=["Buscando…"])
        self.sa_combo.current(0)
        self.sa_combo.grid(row=3, column=1, sticky="ew", padx=8, pady=(6, 0))
        ttk.Label(f, text="Tiene unos segundos de retraso: ideal para películas, no para juegos. "
                          "Si tu proyector admite Miracast, en Windows también puedes usar Win + K.",
                  style="Hint.TLabel", wraplength=560, justify="left"
                  ).grid(row=4, column=0, columnspan=2, sticky="w", pady=(10, 0))
        ttk.Button(f, text="▶  Transmitir pantalla", style="Big.TButton",
                   command=self.play_screen).grid(row=5, column=0, columnspan=2, pady=(16, 0))
        if os.name == "nt":
            ttk.Button(f, text="Duplicar con Miracast (Win + K)", command=self.miracast).grid(
                row=6, column=0, columnspan=2, pady=(8, 0))

    def set_status(self, text: str, error: bool = False):
        self.status_lbl.configure(text=text, style="Error.TLabel" if error else "Status.TLabel")

    # --- proyectores ---
    def current_renderer(self):
        i = self.dev_combo.current()
        if 0 <= i < len(self.renderers):
            return self.renderers[i]
        if i == len(self.renderers) and self.caster.server is not None:
            return self.caster.browser()
        return None

    def _labels(self) -> List[str]:
        return [r.label for r in self.renderers] + [BrowserRenderer.label.fget(None)]

    def search(self, hosts: Optional[List[str]] = None):
        self.btn_search.state(["disabled"])
        self.set_status("Buscando proyectores en la red…")

        def work():
            found = discover(timeout=3.0, hosts=hosts)
            last = self.cfg.get("ultimo_proyector", {}).get("location")
            if not found and not hosts and last:
                try:  # puede que no responda a la búsqueda pero siga en la misma dirección
                    r = load_renderer(last)
                    found = [r] if r else []
                except Exception:
                    pass
            return found
        self.bg(work, done=self._search_done, quiet=True, serial=False)
        self.root.after(5000, lambda: self.btn_search.state(["!disabled"]))

    def _search_done(self, found: List[Renderer]):
        self.btn_search.state(["!disabled"])
        known = {r.key: r for r in self.renderers}
        for r in found:
            known[r.key] = r
        current = self.current_renderer()
        self.renderers = sorted(known.values(), key=lambda r: (r.name.lower(), r.kind))
        self.dev_combo.configure(values=self._labels())
        if not self.renderers:
            self.dev_combo.current(0)  # sólo queda el navegador
            self.set_status("No encontré el proyector por DLNA ni Chromecast. Puedes usar «Navegador del "
                            "proyector» o, en Windows, Miracast.", error=True)
            if not self.warned:
                self.warned = True
                messagebox.showwarning(APP, NOT_FOUND_HELP, parent=self.root)
            self._device_selected()
            return
        last = self.cfg.get("ultimo_proyector", {}).get("udn")
        options = self.renderers + [self.caster.browser()]
        pick = next((i for i, r in enumerate(options) if current and r.key == current.key), None)
        if pick is None:
            pick = next((i for i, r in enumerate(options) if last and (r.udn or r.key) == last), 0)
        self.dev_combo.current(pick)
        n = len(self.renderers)
        self.set_status(f"Listo. {'Encontré 1 equipo' if n == 1 else f'Encontré {n} equipos'} para proyectar.")
        self._device_selected()

    def _device_selected(self, _event=None):
        r = self.current_renderer()
        if not r:
            return
        self.cfg["ultimo_proyector"] = {"udn": r.udn or r.key, "location": r.location, "name": r.name,
                                        "kind": r.kind}
        save_config(self.cfg)
        if r.kind == "Navegador":
            if not r.connected:
                self.set_status(f"En el navegador del proyector abre {self.caster.page_url()} y pulsa OK.")
        else:
            self.bg(r.get_volume, done=self._show_volume, quiet=True)

    def _show_volume(self, v):
        self.vol.set(v)
        self.vol_lbl.configure(text=str(v))

    def add_by_ip(self):
        ip = simpledialog.askstring(
            APP, "IP del proyector (la ves en su menú de red o WiFi),\npor ejemplo 192.168.0.25:",
            parent=self.root)
        if ip:
            ip = ip.strip()
            if not looks_like_ip(ip):
                messagebox.showerror(APP, f"«{ip}» no parece una IP (debe ser como 192.168.0.25).",
                                     parent=self.root)
                return
            self.search(hosts=[ip])

    def _renderer_or_warn(self) -> Optional[Renderer]:
        r = self.current_renderer()
        if not r:
            messagebox.showinfo(APP, "Primero elige un proyector (o pulsa «Buscar»).", parent=self.root)
        return r

    # --- película ---
    def choose_file(self):
        path = filedialog.askopenfilename(
            parent=self.root, title="Elegir película",
            initialdir=self.cfg.get("ultima_carpeta") or os.path.expanduser("~"),
            filetypes=[("Videos", VIDEO_EXTS), ("Todos los archivos", "*.*")])
        if path:
            self.load_file(path)

    def load_file(self, path: str):
        path = os.path.abspath(path)
        self.file_path = path
        self.file_info = MediaInfo()
        self.cfg["ultima_carpeta"] = os.path.dirname(path)
        save_config(self.cfg)
        self.file_lbl.configure(text=os.path.basename(path))
        self.info_lbl.configure(text="Analizando el archivo…")
        self.warn_lbl.configure(text="")
        self._fill_tracks()
        self.bg(lambda: (path, probe(path)), done=self._file_loaded, quiet=True, serial=False)

    def _file_loaded(self, result):
        path, info = result
        if path != self.file_path:
            return
        self.file_info = info
        externals = find_external_subs(path)
        summary, warnings = media_summary(info, len(externals))
        if not find_ffmpeg():
            summary = summary or "Listo para proyectar."
            warnings.append("(Sin ffmpeg no puedo analizar el archivo ni usar el modo Compatible.)")
        self.info_lbl.configure(text=summary or "Listo para proyectar.")
        self.warn_lbl.configure(text="\n".join("⚠ " + w for w in warnings))
        self._fill_tracks(externals)

    def _fill_tracks(self, externals: Optional[List[str]] = None):
        info = self.file_info
        self.audio_options = [(a.label(i + 1), a) for i, a in enumerate(info.audios)] or [("Predeterminado", None)]
        self.audio_combo.configure(values=[t for t, _ in self.audio_options])
        default = info.default_audio
        self.audio_combo.current(next((i for i, (_, a) in enumerate(self.audio_options) if a is default), 0))
        self.sub_options = [("Sin subtítulos", None)]
        self.sub_options += [(f"Archivo: {os.path.basename(p)}", p) for p in (externals or [])]
        self.sub_options += [(s.label(i + 1), s) for i, s in enumerate(info.subtitles)]
        self.sub_options.append(("Elegir archivo de subtítulos…", "elegir"))
        self.sub_combo.configure(values=[t for t, _ in self.sub_options])
        self.sub_combo.current(1 if externals else 0)  # si hay un .srt al lado, se usa

    def _audio_selected(self, _e=None):
        i = self.audio_combo.current()
        chosen = self.audio_options[i][1] if 0 <= i < len(self.audio_options) else None
        if chosen is not None and chosen is not self.file_info.default_audio and self.mode_var.get() != "compatible":
            self.mode_var.set("compatible")
            self.set_status("Para elegir la pista de audio se usa el modo Compatible.")

    def _sub_selected(self, _e=None):
        i = self.sub_combo.current()
        value = self.sub_options[i][1] if 0 <= i < len(self.sub_options) else None
        if value == "elegir":
            path = filedialog.askopenfilename(
                parent=self.root, title="Elegir subtítulos",
                initialdir=os.path.dirname(self.file_path) if self.file_path else None,
                filetypes=[("Subtítulos", "*.srt *.ass *.ssa *.vtt"), ("Todos los archivos", "*.*")])
            if not path:
                self.sub_combo.current(0)
                return
            self.sub_options.insert(1, (f"Archivo: {os.path.basename(path)}", path))
            self.sub_combo.configure(values=[t for t, _ in self.sub_options])
            self.sub_combo.current(1)
        elif isinstance(value, Stream) and self.mode_var.get() != "compatible":
            self.mode_var.set("compatible")
            self.set_status("Los subtítulos internos se muestran con el modo Compatible.")

    def play_film(self):
        r = self._renderer_or_warn()
        if not r:
            return
        if not self.file_path:
            messagebox.showinfo(APP, "Primero elige una película.", parent=self.root)
            return
        compatible = self.mode_var.get() == "compatible"
        ai, si = self.audio_combo.current(), self.sub_combo.current()
        audio = self.audio_options[ai][1] if 0 <= ai < len(self.audio_options) else None
        sub = self.sub_options[si][1] if 0 <= si < len(self.sub_options) else None
        if sub == "elegir":
            sub = None
        if isinstance(sub, Stream) and not compatible:
            compatible = True
            self.mode_var.set("compatible")
        if compatible and not find_ffmpeg():
            messagebox.showerror(APP, FFMPEG_HELP, parent=self.root)
            return
        path, info = self.file_path, self.file_info
        title = os.path.basename(path)
        self._browser_help(r)
        self.set_status(f"Enviando «{title}» a {r.name}…")

        def done(_):
            extra = " (se convierte en vivo: este equipo no abre ese formato directo)" \
                if self.caster.auto_compatible else ""
            self._started(f"Proyectando «{title}» en {r.name}{extra}")
        self.bg(lambda: self.caster.play_file(r, path, compatible, audio, sub, info), done=done)

    def _browser_help(self, r):
        if r.kind == "Navegador" and not r.connected:
            messagebox.showinfo(APP, BROWSER_HELP.format(url=self.caster.page_url()), parent=self.root)

    # --- pantalla ---
    def _load_screen_audio(self):
        def work():
            return audio_sources(find_ffmpeg())

        def done(opts):
            self.screen_audio = opts
            self.sa_combo.configure(values=[t for t, _ in opts])
            self.sa_combo.current(0)
        self.bg(work, done=done, quiet=True, serial=False)

    def play_screen(self):
        r = self._renderer_or_warn()
        if not r:
            return
        if not find_ffmpeg():
            messagebox.showerror(APP, FFMPEG_HELP, parent=self.root)
            return
        height = [1080, 720, 480][max(0, self.q_combo.current())]
        fps = [30, 60, 24][max(0, self.fps_combo.current())]
        i = self.sa_combo.current()
        audio = self.screen_audio[i][1] if 0 <= i < len(self.screen_audio) else None
        self._browser_help(r)
        self.set_status(f"Conectando la pantalla con {r.name}…")
        self.bg(lambda: self.caster.play_screen(r, height, fps, audio),
                done=lambda _: self._started(f"Transmitiendo la pantalla en {r.name} "
                                             "(tarda unos segundos en aparecer)"))

    # --- controles ---
    def _started(self, text):
        self.last_state = ""
        self.set_status(text)
        self._cine_on()
        r = self.caster.renderer
        if r and r.kind != "Navegador":
            self.bg(r.get_volume, done=self._show_volume, quiet=True)

    def miracast(self):
        try:
            abrir_miracast()
            self.set_status("Elige el proyector en el panel «Transmitir» de Windows. Si no aparece, en el "
                            "proyector abre la app «Screen Mirroring» o «Miracast».")
        except ProyectarError as e:
            self.set_status(str(e), error=True)

    # --- modo cine (luces de Smart Life) ---
    def _cine_cambiado(self):
        self.cfg["modo_cine"] = self.cine_var.get()
        save_config(self.cfg)
        if not self.cine_var.get():
            self._cine_off()
        elif self.caster.mode:
            self._cine_on()

    def _cine_on(self):
        hogar = self.hogar_luces
        if not hogar or not self.cine_var.get() or self._luces_foto is not None:
            return
        self._luces_foto = {}

        def work():
            hogar.actualizar_todo()
            foto = hogar.foto()  # para dejarlas como estaban al terminar
            hogar.aplicar_escena("Cine")
            return foto
        self.bg(work, done=lambda foto: setattr(self, "_luces_foto", foto), quiet=True, serial=False)

    def _cine_off(self, wait: bool = False):
        hogar, foto, self._luces_foto = self.hogar_luces, self._luces_foto, None
        if not hogar or not foto:
            return
        if wait:
            try:
                hogar.restaurar(foto)
            except Exception:
                pass
        else:
            self.bg(lambda: hogar.restaurar(foto), quiet=True, serial=False)

    def toggle_pause(self):
        if not self.caster.mode:
            return
        self.bg(self.caster.toggle_pause,
                done=lambda st: self.btn_pause.configure(text="⏸ Pausa" if st == "PLAYING" else "▶ Seguir"))

    def stop(self):
        if self.caster.mode:
            self.bg(self.caster.stop, done=lambda _: self._reset_controls("Detenido."))
        self._cine_off()

    def _reset_controls(self, text):
        self.seek_bar.set(0)
        self.pos_lbl.configure(text="0:00:00")
        self.dur_lbl.configure(text="0:00:00")
        self.btn_pause.configure(text="⏸ Pausa")
        self.set_status(text)

    def jump(self, delta):
        if self.caster.mode in ("archivo", "convertido"):
            self.set_status("Moviendo…")
            self.bg(lambda: self.caster.seek_relative(delta))

    def _seek_drag(self, value):
        if self.dragging:
            self.pos_lbl.configure(text=fmt_time(float(value)))

    def _seek_release(self, _e=None):
        self.dragging = False
        if self.caster.mode in ("archivo", "convertido") and self.caster.duration:
            target = float(self.seek_bar.get())
            self.set_status(f"Yendo a {fmt_time(target)}…")
            self.bg(lambda: self.caster.seek(target))

    def _vol_release(self, _e=None):
        r = self.caster.renderer or self.current_renderer()
        if r:
            v = int(float(self.vol.get()))
            self.bg(lambda: r.set_volume(v))

    def _tick(self):
        self.root.after(self.POLL_MS, self._tick)
        if self.caster.mode and not self.polling:
            self.polling = True

            def poll():
                try:
                    st = self.caster.status()
                    self._post(self._show_status, st)
                except Exception as e:
                    self._post(self.set_status, f"Sin respuesta del proyector: {e}", True)
                finally:
                    self._post(setattr, self, "polling", False)
            self.jobs.submit(poll)

    def _show_status(self, st):
        if not st.get("mode") or self.caster.mode != st["mode"]:
            return
        state, pos, dur = st["state"], st["position"], st["duration"]
        if not self.dragging:
            self.pos_lbl.configure(text=fmt_time(pos))
            if dur:
                self.seek_bar.configure(to=dur)
                self.seek_bar.set(min(pos, dur))
                self.dur_lbl.configure(text=fmt_time(dur))
            else:
                self.seek_bar.set(0)
                self.dur_lbl.configure(text="en vivo" if st["mode"] == "pantalla" else "—")
        self.btn_pause.configure(text="⏸ Pausa" if state in ("PLAYING", "TRANSITIONING") else "▶ Seguir")
        name = self.caster.renderer.name if self.caster.renderer else ""
        stopped = state in ("STOPPED", "NO_MEDIA_PRESENT")
        if stopped and self.last_state == "PLAYING":
            self._cine_off()  # terminó la película: vuelven las luces
        if st["kind"] == "Navegador" and not st["connected"]:
            self.set_status(f"Esperando al navegador del proyector: abre {self.caster.page_url()} y pulsa OK.",
                            error=True)
        elif st["error"] and stopped:
            self.set_status("ffmpeg falló: " + st["error"].splitlines()[-1][:150], error=True)
        elif st["requests"] == 0 and st["since"] > 10 and state != "PLAYING":
            self.set_status("El proyector todavía no pidió el video. Si es la primera vez, permite a Python "
                            "en el Firewall de Windows (redes privadas y públicas).", error=True)
        elif stopped and st["mode"] == "archivo" and st["since"] < 20 and self.last_state != "PLAYING":
            self.set_status("El proyector no pudo abrir el archivo. Prueba el modo Compatible.", error=True)
        elif stopped and self.last_state == "PLAYING":
            self.set_status("Terminó (o se detuvo desde el proyector).")
        elif not stopped:
            self.set_status(f"{STATE_TEXT.get(state, state)} en {name} — {self.caster.title}")
        self.last_state = state

    def close(self):
        self.set_status("Cerrando…")
        self.root.update_idletasks()

        def shutdown():
            self._cine_off(wait=True)
            self.caster.close()
        t = threading.Thread(target=shutdown, daemon=True)
        t.start()
        t.join(5)
        self.jobs.shutdown(wait=False)
        self.root.destroy()


def run_gui(initial_file: Optional[str] = None) -> int:
    if tk is None:
        print("Esta instalación de Python no trae la ventana (tkinter). Usa el modo consola:\n"
              "    python proyectar.py --help")
        return 2
    if os.name == "nt":
        try:  # texto nítido en pantallas con escalado
            import ctypes
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except Exception:
            pass
    root = tk.Tk()
    App(root, initial_file)
    root.mainloop()
    return 0


# ---------------------------------------------------------------------------
# Consola
# ---------------------------------------------------------------------------

CLI_HELP = ("Comandos:  [Enter] estado · p pausa/sigue · + adelanta 30 s · - atrasa 10 s · "
            "ir 1:20:00 · vol 50 · s salir")


def pick_renderer(query: Optional[str], caster: Optional["Caster"] = None):
    if query and query.strip().lower() in ("navegador", "browser") and caster is not None:
        print(BROWSER_HELP.format(url=caster.page_url()))
        return caster.browser()
    hosts = [query] if query and looks_like_ip(query) else None
    print("Buscando proyectores en la red…")
    found = discover(hosts=hosts)
    if not found and not hosts:
        last = load_config().get("ultimo_proyector", {}).get("location")
        if last:
            try:
                r = load_renderer(last)
                found = [r] if r else []
            except Exception:
                pass
    if query and not hosts:
        found = [r for r in found if query.lower() in r.name.lower() or query == r.host]
    if not found:
        raise ProyectarError(NOT_FOUND_HELP + "\n\nEn la consola: --proyector navegador")
    if len(found) == 1:
        return found[0]
    for i, r in enumerate(found, 1):
        print(f"  {i}. {r.label}")
    while True:
        choice = input("¿Cuál? (número): ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(found):
            return found[int(choice) - 1]


def interactive(caster: Caster) -> None:
    print(CLI_HELP)
    while True:
        try:
            line = input("> ").strip().lower()
        except EOFError:  # sin teclado (por ejemplo, en un script): esperar a que termine
            while caster.status()["state"] not in ("STOPPED", "NO_MEDIA_PRESENT"):
                time.sleep(2)
            return
        try:
            if line in ("s", "q", "salir", "stop"):
                return
            elif line in ("p", "pausa"):
                st = caster.toggle_pause()
                print("En pausa" if st != "PLAYING" else "Reproduciendo")
            elif line.startswith("+") or line.startswith("-"):
                amount = parse_time(line[1:]) or (30 if line[0] == "+" else 10)
                caster.seek_relative(amount if line[0] == "+" else -amount)
            elif line.startswith("ir "):
                t = parse_time(line[3:])
                if t is None:
                    print("Formato: ir 1:20:00")
                else:
                    caster.seek(t)
            elif line.startswith("vol"):
                v = line[3:].strip()
                if v.isdigit():
                    caster.renderer.set_volume(int(v))
                print(f"Volumen: {caster.renderer.get_volume()}")
            elif line in ("?", "ayuda", "h"):
                print(CLI_HELP)
            else:
                st = caster.status()
                dur = f" / {fmt_time(st['duration'])}" if st["duration"] else ""
                print(f"{STATE_TEXT.get(st['state'], st['state'])}  {fmt_time(st['position'])}{dur}")
                if st["error"]:
                    print("ffmpeg:", st["error"])
        except ProyectarError as e:
            print(e)


def run_cli(args) -> int:
    if args.listar:
        hosts = [args.proyector] if args.proyector and looks_like_ip(args.proyector) else None
        found = discover(hosts=hosts)
        if not found:
            print(NOT_FOUND_HELP)
            return 1
        for r in found:
            extra = " ".join(x for x in (r.manufacturer, r.model) if x)
            print(f"• {r.label}" + (f"  [{extra}]" if extra else ""))
        print("• También: --proyector navegador (el navegador web del proyector)")
        return 0

    caster = Caster()
    try:
        renderer = pick_renderer(args.proyector, caster)
        if args.pantalla:
            audio = None
            if not args.sin_sonido:
                opts = audio_sources(find_ffmpeg())
                audio = opts[0][1]
                print(f"Sonido: {opts[0][0]}")
            caster.play_screen(renderer, args.calidad, args.fps, audio)
            print(f"▶ Transmitiendo la pantalla en {renderer.label}")
        else:
            path = args.archivo
            info = probe(path)
            summary, warnings = media_summary(info, 0)
            if summary:
                print(summary)
            for w in warnings:
                print("⚠", w)
            sub = None
            if args.subs and args.subs.lower() not in ("no", "ninguno"):
                if args.subs.isdigit():
                    n = int(args.subs)
                    if not 1 <= n <= len(info.subtitles):
                        raise ProyectarError(f"El archivo tiene {len(info.subtitles)} pistas de subtítulos.")
                    sub = info.subtitles[n - 1]
                else:
                    sub = args.subs
            elif not args.subs:
                ext = find_external_subs(path)
                if ext:
                    sub = ext[0]
                    print(f"Subtítulos: {os.path.basename(sub)}  (usa --subs no para quitarlos)")
            audio = None
            if args.audio:
                if not 1 <= args.audio <= len(info.audios):
                    raise ProyectarError(f"El archivo tiene {len(info.audios)} pistas de audio.")
                audio = info.audios[args.audio - 1]
            compatible = args.compatible or isinstance(sub, Stream) or audio is not None
            caster.play_file(renderer, path, compatible, audio, sub, info)
            compatible = compatible or caster.auto_compatible
            print(f"▶ Proyectando en {renderer.label}" + ("  (modo Compatible)" if compatible else ""))
        interactive(caster)
        return 0
    except ProyectarError as e:
        print(f"\n{e}")
        return 1
    except KeyboardInterrupt:
        return 0
    finally:
        caster.close()


def setup_logging(verbose: bool = False) -> None:
    handlers: List[logging.Handler] = []
    if sys.stderr:
        console = logging.StreamHandler()
        console.setLevel(logging.DEBUG if verbose else logging.INFO)
        handlers.append(console)
    try:
        f = logging.FileHandler(LOG_PATH, "w", encoding="utf-8")
        f.setLevel(logging.DEBUG)
        handlers.append(f)
    except OSError:
        pass
    logging.basicConfig(level=logging.DEBUG, handlers=handlers,
                        format="%(asctime)s %(levelname)-7s %(message)s", datefmt="%H:%M:%S")
    logging.getLogger("urllib3").setLevel(logging.WARNING)


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(
        prog="proyectar",
        description="Proyecta películas o la pantalla de esta PC en un proyector/TV de la red WiFi (DLNA).",
        epilog="Sin argumentos abre la ventana.")
    p.add_argument("archivo", nargs="?", help="película a proyectar")
    p.add_argument("-l", "--listar", action="store_true", help="buscar proyectores en la red y salir")
    p.add_argument("-p", "--proyector", help="nombre (o parte) o IP del proyector, o 'navegador'")
    p.add_argument("-c", "--compatible", action="store_true",
                   help="convertir en vivo con ffmpeg (si no se ve o no se escucha)")
    p.add_argument("--audio", type=int, help="pista de audio (1, 2, …); activa el modo compatible")
    p.add_argument("--subs", help="archivo de subtítulos, número de pista interna, o 'no'")
    p.add_argument("--pantalla", action="store_true", help="transmitir la pantalla de la PC")
    p.add_argument("--calidad", type=int, default=1080, choices=[480, 720, 1080], help="altura de la imagen")
    p.add_argument("--fps", type=int, default=30, help="cuadros por segundo (pantalla)")
    p.add_argument("--sin-sonido", action="store_true", help="transmitir la pantalla sin sonido")
    p.add_argument("--ventana", action="store_true", help="abrir la ventana con este archivo")
    p.add_argument("-v", "--verbose", action="store_true", help="mostrar detalles técnicos")
    p.add_argument("--version", action="version", version=f"{APP} {VERSION}")
    args = p.parse_args(argv)
    setup_logging(args.verbose)
    if args.ventana or not (args.listar or args.archivo or args.pantalla):
        return run_gui(args.archivo)
    return run_cli(args)


if __name__ == "__main__":
    sys.exit(main())

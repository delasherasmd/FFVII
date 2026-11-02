#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Identificar proyector: revisa la red WiFi de la casa y cuenta qué equipos hay y qué
sabe hacer cada uno (DLNA, Chromecast, AirPlay, Android con ADB, Miracast…).

Guarda el informe en el escritorio (informe_proyector.txt) y lo copia al portapapeles,
para pegarlo en el chat.

    python identificar.py            (o IdentificarProyector.exe con doble clic)
"""

from __future__ import annotations

import argparse
import concurrent.futures
import ipaddress
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from typing import Dict, List, Optional

import proyectar as P

VERSION = "1.0"
_sin_proxy = urllib.request.build_opener(urllib.request.ProxyHandler({}))
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)

PUERTOS = {
    5555: "ADB (Android con depuración por red)",
    6466: "Control remoto Android TV",
    7000: "AirPlay",
    7236: "Miracast",
    8008: "Chromecast (http)",
    8009: "Chromecast",
    8443: "Chromecast (https)",
    8060: "Roku",
    8200: "Servidor DLNA",
    49152: "UPnP",
    80: "Página web",
    8080: "Página web",
    5000: "UPnP / AirPlay viejo",
    1400: "Sonos / UPnP",
}
SERVICIOS_MDNS = {
    "_googlecast._tcp.local": "Chromecast / Google Cast",
    "_androidtvremote2._tcp.local": "Android TV (control remoto)",
    "_adb-tls-connect._tcp.local": "Android (depuración inalámbrica)",
    "_adb._tcp.local": "Android (ADB)",
    "_airplay._tcp.local": "AirPlay (video)",
    "_raop._tcp.local": "AirPlay (audio)",
    "_spotify-connect._tcp.local": "Spotify Connect",
    "_http._tcp.local": "Página web",
}
PISTAS = re.compile(r"proyect|project|beam|hy\d{3}|magcubic|wanbo|xgimi|nebula|anker|yaber|vankyo|benq|epson|"
                    r"optoma|viewsonic|gadnic|philco|exelens|eshare|airscreen|android|tv|box|cast|screen|mirror", re.I)


def log(msg: str) -> None:
    print(msg, flush=True)


# ---------------------------------------------------------------------------
# Búsquedas
# ---------------------------------------------------------------------------

def mi_red() -> Optional[ipaddress.IPv4Network]:
    ip = P.local_ip_for("8.8.8.8") or P.local_ip_for("192.168.1.1") or (P.local_ipv4s() or [None])[0]
    if not ip:
        return None
    return ipaddress.ip_network(f"{ip}/24", strict=False)


def barrer_puertos(red: ipaddress.IPv4Network, propia: str, timeout: float = 0.45) -> Dict[str, List[int]]:
    """Prueba los puertos típicos en todas las direcciones de la red (unos segundos)."""
    abiertos: Dict[str, List[int]] = {}

    def probar(ip, puerto):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        try:
            if s.connect_ex((ip, puerto)) == 0:
                return ip, puerto
        except OSError:
            pass
        finally:
            s.close()
        return None

    tareas = [(str(ip), p) for ip in red.hosts() if str(ip) != propia for p in PUERTOS]
    with concurrent.futures.ThreadPoolExecutor(max_workers=200) as pool:
        for r in pool.map(lambda t: probar(*t), tareas):
            if r:
                abiertos.setdefault(r[0], []).append(r[1])
    return abiertos


def tabla_arp() -> Dict[str, str]:
    """Direcciones MAC que la PC conoce (sirven para saber la marca del equipo)."""
    macs: Dict[str, str] = {}
    for cmd in (["arp", "-a"], ["ip", "neigh"]):
        try:
            out = subprocess.run(cmd, capture_output=True, timeout=10, creationflags=NO_WINDOW).stdout
        except (OSError, subprocess.TimeoutExpired):
            continue
        texto = out.decode("utf-8", "replace") if isinstance(out, bytes) else out
        if not texto.strip():
            try:
                texto = out.decode("cp850", "replace")
            except Exception:
                pass
        for m in re.finditer(r"(\d+\.\d+\.\d+\.\d+)\D+?([0-9a-fA-F]{2}(?:[:-][0-9a-fA-F]{2}){5})", texto):
            mac = m.group(2).lower().replace("-", ":")
            if mac not in ("ff:ff:ff:ff:ff:ff",) and not mac.startswith("01:00:5e"):
                macs[m.group(1)] = mac
        if macs:
            break
    return macs


def nombre_dns(ip: str) -> str:
    try:
        return socket.gethostbyaddr(ip)[0]
    except OSError:
        return ""


def buscar_upnp(timeout: float = 4.0) -> Dict[str, List[dict]]:
    """Todos los equipos UPnP/DLNA (no sólo proyectores) con su ficha."""
    viejos = P.SSDP_TARGETS
    P.SSDP_TARGETS = ("ssdp:all", "upnp:rootdevice", "urn:schemas-upnp-org:device:MediaRenderer:1")
    try:
        ubicaciones = P.ssdp_search(timeout)
    finally:
        P.SSDP_TARGETS = viejos
    por_ip: Dict[str, List[dict]] = {}

    def leer(loc):
        try:
            raiz = P.parse_xml(P.http_get(loc, 4))
        except Exception:
            return None
        dev = raiz.find(".//device")
        if dev is None:
            return None
        servicios = sorted({(s.findtext("serviceType") or "").split(":")[-2] for s in raiz.iter("service")
                            if (s.findtext("serviceType") or "").count(":") >= 2})
        return {
            "ip": urllib.parse.urlsplit(loc).hostname, "ficha": loc,
            "nombre": (dev.findtext("friendlyName") or "").strip(),
            "fabricante": (dev.findtext("manufacturer") or "").strip(),
            "modelo": " ".join(x for x in ((dev.findtext("modelName") or "").strip(),
                                           (dev.findtext("modelNumber") or "").strip()) if x),
            "tipo": (dev.findtext("deviceType") or "").split(":")[-2] if (dev.findtext("deviceType") or "").count(":") >= 2 else "",
            "servicios": servicios,
        }
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        for d in pool.map(leer, ubicaciones):
            if d and d["ip"]:
                lista = por_ip.setdefault(d["ip"], [])
                if not any(x["nombre"] == d["nombre"] and x["tipo"] == d["tipo"] for x in lista):
                    lista.append(d)
    return por_ip


def buscar_mdns() -> Dict[str, List[dict]]:
    por_ip: Dict[str, List[dict]] = {}
    for servicio, desc in SERVICIOS_MDNS.items():
        try:
            encontrados = P.mdns_browse(servicio, timeout=1.3)
        except Exception:
            continue
        for s in encontrados:
            if s.get("host"):
                por_ip.setdefault(s["host"], []).append({"servicio": desc, "nombre": s["name"].split("._")[0],
                                                          "puerto": s.get("port"), "datos": s.get("txt") or {}})
    return por_ip


def preguntar_http(ip: str, puertos: List[int]) -> dict:
    """Datos extra que algunos equipos cuentan si se les pregunta por su página."""
    info: dict = {}

    def get(url, limite=4000):
        req = urllib.request.Request(url, headers={"User-Agent": "Identificar/1.0"})
        with _sin_proxy.open(req, timeout=3) as r:
            return r.headers.get("Server", ""), r.read(limite)
    if 8008 in puertos:
        try:
            _, cuerpo = get(f"http://{ip}:8008/setup/eureka_info?params=name,device_info,build_info", 20000)
            d = json.loads(cuerpo)
            di = d.get("device_info") or {}
            info["chromecast"] = {k: v for k, v in {
                "nombre": d.get("name"), "fabricante": di.get("manufacturer"), "modelo": di.get("model_name"),
                "version_cast": (d.get("build_info") or {}).get("cast_build_revision"),
                "sistema": (d.get("build_info") or {}).get("system_build_number")}.items() if v}
        except Exception:
            pass
    if 7000 in puertos:
        try:
            servidor, cuerpo = get(f"http://{ip}:7000/info", 20000)
            info["airplay"] = {"servidor": servidor}
            m = re.search(rb"<key>model</key>\s*<string>([^<]+)</string>", cuerpo)
            if m:
                info["airplay"]["modelo"] = m.group(1).decode("utf-8", "replace")
        except Exception:
            pass
    for p in (80, 8080):
        if p in puertos:
            try:
                servidor, cuerpo = get(f"http://{ip}:{p}/")
                t = re.search(rb"<title>([^<]{1,80})</title>", cuerpo, re.I)
                info[f"web_{p}"] = {k: v for k, v in {"servidor": servidor,
                                                       "titulo": t.group(1).decode("utf-8", "replace").strip() if t else ""}.items() if v}
            except Exception:
                pass
    return info


# ---------------------------------------------------------------------------
# Informe
# ---------------------------------------------------------------------------

def puntaje(e: dict) -> int:
    p = 0
    p += 4 * any(d["tipo"] == "MediaRenderer" or "AVTransport" in d["servicios"] for d in e["upnp"])
    p += 4 * any("Cast" in s["servicio"] for s in e["mdns"])
    p += 3 * (5555 in e["puertos"] or 6466 in e["puertos"])
    p += 2 * (7000 in e["puertos"] or any("AirPlay" in s["servicio"] for s in e["mdns"]))
    p += 2 * (7236 in e["puertos"])
    texto = " ".join([e["dns"]] + [d["nombre"] + d["fabricante"] + d["modelo"] for d in e["upnp"]]
                     + [s["nombre"] for s in e["mdns"]] + [json.dumps(e["extra"])])
    p += 3 * bool(PISTAS.search(texto))
    return p


def armar_informe(red, propia, puertos, macs, upnp, mdns, extra, dns, segundos) -> str:
    ips = sorted(set(puertos) | set(upnp) | set(mdns) | set(macs), key=lambda x: tuple(int(n) for n in x.split(".")))
    ips = [ip for ip in ips if ip != propia and ipaddress.ip_address(ip) in red]
    equipos = []
    for ip in ips:
        e = {"ip": ip, "mac": macs.get(ip, ""), "dns": dns.get(ip, ""), "puertos": sorted(puertos.get(ip, [])),
             "upnp": upnp.get(ip, []), "mdns": mdns.get(ip, []), "extra": extra.get(ip, {})}
        e["puntaje"] = puntaje(e)
        equipos.append(e)
    equipos.sort(key=lambda e: -e["puntaje"])
    L = [f"INFORME DE LA RED · Identificar proyector {VERSION}",
         f"Fecha: {time.strftime('%Y-%m-%d %H:%M')} · Esta PC: {propia} · Red: {red} · Búsqueda: {segundos:.0f} s",
         f"Equipos encontrados: {len(equipos)}", ""]
    for e in equipos:
        marca = "★ PROBABLEMENTE EL PROYECTOR · " if e["puntaje"] >= 4 and e is equipos[0] else (
            "☆ posible · " if e["puntaje"] >= 4 else "")
        L.append(f"── {marca}{e['ip']}" + (f"  ({e['dns']})" if e["dns"] else "") + (f"  MAC {e['mac']}" if e["mac"] else ""))
        for p in e["puertos"]:
            L.append(f"   puerto {p}: {PUERTOS.get(p, '')}")
        for d in e["upnp"]:
            L.append(f"   UPnP {d['tipo'] or '?'}: «{d['nombre']}» · {d['fabricante']} · {d['modelo']}"
                     + (f" · servicios: {', '.join(d['servicios'])}" if d["servicios"] else ""))
        for s in e["mdns"]:
            datos = {k: v for k, v in s["datos"].items() if k in ("fn", "md", "model", "manufacturer", "name", "id", "ve", "srcvers")}
            L.append(f"   {s['servicio']}: «{s['nombre']}» puerto {s['puerto']}" + (f" · {datos}" if datos else ""))
        for k, v in e["extra"].items():
            L.append(f"   {k}: {v}")
        if not (e["puertos"] or e["upnp"] or e["mdns"]):
            L.append("   (responde en la red, pero no ofrece servicios conocidos)")
        L.append("")
    L.append("Copia todo este texto y pégalo en el chat.")
    return "\n".join(L)


def escritorio() -> str:
    """La carpeta del escritorio de verdad (aunque esté en OneDrive o en otro idioma)."""
    if os.name == "nt":
        try:
            import ctypes
            guid = (ctypes.c_byte * 16)(*bytes.fromhex("3accbfb42cdb4c42b0297fe99a87c641"))  # FOLDERID_Desktop
            ruta = ctypes.c_wchar_p()
            if ctypes.windll.shell32.SHGetKnownFolderPath(guid, 0, None, ctypes.byref(ruta)) == 0:
                valor = ruta.value
                ctypes.windll.ole32.CoTaskMemFree(ruta)
                if valor and os.path.isdir(valor):
                    return valor
        except Exception:
            pass
    for nombre in ("Desktop", "Escritorio"):
        ruta = os.path.join(os.path.expanduser("~"), nombre)
        if os.path.isdir(ruta):
            return ruta
    return os.path.expanduser("~")


def al_portapapeles(texto: str) -> bool:
    try:
        if os.name == "nt":
            subprocess.run(["clip"], input=texto.encode("utf-16-le"), check=True, creationflags=NO_WINDOW)
            return True
    except (OSError, subprocess.CalledProcessError):
        pass
    return False


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Busca el proyector en la red y arma un informe.")
    ap.add_argument("--sin-pausa", action="store_true", help="no esperar Enter al terminar")
    ap.add_argument("--salida", help="dónde guardar el informe (por defecto, el escritorio)")
    ap.add_argument("--red", help="red a revisar, por ejemplo 192.168.0.0/24 (por defecto, la del WiFi)")
    args = ap.parse_args(argv)
    for flujo in (sys.stdout, sys.stderr):  # que un carácter raro nunca corte el programa
        try:
            flujo.reconfigure(errors="replace")
        except Exception:
            pass
    if os.name == "nt":
        os.system("")  # colores/acentos en la consola de Windows
    inicio = time.monotonic()
    log("Identificar proyector — revisando la red WiFi de la casa (tarda menos de un minuto)…\n")
    red = ipaddress.ip_network(args.red, strict=False) if args.red else mi_red()
    propia = P.local_ip_for("8.8.8.8") or ""
    if not red:
        log("No encontré ninguna red. ¿La PC está conectada al WiFi?")
        return 1
    resultados: dict = {}

    def correr(nombre, fn):
        try:
            resultados[nombre] = fn()
        except Exception as e:
            resultados[nombre] = {}
            log(f"  (la búsqueda {nombre} falló: {e})")
    hilos = [
        concurrent.futures.ThreadPoolExecutor(max_workers=1).submit(correr, "upnp", buscar_upnp),
        concurrent.futures.ThreadPoolExecutor(max_workers=1).submit(correr, "mdns", buscar_mdns),
    ]
    log(f"  · Probando los equipos de la red {red}…")
    puertos = barrer_puertos(red, propia)
    log(f"  · {len(puertos)} equipos responden; buscando DLNA, Chromecast, AirPlay y Android…")
    for h in hilos:
        h.result()
    macs = tabla_arp()
    upnp, mdns = resultados.get("upnp", {}), resultados.get("mdns", {})
    todos = set(puertos) | set(upnp) | set(mdns)
    with concurrent.futures.ThreadPoolExecutor(max_workers=32) as pool:
        dns = dict(zip(todos, pool.map(nombre_dns, todos)))
        extra = dict(zip(puertos, pool.map(lambda ip: preguntar_http(ip, puertos[ip]), puertos)))
    informe = armar_informe(red, propia, puertos, macs, upnp, mdns, extra, dns, time.monotonic() - inicio)
    destino = args.salida or os.path.join(escritorio(), "informe_proyector.txt")
    guardado = None
    try:  # primero se guarda, después se muestra
        with open(destino, "w", encoding="utf-8") as f:
            f.write(informe)
        guardado = destino
    except OSError as e:
        log(f"No pude guardar el informe ({e}).")
    log("\n" + informe)
    if guardado:
        log(f"\nGuardado en: {guardado}")
    if al_portapapeles(informe):
        log("También quedó copiado: en el chat pulsa Ctrl+V para pegarlo.")
    if not args.sin_pausa:
        try:
            input("\nPulsa Enter para cerrar…")
        except EOFError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())

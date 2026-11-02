#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Luces - controla desde la PC, por WiFi, las luces inteligentes de la app
Smart Life (Tuya): prender y apagar, brillo, tono (cálida/fría), colores y escenas.

    python luces.py                     abre la ventana
    python luces.py lista               muestra las luces y cómo están
    python luces.py encender [luz]      sin nombre: todas
    python luces.py apagar [luz]
    python luces.py brillo 40 [luz]
    python luces.py tono 0 [luz]        0 = cálida … 100 = fría
    python luces.py color rojo [luz]    o un color como #ff8800
    python luces.py escena cine
    python luces.py configurar          conecta tu cuenta (una sola vez)
    python luces.py buscar              vuelve a buscar las luces en la red

Necesita `pip install tinytuya` (Luces.bat lo instala solo).
"""

from __future__ import annotations

import argparse
import colorsys
import json
import logging
import os
import queue
import re
import sys
import tempfile
import threading
import time
import unicodedata
import urllib.parse
import urllib.request
import webbrowser
from concurrent.futures import ThreadPoolExecutor
from typing import Callable, Dict, List, Optional, Tuple

try:
    import tkinter as tk
    from tkinter import colorchooser, messagebox, ttk
except ImportError:  # pragma: no cover
    tk = None

APP = "Luces"
VERSION = "1.0"
LOG_PATH = os.path.join(tempfile.gettempdir(), "luces.log")
log = logging.getLogger("luces")

TUYA_URL = "https://platform.tuya.com"
REGIONES = [
    ("", "Automática (probar todas)"),
    ("us", "América Oeste (Argentina y casi toda Latinoamérica)"),
    ("us-e", "América Este"),
    ("eu", "Europa Central"),
    ("eu-w", "Europa Occidental"),
    ("in", "India"),
    ("sg", "Singapur"),
    ("cn", "China"),
]

# Categorías de Tuya que son luces (las demás, si tienen interruptor, se tratan como enchufes)
CATEGORIAS_LUZ = {"dj", "dd", "fwd", "dc", "xdd", "fsd", "tgq", "tgkg", "gyd", "sxd", "tyndj", "mbd", "dsd", "tyd"}
SWITCH_CODES = ("switch_led", "switch_led_1", "switch_1", "switch", "led_switch")
BRIGHT_CODES = ("bright_value_v2", "bright_value", "bright_value_1")
TEMP_CODES = ("temp_value_v2", "temp_value", "temp_value_1")
COLOUR_CODES = ("colour_data_v2", "colour_data", "colour_data_raw")
RANGOS_POR_DEFECTO = {"bright_value": (25, 255), "temp_value": (0, 255)}

_HSV_V2 = {"h": {"min": 0, "max": 360}, "s": {"min": 0, "max": 1000}, "v": {"min": 0, "max": 1000}}
MAPA_LUZ = {  # el "idioma" estándar de las luces Tuya modernas, por si la nube no lo informa
    "20": {"code": "switch_led", "type": "Boolean", "values": {}},
    "21": {"code": "work_mode", "type": "Enum", "values": {"range": ["white", "colour", "scene", "music"]}},
    "22": {"code": "bright_value_v2", "type": "Integer", "values": {"min": 10, "max": 1000}},
    "23": {"code": "temp_value_v2", "type": "Integer", "values": {"min": 0, "max": 1000}},
    "24": {"code": "colour_data_v2", "type": "Json", "values": _HSV_V2},
}
MAPA_ENCHUFE = {"1": {"code": "switch_1", "type": "Boolean", "values": {}}}

COLORES = {  # nombre: (tono 0-360, saturación 0-100)
    "rojo": (0, 100), "naranja": (28, 100), "amarillo": (52, 100), "verde": (120, 100),
    "cian": (180, 100), "azul": (230, 100), "violeta": (275, 100), "rosa": (325, 70),
}

ESCENAS_BASE = {
    "Cine": {"on": True, "modo": "blanco", "brillo": 8, "tono": 0},
    "Relax": {"on": True, "modo": "blanco", "brillo": 40, "tono": 10},
    "Lectura": {"on": True, "modo": "blanco", "brillo": 100, "tono": 65},
    "Día": {"on": True, "modo": "blanco", "brillo": 100, "tono": 100},
    "Noche": {"on": True, "modo": "color", "color": [25, 90], "brillo": 6},
    "Fiesta": {"on": True, "modo": "fiesta", "brillo": 100},   # un color vivo distinto cada vez
}


class LucesError(Exception):
    """Error con un mensaje pensado para el usuario."""


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

def config_dir() -> str:
    if os.environ.get("LUCES_DIR"):
        return os.environ["LUCES_DIR"]
    if os.name == "nt":
        return os.path.join(os.environ.get("APPDATA") or os.path.expanduser("~"), "Luces")
    return os.path.join(os.path.expanduser("~"), ".config", "luces")


def _leer_json(path: str, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def _escribir_json(path: str, data) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def normalizar(texto: str) -> str:
    """'Lámpara  Living' -> 'lampara living' (para buscar sin importar tildes)."""
    t = unicodedata.normalize("NFKD", texto or "")
    return " ".join("".join(c for c in t if not unicodedata.combining(c)).lower().split())


def es_error(r) -> bool:
    return isinstance(r, dict) and ("Error" in r or "Err" in r or r.get("success") is False)


def texto_error(r) -> str:
    if isinstance(r, dict):
        for k in ("Payload", "msg", "Error"):
            if r.get(k):
                return str(r[k])
    return str(r)


def parse_color(texto: str) -> Tuple[int, int]:
    """'rojo' o '#ff8800' -> (tono, saturación %)."""
    t = normalizar(texto)
    if t in COLORES:
        return COLORES[t]
    m = re.fullmatch(r"#?([0-9a-f]{6})", t)
    if not m:
        raise LucesError(f"No conozco el color «{texto}». Usa {', '.join(COLORES)} o un código como #ff8800.")
    r, g, b = (int(m.group(1)[i:i + 2], 16) / 255 for i in (0, 2, 4))
    h, s, _ = colorsys.rgb_to_hsv(r, g, b)
    return round(h * 360) % 360, round(s * 100)


def encode_colour(hsv: Dict[str, int], fmt: str) -> str:
    """Color en el formato que espera la luz por la red local."""
    h, s, v = int(hsv["h"]), int(hsv["s"]), int(hsv["v"])
    if fmt == "json":
        return json.dumps({"h": h, "s": s, "v": v})
    if fmt == "hex14":  # luces viejas: rrggbb + hhhh + ss + vv (s y v de 0 a 255)
        r, g, b = (round(x * 255) for x in colorsys.hsv_to_rgb(h / 360, s / 255, v / 255))
        return f"{r:02x}{g:02x}{b:02x}{h:04x}{s:02x}{v:02x}"
    return f"{h:04x}{s:04x}{v:04x}"


def decode_colour(raw) -> Tuple[Optional[Dict[str, int]], Optional[str]]:
    if isinstance(raw, dict):
        return {k: int(raw.get(k, 0)) for k in "hsv"}, "json"
    if not isinstance(raw, str):
        return None, None
    raw = raw.strip()
    if raw.startswith("{"):
        try:
            d = json.loads(raw)
            return {k: int(d.get(k, 0)) for k in "hsv"}, "json"
        except ValueError:
            return None, None
    if re.fullmatch(r"[0-9a-fA-F]{12}", raw):
        return {"h": int(raw[0:4], 16), "s": int(raw[4:8], 16), "v": int(raw[8:12], 16)}, "hex12"
    if re.fullmatch(r"[0-9a-fA-F]{14}", raw):
        return {"h": int(raw[6:10], 16), "s": int(raw[10:12], 16), "v": int(raw[12:14], 16)}, "hex14"
    return None, None


def _tinytuya():
    try:
        import tinytuya
        return tinytuya
    except ImportError:
        raise LucesError("Falta el componente «tinytuya». Abre Luces.bat (lo instala solo) "
                         "o escribe:  py -m pip install tinytuya") from None


# ---------------------------------------------------------------------------
# Una luz (o enchufe)
# ---------------------------------------------------------------------------

class Luz:
    def __init__(self, data: dict, hogar: "Hogar"):
        self.data = data
        self.hogar = hogar
        self.id = data["id"]
        self.nombre = (data.get("name") or self.id).strip()
        self.categoria = data.get("category", "")
        mapping = data.get("mapping") or (MAPA_LUZ if self.categoria in CATEGORIAS_LUZ else MAPA_ENCHUFE)
        self.mapping = {str(k): v for k, v in mapping.items() if isinstance(v, dict) and v.get("code")}
        self.dps_de = {v["code"]: k for k, v in self.mapping.items()}
        self.codigo_de = {k: v["code"] for k, v in self.mapping.items()}
        first = lambda codes: next((c for c in codes if c in self.dps_de), None)  # noqa: E731
        self.c_switch = first(SWITCH_CODES)
        self.c_bright = first(BRIGHT_CODES)
        self.c_temp = first(TEMP_CODES)
        self.c_colour = first(COLOUR_CODES)
        self.c_mode = "work_mode" if "work_mode" in self.dps_de else None
        self.state: Dict[str, object] = {}
        self.via = ""        # "local" (WiFi de la casa), "nube" o "" (sin respuesta)
        self.error = ""
        self.lock = threading.Lock()
        self._dev = None
        self._fmt: Optional[str] = None

    def __repr__(self):
        return f"<Luz {self.nombre!r} {self.id}>"

    # --- qué sabe hacer ---
    @property
    def es_luz(self) -> bool:
        return bool(self.c_bright or self.c_colour or self.categoria in CATEGORIAS_LUZ)

    @property
    def controlable(self) -> bool:
        return bool(self.c_switch or self.c_bright or self.c_colour)

    def _values(self, code: str) -> dict:
        v = self.mapping.get(self.dps_de.get(code, ""), {}).get("values")
        if isinstance(v, str):
            try:
                v = json.loads(v)
            except ValueError:
                v = {}
        return v if isinstance(v, dict) else {}

    def rango(self, code: str) -> Tuple[int, int]:
        v = self._values(code)
        if "min" in v and "max" in v:
            return int(v["min"]), int(v["max"])
        return RANGOS_POR_DEFECTO.get(code, (10, 1000) if "bright" in code else (0, 1000))

    def rangos_color(self) -> Dict[str, Tuple[int, int]]:
        v = self._values(self.c_colour or "")
        big = self.c_colour != "colour_data" or (v.get("s", {}).get("max", 255) >= 1000)
        default = {"h": (0, 360), "s": (0, 1000 if big else 255), "v": (0, 1000 if big else 255)}
        out = {}
        for k in "hsv":
            r = v.get(k) if isinstance(v.get(k), dict) else None
            out[k] = (int(r.get("min", default[k][0])), int(r.get("max", default[k][1]))) if r else default[k]
        return out

    def formato_color(self) -> str:
        if self._fmt:
            return self._fmt
        return "hex12" if self.rangos_color()["s"][1] >= 1000 else "hex14"

    @staticmethod
    def _pct(raw, lo, hi) -> int:
        if hi <= lo:
            return 100
        return max(0, min(100, round((float(raw) - lo) * 100 / (hi - lo))))

    @staticmethod
    def _raw(pct, lo, hi) -> int:
        return int(round(lo + (hi - lo) * max(0.0, min(100.0, float(pct))) / 100))

    # --- estado actual, en términos simples ---
    @property
    def encendida(self) -> Optional[bool]:
        v = self.state.get(self.c_switch) if self.c_switch else None
        return None if v is None else bool(v)

    @property
    def modo(self) -> str:
        if self.c_mode and self.state.get(self.c_mode):
            return "color" if self.state[self.c_mode] == "colour" else (
                "blanco" if self.state[self.c_mode] == "white" else str(self.state[self.c_mode]))
        if self.c_colour and not self.c_bright:
            return "color"
        return "blanco"

    @property
    def color(self) -> Optional[Tuple[int, int]]:
        hsv = self.state.get(self.c_colour) if self.c_colour else None
        if not isinstance(hsv, dict):
            return None
        r = self.rangos_color()
        return int(hsv["h"]) % 360, self._pct(hsv["s"], 0, r["s"][1])

    @property
    def brillo(self) -> Optional[int]:
        if self.modo == "color" and self.c_colour and isinstance(self.state.get(self.c_colour), dict):
            return max(1, self._pct(self.state[self.c_colour]["v"], 0, self.rangos_color()["v"][1]))
        if self.c_bright and self.state.get(self.c_bright) is not None:
            return max(1, self._pct(self.state[self.c_bright], *self.rango(self.c_bright)))
        return None

    @property
    def tono(self) -> Optional[int]:
        if self.c_temp and self.state.get(self.c_temp) is not None:
            return self._pct(self.state[self.c_temp], *self.rango(self.c_temp))
        return None

    def color_pantalla(self) -> str:
        """Color aproximado para dibujar la luz en la ventana."""
        if not self.encendida:
            return "#5b5b5b"
        if self.modo == "color" and self.color:
            h, s = self.color
            r, g, b = colorsys.hsv_to_rgb(h / 360, s / 100, 1)
        else:
            t = (self.tono if self.tono is not None else 50) / 100
            warm, cold = (255, 180, 107), (205, 225, 255)
            r, g, b = ((warm[i] + (cold[i] - warm[i]) * t) / 255 for i in range(3))
        return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))

    def foto(self) -> dict:
        """El estado actual como 'escena' (para guardarlo o restaurarlo)."""
        if self.encendida is None:
            return {}
        spec: dict = {"on": self.encendida}
        if self.encendida:
            if self.modo == "color" and self.color:
                spec.update(modo="color", color=list(self.color), brillo=self.brillo)
            else:
                spec.update(modo="blanco", brillo=self.brillo, tono=self.tono)
        return {k: v for k, v in spec.items() if v is not None}

    # --- órdenes ---
    def _hsv(self, h, s_pct, v_pct) -> Dict[str, int]:
        r = self.rangos_color()
        return {"h": int(h) % 360, "s": self._raw(s_pct, 0, r["s"][1]),
                "v": max(r["v"][0], self._raw(max(1, v_pct), 0, r["v"][1]))}

    def comandos(self, on=None, brillo=None, tono=None, color=None, blanco=False) -> Dict[str, object]:
        """Traduce 'brillo 40', 'color rojo', etc. a los códigos de esta luz."""
        cmds: Dict[str, object] = {}
        if on is not None and self.c_switch:
            cmds[self.c_switch] = bool(on)
        if on is False:
            return cmds
        en_color = self.modo == "color" and not blanco and tono is None
        if color is not None and self.c_colour:
            if self.c_mode:
                cmds[self.c_mode] = "colour"
            v = brillo if brillo is not None else (self.brillo or 100)  # mantiene el brillo que tenía
            cmds[self.c_colour] = self._hsv(color[0], color[1], v)
        elif brillo is not None and en_color and self.c_colour and self.color:
            cmds[self.c_colour] = self._hsv(self.color[0], self.color[1], brillo)
        elif brillo is not None or tono is not None or blanco:
            if self.c_bright or self.c_temp:
                if self.c_mode and (blanco or self.modo != "blanco"):
                    cmds[self.c_mode] = "white"
                if brillo is not None and self.c_bright:
                    cmds[self.c_bright] = self._raw(max(1, brillo), *self.rango(self.c_bright))
                if tono is not None and self.c_temp:
                    cmds[self.c_temp] = self._raw(tono, *self.rango(self.c_temp))
            elif self.c_colour:  # luz sólo de colores: el "blanco" es color sin saturación
                if self.c_mode:
                    cmds[self.c_mode] = "colour"
                cmds[self.c_colour] = self._hsv(0, 0, brillo if brillo is not None else 100)
        if cmds and on is None and self.c_switch and self.encendida is False and self.c_switch not in cmds:
            cmds[self.c_switch] = True  # mover el brillo de una luz apagada la prende
        return cmds

    def aplicar(self, spec: dict) -> None:
        if not spec:
            return
        if spec.get("on") is False:
            self.enviar(self.comandos(on=False))
        elif spec.get("modo") == "color" and self.c_colour and spec.get("color"):
            self.enviar(self.comandos(on=True, color=spec["color"], brillo=spec.get("brillo")))
        else:
            self.enviar(self.comandos(on=True, brillo=spec.get("brillo"), tono=spec.get("tono"),
                                      blanco=bool(self.c_bright or self.c_colour)))

    # --- comunicación ---
    def _local(self):
        ip, key = self.data.get("ip"), self.data.get("key")
        if not ip or not key:
            return None
        if self._dev is None:
            tt = _tinytuya()
            dev = tt.Device(self.id, ip, key, version=float(self.data.get("version") or 3.3),
                            connection_timeout=3, connection_retry_limit=1, connection_retry_delay=1,
                            port=int(self.data.get("port") or 6668))
            dev.set_socketPersistent(True)  # más rápido al mover el brillo
            self._dev = dev
        return self._dev

    def _cerrar_local(self):
        if self._dev is not None:
            try:
                self._dev.close()
            except Exception:
                pass
            self._dev = None

    def _al_local(self, code, value):
        if code == self.c_colour and isinstance(value, dict):
            return encode_colour(value, self.formato_color())
        return value

    def _leer_local(self, dps: dict) -> None:
        for k, v in (dps or {}).items():
            code = self.codigo_de.get(str(k))
            if not code:
                continue
            if code == self.c_colour:
                hsv, fmt = decode_colour(v)
                if hsv is None:
                    continue
                self._fmt, v = fmt, hsv
            self.state[code] = v

    def _leer_nube(self, items) -> None:
        for it in items or []:
            code, v = it.get("code"), it.get("value")
            if code == self.c_colour:
                v, _ = decode_colour(v)
                if v is None:
                    continue
            if code:
                self.state[code] = v

    def enviar(self, cmds: Dict[str, object]) -> None:
        if not cmds:
            return
        if self.data.get("demo"):  # luz de prueba: sólo cambia en la pantalla
            self.state.update(cmds)
            self.via, self.error = "demo", ""
            return
        with self.lock:
            problemas = []
            dev = self._local()
            if dev is not None:
                data = {self.dps_de[c]: self._al_local(c, v) for c, v in cmds.items() if c in self.dps_de}
                try:
                    r = dev.set_multiple_values(data)
                except Exception as e:
                    r = {"Error": str(e)}
                if not es_error(r):
                    self.state.update(cmds)
                    if isinstance(r, dict):
                        self._leer_local(r.get("dps"))
                    self.via, self.error = "local", ""
                    return
                problemas.append(f"WiFi: {texto_error(r)}")
                self._cerrar_local()
            nube = self.hogar.nube()
            if nube is not None:
                r = nube.sendcommand(self.id, {"commands": [{"code": c, "value": v} for c, v in cmds.items()]})
                if not es_error(r):
                    self.state.update(cmds)
                    self.via, self.error = "nube", ""
                    return
                problemas.append(f"nube: {texto_error(r)}")
            self.via = ""
            self.error = "; ".join(problemas) or "no sé su dirección en la red"
            raise LucesError(f"«{self.nombre}» no responde ({self.error}).")

    def actualizar(self) -> None:
        if self.data.get("demo"):
            self.via = "demo"
            return
        with self.lock:
            problemas = []
            dev = self._local()
            if dev is not None:
                try:
                    r = dev.status()
                except Exception as e:
                    r = {"Error": str(e)}
                if isinstance(r, dict) and not es_error(r) and "dps" in r:
                    self._leer_local(r["dps"])
                    self.via, self.error = "local", ""
                    return
                problemas.append(f"WiFi: {texto_error(r)}")
                self._cerrar_local()
            nube = self.hogar.nube()
            if nube is not None:
                r = nube.getstatus(self.id)
                if not es_error(r) and isinstance(r, dict):
                    self._leer_nube(r.get("result"))
                    self.via, self.error = "nube", ""
                    return
                problemas.append(f"nube: {texto_error(r)}")
            self.via = ""
            self.error = "; ".join(problemas) or "no sé su dirección en la red"


# ---------------------------------------------------------------------------
# Todas las luces de la casa
# ---------------------------------------------------------------------------

class Hogar:
    def __init__(self, carpeta: Optional[str] = None):
        self.dir = carpeta or config_dir()
        self.config = _leer_json(os.path.join(self.dir, "config.json"), {})
        datos = _leer_json(os.path.join(self.dir, "dispositivos.json"), [])
        self.todas = [Luz(d, self) for d in datos if isinstance(d, dict) and d.get("id")]
        self.todas = [x for x in self.todas if x.controlable]
        self.todas.sort(key=lambda x: (not x.es_luz, normalizar(x.nombre)))
        self._nube = None
        self._nube_fallo = 0.0
        self._nube_lock = threading.Lock()

    @property
    def configurado(self) -> bool:
        return bool(self.todas)

    @property
    def luces(self) -> List[Luz]:
        return [x for x in self.todas if x.es_luz]

    def guardar(self) -> None:
        _escribir_json(os.path.join(self.dir, "config.json"), self.config)
        _escribir_json(os.path.join(self.dir, "dispositivos.json"), [x.data for x in self.todas])

    def nube(self):
        """Conexión con la nube de Tuya (plan B si una luz no responde por WiFi)."""
        cfg = self.config
        if not (cfg.get("api_key") and cfg.get("api_secret") and cfg.get("region")):
            return None
        with self._nube_lock:
            if self._nube is not None:
                return self._nube
            if time.time() - self._nube_fallo < 60:
                return None
            try:
                c = _tinytuya().Cloud(apiRegion=cfg["region"], apiKey=cfg["api_key"], apiSecret=cfg["api_secret"])
                if not getattr(c, "token", None):
                    raise LucesError(texto_error(getattr(c, "error", "sin respuesta")))
                self._nube = c
            except Exception as e:
                log.info("Nube de Tuya no disponible: %s", e)
                self._nube_fallo = time.time()
            return self._nube

    def buscar(self, nombre: Optional[str]) -> List[Luz]:
        """Luces cuyo nombre contiene `nombre`; sin nombre (o 'todas'): todas las luces."""
        if not nombre or normalizar(nombre) in ("todas", "todo", "todos"):
            return self.luces
        n = normalizar(nombre)
        exactas = [x for x in self.todas if normalizar(x.nombre) == n]
        found = exactas or [x for x in self.todas if n in normalizar(x.nombre)]
        if not found:
            raise LucesError(f"No hay ninguna luz que se llame «{nombre}». "
                             f"Tengo: {', '.join(x.nombre for x in self.todas)}")
        return found

    # --- configuración inicial ---
    def conectar(self, api_key: str, api_secret: str, region: str = "",
                 avisar: Callable[[str], None] = lambda m: None) -> int:
        """Trae de la nube de Tuya las luces de la cuenta Smart Life y sus claves."""
        tt = _tinytuya()
        api_key, api_secret = api_key.strip(), api_secret.strip()
        if not api_key or not api_secret:
            raise LucesError("Faltan el Access ID y el Access Secret.")
        regiones = [region] if region else [r for r, _ in REGIONES if r]
        ultimo = ""
        for reg in regiones:
            avisar(f"Probando la región {dict(REGIONES)[reg].split(' (')[0]}…")
            try:
                c = tt.Cloud(apiRegion=reg, apiKey=api_key, apiSecret=api_secret)
            except Exception as e:
                ultimo = str(e)
                continue
            if not getattr(c, "token", None):
                ultimo = texto_error(getattr(c, "error", ""))
                if re.search(r"sign invalid|clientId is invalid|1004|1005", ultimo, re.I):
                    raise LucesError("El Access ID o el Access Secret no son correctos. "
                                     "Cópialos de nuevo desde la página del proyecto (Overview).")
                continue
            try:
                devs = c.getdevices(include_map=True, oldlist=[x.data for x in self.todas])
            except Exception as e:
                devs, ultimo = [], str(e)
            raw = getattr(c, "getdevices_raw", {}) or {}
            if es_error(devs):
                ultimo = texto_error(devs)
                continue
            if not devs:
                ultimo = raw.get("msg") or ultimo or "la cuenta no tiene dispositivos en esta región"
                continue
            viejos = {x.id: x.data for x in self.todas}
            nuevos = []
            for d in devs:
                if not isinstance(d, dict) or not d.get("id"):
                    continue
                for k in ("ip", "version", "port"):  # conservar lo que ya sabíamos de la red
                    if viejos.get(d["id"], {}).get(k) and not d.get(k):
                        d[k] = viejos[d["id"]][k]
                if d.get("ip") and not re.match(r"^(10|172\.(1[6-9]|2\d|3[01])|192\.168)\.", str(d["ip"])):
                    d.pop("ip")  # la nube a veces informa la IP pública: no sirve en la casa
                nuevos.append(d)
            self.config.update(api_key=api_key, api_secret=api_secret, region=reg)
            self.todas = [Luz(d, self) for d in nuevos]
            self.todas = [x for x in self.todas if x.controlable]
            self.todas.sort(key=lambda x: (not x.es_luz, normalizar(x.nombre)))
            self._nube, self._nube_fallo = c, 0.0
            self.guardar()
            avisar(f"Encontré {len(self.todas)} dispositivos en tu cuenta.")
            return len(self.todas)
        hint = ""
        if re.search(r"permission|1106|expire|28841", ultimo, re.I):
            hint = ("\n\nRevisa en la página de Tuya que la cuenta de Smart Life esté vinculada al proyecto "
                    "(pestaña Devices → Link App Account) y que el servicio «IoT Core» esté activo.")
        raise LucesError(f"No pude traer las luces de tu cuenta: {ultimo}{hint}")

    def escanear(self, segundos: int = 8) -> int:
        """Busca las luces en la red de la casa para hablarles directo (sin internet)."""
        if not self.todas or all(x.data.get("demo") for x in self.todas):
            return 0
        _tinytuya()  # avisa claramente si falta instalarlo
        from tinytuya import scanner
        known = [{"id": x.id, "name": x.nombre, "key": x.data.get("key", ""), "mac": x.data.get("mac", "")}
                 for x in self.todas]
        try:
            found = scanner.devices(verbose=False, scantime=segundos, color=False, poll=False, byID=True,
                                    wantids=[x.id for x in self.todas], tuyadevices=known,
                                    maxdevices=len(self.todas)) or {}
        except Exception as e:
            log.warning("No se pudo buscar en la red: %s", e)
            return 0
        n = 0
        for luz in self.todas:
            info = found.get(luz.id)
            if not info or not info.get("ip"):
                continue
            n += 1
            if luz.data.get("ip") != info["ip"] or str(luz.data.get("version")) != str(info.get("version")):
                luz.data["ip"] = info["ip"]
                if info.get("version"):
                    luz.data["version"] = str(info["version"])
                luz._cerrar_local()
        self.guardar()
        log.info("En la red encontré %d de %d dispositivos", n, len(self.todas))
        return n

    # --- acciones sobre varias luces ---
    def _en_paralelo(self, luces: List[Luz], fn: Callable[[Luz], None]) -> List[str]:
        errores: List[str] = []
        if not luces:
            return errores
        with ThreadPoolExecutor(max_workers=min(8, len(luces))) as pool:
            for luz, fut in [(x, pool.submit(fn, x)) for x in luces]:
                try:
                    fut.result()
                except LucesError as e:
                    errores.append(str(e))
                except Exception as e:  # pragma: no cover
                    log.exception("Error con %s", luz.nombre)
                    errores.append(f"«{luz.nombre}»: {e}")
        return errores

    def encender_todas(self, on: bool = True) -> List[str]:
        return self._en_paralelo(self.luces, lambda l: l.enviar(l.comandos(on=on)))

    def actualizar_todo(self) -> List[str]:
        self._en_paralelo(self.todas, Luz.actualizar)
        return [f"«{x.nombre}» no responde" for x in self.todas if not x.via]

    def escenas(self) -> Dict[str, dict]:
        out = dict(ESCENAS_BASE)
        out.update(_leer_json(os.path.join(self.dir, "escenas.json"), {}))
        return out

    def aplicar_escena(self, nombre: str, luces: Optional[List[Luz]] = None) -> List[str]:
        escenas = self.escenas()
        clave = next((k for k in escenas if normalizar(k) == normalizar(nombre)), None)
        if clave is None:
            raise LucesError(f"No existe la escena «{nombre}». Hay: {', '.join(escenas)}")
        spec = escenas[clave]
        luces = self.luces if luces is None else luces
        if "luces" in spec:  # escena guardada: cada luz como estaba
            return self.restaurar(spec["luces"])
        if spec.get("modo") == "fiesta":
            import random
            colores = [l for l in luces if l.c_colour]
            inicio = random.choice([0, 30, 120, 190, 230, 280, 320])   # con una sola luz: un color distinto cada vez
            hues = {l.id: (inicio + round(i * 360 / max(1, len(colores)))) % 360 for i, l in enumerate(colores)}
            return self._en_paralelo(luces, lambda l: l.aplicar(
                {"on": True, "modo": "color", "color": [hues[l.id], 100], "brillo": spec.get("brillo", 100)}
                if l.id in hues else {"on": True, "modo": "blanco", "brillo": spec.get("brillo", 100)}))
        return self._en_paralelo(luces, lambda l: l.aplicar(spec))

    def foto(self) -> Dict[str, dict]:
        return {x.id: x.foto() for x in self.luces if x.foto()}

    def restaurar(self, foto: Dict[str, dict]) -> List[str]:
        luces = [x for x in self.todas if x.id in foto]
        return self._en_paralelo(luces, lambda l: l.aplicar(foto[l.id]))

    def guardar_escena(self, nombre: str) -> None:
        nombre = nombre.strip()
        if not nombre:
            raise LucesError("Ponle un nombre a la escena.")
        path = os.path.join(self.dir, "escenas.json")
        propias = _leer_json(path, {})
        propias[nombre] = {"luces": self.foto()}
        _escribir_json(path, propias)

    def borrar_escena(self, nombre: str) -> None:
        path = os.path.join(self.dir, "escenas.json")
        propias = _leer_json(path, {})
        propias.pop(nombre, None)
        _escribir_json(path, propias)


# ---------------------------------------------------------------------------
# Ventana
# ---------------------------------------------------------------------------

GUIA = """1.  Entra a platform.tuya.com y crea una cuenta gratis.

2.  Arriba elige Cloud → Development → «Create Cloud Project».
     • Nombre: el que quieras (por ejemplo «Luces casa»).
     • Industry: Smart Home.  Development Method: Smart Home.
     • Data Center: «Western America» si estás en Latinoamérica
       (tiene que ser la región de tu cuenta de Smart Life).

3.  En la pantalla de servicios que aparece, deja los que vienen
     marcados (IoT Core, Authorization) y confirma.

4.  Dentro del proyecto: pestaña «Devices» → «Link App Account»
     → «Add App Account». Aparece un código QR.

5.  En el celular, en Smart Life: pestaña «Yo» → ícono de escanear
     (arriba a la derecha) → escanea el QR → Confirmar.

6.  En la pestaña «Overview» del proyecto copia «Access ID»
     y «Access Secret» y pégalos aquí abajo.

Es una sola vez. Después las luces se manejan directo por el WiFi
de tu casa. La clave queda guardada sólo en esta PC."""


class Tarjeta:
    """El cuadrito de una luz en la ventana."""

    def __init__(self, app: "App", parent, luz: Luz):
        self.app, self.luz = app, luz
        self._pendiente: Dict[str, object] = {}
        self._after = None
        self._arrastrando = False
        f = self.frame = ttk.Frame(parent, padding=10, style="Card.TFrame")
        f.columnconfigure(1, weight=1)

        self.foco = tk.Canvas(f, width=30, height=30, highlightthickness=0, bg=app.card_bg)
        self.foco.grid(row=0, column=0, rowspan=2, sticky="n", padx=(0, 10))
        self.circulo = self.foco.create_oval(3, 3, 27, 27, fill="#5b5b5b", outline="")
        ttk.Label(f, text=luz.nombre, style="CardTitle.TLabel").grid(row=0, column=1, sticky="w")
        self.boton = ttk.Button(f, text="Encender", width=10, command=self.alternar)
        self.boton.grid(row=0, column=2, sticky="e")
        self.estado = ttk.Label(f, text="…", style="CardHint.TLabel")
        self.estado.grid(row=1, column=1, columnspan=2, sticky="w")

        row = 2
        self.brillo = self.tono = None
        if luz.c_bright or luz.c_colour:
            ttk.Label(f, text="Brillo", style="Card.TLabel").grid(row=row, column=0, sticky="w", pady=(8, 0))
            self.brillo = ttk.Scale(f, from_=1, to=100, orient="horizontal",
                                    command=lambda v: self._mover("brillo", v))
            self.brillo.grid(row=row, column=1, columnspan=2, sticky="ew", pady=(8, 0))
            self._soltar(self.brillo, "brillo")
            row += 1
        if luz.c_temp:
            ttk.Label(f, text="Tono", style="Card.TLabel").grid(row=row, column=0, sticky="w")
            self.tono = ttk.Scale(f, from_=0, to=100, orient="horizontal",
                                  command=lambda v: self._mover("tono", v))
            self.tono.grid(row=row, column=1, columnspan=2, sticky="ew")
            self._soltar(self.tono, "tono")
            leyenda = ttk.Frame(f, style="Card.TFrame")
            leyenda.grid(row=row + 1, column=1, columnspan=2, sticky="ew")
            ttk.Label(leyenda, text="cálida", style="CardHint.TLabel").pack(side="left")
            ttk.Label(leyenda, text="fría", style="CardHint.TLabel").pack(side="right")
            row += 2
        if luz.c_colour:
            colores = tk.Frame(f, bg=app.card_bg)
            colores.grid(row=row, column=0, columnspan=3, sticky="w", pady=(8, 0))
            def muestra(color, accion, texto=""):
                sw = tk.Label(colores, bg=color, width=2, text=texto, cursor="hand2", relief="flat",
                              highlightthickness=1, highlightbackground="#888888")
                sw.pack(side="left", padx=2, ipady=2)
                sw.bind("<Button-1>", lambda e: accion())
            if luz.c_bright or luz.c_temp:  # cuadrito blanco = volver a luz blanca
                muestra("#fff4e0", lambda: self.app.mandar(self.luz, blanco=True, brillo=self.luz.brillo or 100))
            for nombre, (h, s) in COLORES.items():
                r, g, b = colorsys.hsv_to_rgb(h / 360, s / 100, 1)
                hexc = "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))
                muestra(hexc, lambda c=(h, s): self.app.mandar(self.luz, color=c))
            muestra(self.app.card_bg, self.elegir_color, "…")

    def _soltar(self, scale, campo):
        scale.bind("<ButtonPress-1>", lambda e: setattr(self, "_arrastrando", True))
        scale.bind("<ButtonRelease-1>", lambda e: self._fin(campo, scale.get()))

    def _mover(self, campo, valor):
        if not self._arrastrando:
            return
        self._pendiente[campo] = round(float(valor))
        if self._after is None:  # mientras se arrastra, se manda como mucho cada 0,35 s
            self._after = self.frame.after(350, self._enviar_pendiente)

    def _fin(self, campo, valor):
        self._arrastrando = False
        self._pendiente[campo] = round(float(valor))
        if self._after is not None:
            self.frame.after_cancel(self._after)
        self._enviar_pendiente()

    def _enviar_pendiente(self):
        self._after = None
        if self._pendiente:
            datos, self._pendiente = self._pendiente, {}
            if "tono" in datos:
                datos["blanco"] = True
            self.app.mandar(self.luz, **datos)

    def alternar(self):
        self.app.mandar(self.luz, on=not self.luz.encendida)

    def elegir_color(self):
        actual = self.luz.color_pantalla() if self.luz.encendida else "#ff8800"
        res = colorchooser.askcolor(color=actual, parent=self.app.root, title=f"Color de {self.luz.nombre}")
        if res and res[1]:
            self.app.mandar(self.luz, color=parse_color(res[1]))

    def refrescar(self):
        luz = self.luz
        self.foco.itemconfigure(self.circulo, fill=luz.color_pantalla())
        on = luz.encendida
        self.boton.configure(text="Apagar" if on else "Encender")
        if not luz.via:
            txt = "Sin conexión" + (f" — {luz.error[:60]}" if luz.error else "")
        else:
            partes = ["Encendida" if on else "Apagada"]
            if on and luz.brillo is not None:
                partes.append(f"{luz.brillo}%")
            if on and luz.modo == "color":
                partes.append("color")
            partes.append("por WiFi" if luz.via == "local" else "por internet")
            txt = " · ".join(partes)
        self.estado.configure(text=txt)
        if not self._arrastrando:
            if self.brillo is not None and luz.brillo is not None:
                self.brillo.set(luz.brillo)
            if self.tono is not None and luz.tono is not None:
                self.tono.set(luz.tono)


class App:
    REFRESCO_MS = 20000

    def __init__(self, root, hogar: Optional[Hogar] = None):
        self.root = root
        self.hogar = hogar or Hogar()
        self.pool = ThreadPoolExecutor(max_workers=6)
        self.cola: queue.Queue = queue.Queue()
        self.tarjetas: Dict[str, Tarjeta] = {}
        root.title("Luces – Smart Life desde la PC")
        self._estilo()
        self._armar()
        root.after(100, self._bombear)
        root.after(self.REFRESCO_MS, self._refresco_periodico)
        if self.hogar.configurado:
            self.mostrar_luces()
            self.actualizar(buscar_red=True)
        else:
            self.mostrar_bienvenida()

    # --- hilos ---
    def _post(self, fn, *args):
        self.cola.put((fn, args))

    def _bombear(self):
        try:
            while True:
                fn, args = self.cola.get_nowait()
                try:
                    fn(*args)
                except Exception:
                    log.exception("Error en la ventana")
        except queue.Empty:
            pass
        self.root.after(100, self._bombear)

    def bg(self, trabajo, listo=None):
        def run():
            try:
                res = trabajo()
            except LucesError as e:
                self._post(self.aviso, str(e), True)
            except Exception as e:
                log.exception("Error")
                self._post(self.aviso, f"Error inesperado: {e}", True)
            else:
                if listo:
                    self._post(listo, res)
        self.pool.submit(run)

    # --- armado ---
    def _estilo(self):
        st = ttk.Style(self.root)
        if os.name != "nt" and "clam" in st.theme_names():
            st.theme_use("clam")
        self.card_bg = "#ffffff"
        fam = "Segoe UI" if os.name == "nt" else "TkDefaultFont"
        st.configure("Card.TFrame", background=self.card_bg, relief="solid", borderwidth=1)
        st.configure("Card.TLabel", background=self.card_bg)
        st.configure("CardTitle.TLabel", background=self.card_bg, font=(fam, 11, "bold"))
        st.configure("CardHint.TLabel", background=self.card_bg, foreground="#666666")
        st.configure("Title.TLabel", font=(fam, 14, "bold"))
        st.configure("Hint.TLabel", foreground="#666666")
        st.configure("Big.TButton", font=(fam, 11, "bold"), padding=(16, 8))
        st.configure("Error.TLabel", foreground="#b00020")
        st.configure("Scene.TButton", padding=(6, 3), width=-8)

    def _armar(self):
        r = self.root
        r.columnconfigure(0, weight=1)
        r.rowconfigure(2, weight=1)
        top = ttk.Frame(r, padding=(12, 10, 12, 0))
        top.grid(row=0, column=0, sticky="ew")
        ttk.Button(top, text="Encender todas", command=lambda: self.todas(True)).pack(side="left")
        ttk.Button(top, text="Apagar todas", command=lambda: self.todas(False)).pack(side="left", padx=6)
        ttk.Button(top, text="Configurar…", command=self.configurar).pack(side="right")
        ttk.Button(top, text="Actualizar", command=lambda: self.actualizar(buscar_red=True)).pack(side="right", padx=6)

        self.barra_escenas = ttk.Frame(r, padding=(12, 8, 12, 0))
        self.barra_escenas.grid(row=1, column=0, sticky="ew")

        cont = ttk.Frame(r)
        cont.grid(row=2, column=0, sticky="nsew", padx=12, pady=10)
        cont.columnconfigure(0, weight=1)
        cont.rowconfigure(0, weight=1)
        self.canvas = tk.Canvas(cont, highlightthickness=0, borderwidth=0)
        barra = ttk.Scrollbar(cont, orient="vertical", command=self.canvas.yview)
        self.canvas.configure(yscrollcommand=barra.set)
        self.canvas.grid(row=0, column=0, sticky="nsew")
        barra.grid(row=0, column=1, sticky="ns")
        self.zona = ttk.Frame(self.canvas)
        self._ventana = self.canvas.create_window((0, 0), window=self.zona, anchor="nw")
        self.zona.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.bind("<Configure>", lambda e: self.canvas.itemconfigure(self._ventana, width=e.width))
        self.canvas.bind_all("<MouseWheel>", lambda e: self.canvas.yview_scroll(-1 if e.delta > 0 else 1, "units"))
        self.canvas.bind_all("<Button-4>", lambda e: self.canvas.yview_scroll(-1, "units"))
        self.canvas.bind_all("<Button-5>", lambda e: self.canvas.yview_scroll(1, "units"))

        self.estado = ttk.Label(r, text="", padding=(14, 0, 14, 10))
        self.estado.grid(row=3, column=0, sticky="ew")
        r.geometry("820x660")
        r.minsize(560, 420)

    def aviso(self, texto: str, error: bool = False):
        self.estado.configure(text=texto, style="Error.TLabel" if error else "TLabel")

    def _limpiar(self):
        for w in self.zona.winfo_children():
            w.destroy()
        self.tarjetas.clear()

    def mostrar_bienvenida(self):
        self._limpiar()
        self._armar_escenas()
        f = ttk.Frame(self.zona, padding=30)
        f.pack(fill="both", expand=True)
        ttk.Label(f, text="Conecta tus luces de Smart Life", style="Title.TLabel").pack(anchor="w")
        ttk.Label(f, wraplength=560, justify="left", text=(
            "Smart Life no deja que otros programas manejen las luces sin permiso. Para dárselo hay que "
            "crear, gratis y una sola vez, un acceso en la página de Tuya (la empresa que hace Smart Life). "
            "Son unos 10 minutos y la guía te lleva paso a paso.")).pack(anchor="w", pady=(10, 16))
        ttk.Button(f, text="Empezar", style="Big.TButton", command=self.configurar).pack(anchor="w")

    def mostrar_luces(self):
        self._limpiar()
        self._armar_escenas()
        if not self.hogar.todas:
            self.mostrar_bienvenida()
            return
        self.zona.columnconfigure(0, weight=1, uniform="c")
        self.zona.columnconfigure(1, weight=1, uniform="c")
        for i, luz in enumerate(self.hogar.todas):
            t = Tarjeta(self, self.zona, luz)
            t.frame.grid(row=i // 2, column=i % 2, sticky="nsew", padx=5, pady=5)
            t.refrescar()
            self.tarjetas[luz.id] = t

    def _armar_escenas(self):
        for w in self.barra_escenas.winfo_children():
            w.destroy()
        ttk.Label(self.barra_escenas, text="Escenas:").grid(row=0, column=0, sticky="w", padx=(0, 6))
        botones = [(n, lambda n=n: self.escena(n)) for n in self.hogar.escenas()]
        botones.append(("+ Guardar actual", self.guardar_escena))
        por_fila = 7
        for i, (texto, accion) in enumerate(botones):
            ttk.Button(self.barra_escenas, text=texto, style="Scene.TButton", command=accion).grid(
                row=i // por_fila, column=1 + i % por_fila, sticky="ew", padx=2, pady=2)

    # --- acciones ---
    def refrescar_tarjetas(self, _=None):
        for t in self.tarjetas.values():
            t.refrescar()

    def mandar(self, luz: Luz, **kw):
        cmds = luz.comandos(**kw)
        if not cmds:
            return
        self.bg(lambda: luz.enviar(cmds), listo=lambda _: (self.tarjetas[luz.id].refrescar(), self.aviso("")))
        # se refresca igual aunque falle, para mostrar el error en la tarjeta
        self.root.after(4000, lambda: self.tarjetas.get(luz.id) and self.tarjetas[luz.id].refrescar())

    def todas(self, on: bool):
        if not self.hogar.configurado:
            return
        self.aviso("Encendiendo…" if on else "Apagando…")
        self.bg(lambda: self.hogar.encender_todas(on), listo=self._fin_grupal)

    def escena(self, nombre: str):
        if not self.hogar.configurado:
            return
        self.aviso(f"Escena «{nombre}»…")
        self.bg(lambda: self.hogar.aplicar_escena(nombre), listo=self._fin_grupal)

    def _fin_grupal(self, errores):
        self.refrescar_tarjetas()
        if errores:
            self.aviso("; ".join(errores)[:200], True)
        else:
            self.aviso("Listo.")

    def guardar_escena(self):
        if not self.hogar.configurado:
            return
        from tkinter import simpledialog
        nombre = simpledialog.askstring(APP, "Nombre para la escena (guarda cómo están ahora todas las luces):",
                                        parent=self.root)
        if nombre:
            self.hogar.guardar_escena(nombre)
            self._armar_escenas()
            self.aviso(f"Escena «{nombre.strip()}» guardada.")

    def actualizar(self, buscar_red: bool = False):
        self.aviso("Buscando las luces en la red…" if buscar_red else "Actualizando…")

        def trabajo():
            if buscar_red:
                self.hogar.escanear(8)
            return self.hogar.actualizar_todo()
        self.bg(trabajo, listo=self._fin_actualizar)

    def _fin_actualizar(self, problemas):
        self.refrescar_tarjetas()
        ok = sum(1 for x in self.hogar.todas if x.via)
        if problemas:
            self.aviso(f"{ok} de {len(self.hogar.todas)} responden. " + "; ".join(problemas)[:150], True)
        else:
            self.aviso(f"Listo: {ok} dispositivos conectados.")

    def _refresco_periodico(self):
        self.root.after(self.REFRESCO_MS, self._refresco_periodico)
        if self.hogar.configurado and not any(t._arrastrando for t in self.tarjetas.values()):
            self.bg(self.hogar.actualizar_todo, listo=lambda _: self.refrescar_tarjetas())

    def configurar(self):
        Configuracion(self)

    def close(self):
        self.pool.shutdown(wait=False)
        self.root.destroy()


class Configuracion:
    """Ventana para conectar la cuenta de Smart Life (una sola vez)."""

    def __init__(self, app: App):
        self.app = app
        cfg = app.hogar.config
        w = self.win = tk.Toplevel(app.root)
        w.title("Conectar con Smart Life")
        w.transient(app.root)
        w.columnconfigure(1, weight=1)
        ttk.Label(w, text="Conectar con Smart Life", style="Title.TLabel").grid(
            row=0, column=0, columnspan=3, sticky="w", padx=16, pady=(14, 6))
        guia = tk.Text(w, height=24, width=66, wrap="word", relief="flat", padx=10, pady=8,
                       font="TkDefaultFont")
        guia.insert("1.0", GUIA)
        guia.configure(state="disabled")
        guia.grid(row=1, column=0, columnspan=3, sticky="nsew", padx=16)
        ttk.Button(w, text="Abrir platform.tuya.com", command=lambda: webbrowser.open(TUYA_URL)).grid(
            row=2, column=0, columnspan=3, sticky="w", padx=16, pady=(6, 10))

        self.key = tk.StringVar(value=cfg.get("api_key", ""))
        self.secret = tk.StringVar(value=cfg.get("api_secret", ""))
        ttk.Label(w, text="Access ID:").grid(row=3, column=0, sticky="w", padx=(16, 6))
        ttk.Entry(w, textvariable=self.key).grid(row=3, column=1, columnspan=2, sticky="ew", padx=(0, 16))
        ttk.Label(w, text="Access Secret:").grid(row=4, column=0, sticky="w", padx=(16, 6), pady=4)
        self.e_secret = ttk.Entry(w, textvariable=self.secret, show="•")
        self.e_secret.grid(row=4, column=1, sticky="ew", pady=4)
        self.ver = tk.BooleanVar(value=False)
        ttk.Checkbutton(w, text="mostrar", variable=self.ver,
                        command=lambda: self.e_secret.configure(show="" if self.ver.get() else "•")).grid(
            row=4, column=2, sticky="w", padx=(6, 16))
        ttk.Label(w, text="Región:").grid(row=5, column=0, sticky="w", padx=(16, 6))
        self.region = ttk.Combobox(w, state="readonly", values=[t for _, t in REGIONES])
        actual = cfg.get("region", "")
        self.region.current(next((i for i, (r, _) in enumerate(REGIONES) if r == actual), 0))
        self.region.grid(row=5, column=1, columnspan=2, sticky="ew", padx=(0, 16))
        self.msg = ttk.Label(w, text="", wraplength=520, justify="left")
        self.msg.grid(row=6, column=0, columnspan=3, sticky="w", padx=16, pady=(10, 0))
        self.boton = ttk.Button(w, text="Conectar", style="Big.TButton", command=self.conectar)
        self.boton.grid(row=7, column=0, columnspan=3, pady=14)

    def conectar(self):
        region = REGIONES[max(0, self.region.current())][0]
        key, secret = self.key.get(), self.secret.get()
        self.boton.state(["disabled"])
        self.msg.configure(text="Conectando…", style="TLabel")
        hogar = self.app.hogar

        def trabajo():
            n = hogar.conectar(key, secret, region, avisar=lambda m: self.app._post(self._avisar, m))
            self.app._post(self._avisar, "Buscando las luces en el WiFi de la casa…")
            hogar.escanear(8)
            hogar.actualizar_todo()
            return n

        def fallo(texto, _err=True):
            self.boton.state(["!disabled"])
            self.msg.configure(text=texto, style="Error.TLabel")

        def run():
            try:
                n = trabajo()
            except LucesError as e:
                self.app._post(fallo, str(e))
            except Exception as e:
                log.exception("Error al conectar")
                self.app._post(fallo, f"Error inesperado: {e}")
            else:
                self.app._post(self._listo, n)
        threading.Thread(target=run, daemon=True).start()

    def _avisar(self, m):
        self.msg.configure(text=m, style="TLabel")

    def _listo(self, n):
        self.win.destroy()
        self.app.mostrar_luces()
        self.app._fin_actualizar([f"«{x.nombre}» no responde" for x in self.app.hogar.todas if not x.via])
        messagebox.showinfo(APP, f"¡Listo! Encontré {n} dispositivos.", parent=self.app.root)


def run_gui() -> int:
    if tk is None:
        print("Esta instalación de Python no trae la ventana (tkinter). Usa: python luces.py --help")
        return 2
    if os.name == "nt":
        try:
            import ctypes
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except Exception:
            pass
    root = tk.Tk()
    app = App(root)
    root.protocol("WM_DELETE_WINDOW", app.close)
    root.mainloop()
    return 0


# ---------------------------------------------------------------------------
# Aplicación: el cuarto en 3D, en una ventana propia
# ---------------------------------------------------------------------------

PUERTO_APP = 8766
TIPOS = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css",
         ".png": "image/png", ".svg": "image/svg+xml", ".ico": "image/x-icon", ".json": "application/json"}
# Dónde van las luces en el cuarto 3D (metros). Se pueden mover desde la ventana.
UBICACIONES = {
    "techo": {"x": 0.0, "y": 2.45, "z": -0.25, "forma": "techo"},
    "tira": {"x": -0.25, "y": 0.82, "z": -1.45, "forma": "tira"},
    "foco": {"x": -1.3, "y": 0.35, "z": -0.65, "forma": "foco"},
}
_FOCOS_EXTRA = [(-1.3, 0.35, -0.65), (1.25, 1.3, -1.35), (-0.75, 1.1, -1.3), (1.4, 2.2, 0.4)]  # rincón, junto al bajo…


def recurso(*partes: str) -> str:
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, "recursos", *partes)


def ubicacion_inicial(luz: "Luz", orden: int) -> dict:
    n = normalizar(luz.nombre)
    if luz.categoria in ("dd", "dc") or "tira" in n or re.search(r"\bled\b", n):
        return dict(UBICACIONES["tira"], alcance=1.0)
    if "techo" in n or "plafon" in n or luz.categoria == "xdd" or orden == 0:
        return dict(UBICACIONES["techo"], alcance=1.0)
    x, y, z = _FOCOS_EXTRA[max(0, orden - 1) % len(_FOCOS_EXTRA)]
    return {"x": x, "y": y, "z": z, "forma": "foco", "alcance": 1.0}


def hogar_demo(carpeta: str) -> "Hogar":
    """Luces de mentira para probar el programa sin cuenta de Smart Life."""
    h = Hogar(carpeta)
    datos = [  # como en el cuarto real: la única luz programable es la del techo
        ({"id": "demo_techo", "name": "Luz del techo", "category": "dj", "demo": True},
         {"switch_led": True, "work_mode": "white", "bright_value_v2": 720, "temp_value_v2": 260}),
    ]
    h.todas = []
    for data, state in datos:
        luz = Luz(data, h)
        luz.state, luz.via = dict(state), "demo"
        h.todas.append(luz)
    return h


def abrir_ventana(url: str) -> bool:
    """Abre la app en una ventana propia de Edge/Chrome (sin barras de navegador)."""
    perfil = os.path.join(config_dir(), "ventana")
    candidatos: List[Optional[str]] = []
    if os.name == "nt":
        for var in ("ProgramFiles(x86)", "ProgramFiles", "LocalAppData"):
            base = os.environ.get(var)
            if base:
                candidatos += [os.path.join(base, "Microsoft", "Edge", "Application", "msedge.exe"),
                               os.path.join(base, "Google", "Chrome", "Application", "chrome.exe")]
    else:
        import shutil
        candidatos += [shutil.which(n) for n in ("microsoft-edge", "google-chrome", "chromium", "chromium-browser")]
    for exe in candidatos:
        if exe and os.path.isfile(exe):
            try:
                import subprocess
                subprocess.Popen([exe, f"--app={url}", f"--user-data-dir={perfil}", "--window-size=1340,840",
                                  "--no-first-run", "--no-default-browser-check", "--disable-features=Translate"],
                                 creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                return True
            except OSError:
                continue
    webbrowser.open(url)
    return False


class WebApp:
    """Servidor local de la ventana: entrega el cuarto 3D y recibe las órdenes."""

    def __init__(self, carpeta: Optional[str] = None, puerto: int = PUERTO_APP):
        self.dir = carpeta or config_dir()
        self.real = Hogar(self.dir)
        self.cfg = _leer_json(os.path.join(self.dir, "app.json"), {})
        self.demo = bool(self.cfg.get("demo")) or False
        self._demo: Optional[Hogar] = None
        import secrets
        self.token = secrets.token_urlsafe(18)
        self.trabajo = {"estado": "", "mensaje": ""}
        self.latido = 0.0
        self.visto = False
        self.ultima_orden = 0.0
        self._lock = threading.Lock()
        from http.server import ThreadingHTTPServer
        ultimo = None
        for p in (puerto, 0):
            try:
                self.httpd = ThreadingHTTPServer(("127.0.0.1", p), _manejador(self))
                break
            except OSError as e:
                ultimo = e
        else:
            raise LucesError(f"No se pudo abrir la ventana: {ultimo}")
        self.httpd.daemon_threads = True
        self.puerto = self.httpd.server_address[1]

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.puerto}/"

    @property
    def hogar(self) -> Hogar:
        if self.demo:
            if self._demo is None:
                self._demo = hogar_demo(os.path.join(self.dir, "demo"))
            return self._demo
        return self.real

    def guardar_cfg(self) -> None:
        self.cfg["demo"] = self.demo
        _escribir_json(os.path.join(self.dir, "app.json"), self.cfg)

    # --- estado para la ventana ---
    def luz_json(self, luz: Luz) -> dict:
        ub = self.cfg.setdefault("ubicaciones", {})
        pos = ub.get(luz.id)
        if pos is None and luz.es_luz:
            # orden entre las luces que no son tira (la primera va al techo)
            normales = [x.id for x in self.hogar.luces if not (x.categoria in ("dd", "dc") or "tira" in normalizar(x.nombre))]
            orden = normales.index(luz.id) if luz.id in normales else 0
            pos = ub[luz.id] = ubicacion_inicial(luz, orden)
            self.guardar_cfg()
        return {
            "id": luz.id, "nombre": luz.nombre, "es_luz": luz.es_luz, "via": luz.via, "error": luz.error,
            "encendida": luz.encendida, "brillo": luz.brillo, "tono": luz.tono, "modo": luz.modo,
            "color": list(luz.color) if luz.color else None, "pos": pos,
            "tiene": {"brillo": bool(luz.c_bright or luz.c_colour), "tono": bool(luz.c_temp), "color": bool(luz.c_colour)},
        }

    def estado(self) -> dict:
        h = self.hogar
        return {
            "configurado": self.real.configurado, "demo": self.demo, "region": self.real.config.get("region"),
            "luces": [self.luz_json(x) for x in h.todas],
            "escenas": [{"nombre": n, "propia": n not in ESCENAS_BASE, "spec": s} for n, s in h.escenas().items()],
            "regiones": REGIONES,
        }

    # --- órdenes ---
    def orden_luz(self, luz_id: str, datos: dict) -> dict:
        luz = next((x for x in self.hogar.todas if x.id == luz_id), None)
        if luz is None:
            raise LucesError("Esa luz ya no existe. Pulsa «Actualizar».")
        kw: dict = {}
        if isinstance(datos.get("on"), bool):
            kw["on"] = datos["on"]
        for k, lo, hi in (("brillo", 1, 100), ("tono", 0, 100)):
            if isinstance(datos.get(k), (int, float)):
                kw[k] = int(max(lo, min(hi, datos[k])))
        c = datos.get("color")
        if isinstance(c, list) and len(c) == 2 and all(isinstance(v, (int, float)) for v in c):
            kw["color"] = (int(c[0]) % 360, int(max(0, min(100, c[1]))))
        if datos.get("blanco") is True:
            kw["blanco"] = True
        self.ultima_orden = time.monotonic()
        luz.enviar(luz.comandos(**kw))
        return {"luz": self.luz_json(luz)}

    def posicion(self, d: dict) -> dict:
        if not d.get("id"):
            raise LucesError("Falta la luz.")
        pos = {}
        for k in ("x", "y", "z"):
            v = d.get(k)
            if not isinstance(v, (int, float)):
                raise LucesError("Posición inválida.")
            pos[k] = round(float(v), 3)
        pos["forma"] = d.get("forma") if d.get("forma") in UBICACIONES else "foco"
        pos["alcance"] = round(max(0.2, min(3.0, float(d.get("alcance") or 1))), 2)
        self.cfg.setdefault("ubicaciones", {})[str(d["id"])] = pos
        self.guardar_cfg()
        return {}

    def conectar(self, d: dict) -> dict:
        if self.trabajo.get("estado") == "corriendo":
            raise LucesError("Ya estoy conectando, espera un momento.")
        self.trabajo = {"estado": "corriendo", "mensaje": "Conectando con Smart Life…"}

        def correr():
            def avisar(m):
                self.trabajo["mensaje"] = m
            try:
                n = self.real.conectar(str(d.get("key", "")), str(d.get("secret", "")), str(d.get("region", "")), avisar)
                avisar("Buscando las luces en el WiFi de la casa…")
                self.real.escanear(8)
                self.real.actualizar_todo()
                self.demo = False
                self.guardar_cfg()
                self.trabajo = {"estado": "listo", "mensaje": f"¡Listo! Encontré {n} dispositivos."}
            except LucesError as e:
                self.trabajo = {"estado": "error", "mensaje": str(e)}
            except Exception as e:  # pragma: no cover
                log.exception("Error al conectar")
                self.trabajo = {"estado": "error", "mensaje": f"Error inesperado: {e}"}
        threading.Thread(target=correr, daemon=True).start()
        return {}

    def api(self, metodo: str, ruta: str, d: dict) -> dict:
        h = self.hogar
        if metodo == "GET" and ruta == "/api/estado":
            self.visto, self.latido = True, time.monotonic()
            return self.estado()
        if metodo == "GET" and ruta == "/api/trabajo":
            return dict(self.trabajo)
        if metodo != "POST":
            raise KeyError(ruta)
        if ruta == "/api/latido":
            self.visto, self.latido = True, time.monotonic()
            return {}
        if ruta.startswith("/api/luz/"):
            return self.orden_luz(urllib.parse.unquote(ruta[len("/api/luz/"):]), d)
        if ruta == "/api/todas":
            self.ultima_orden = time.monotonic()
            return {"errores": h.encender_todas(bool(d.get("on"))), "estado": self.estado()}
        if ruta == "/api/escena":
            self.ultima_orden = time.monotonic()
            return {"errores": h.aplicar_escena(str(d.get("nombre", ""))), "estado": self.estado()}
        if ruta == "/api/escena/guardar":
            h.guardar_escena(str(d.get("nombre", "")))
            return {"estado": self.estado()}
        if ruta == "/api/escena/borrar":
            h.borrar_escena(str(d.get("nombre", "")))
            return {"estado": self.estado()}
        if ruta == "/api/actualizar":
            if d.get("red") and not self.demo:
                h.escanear(8)
            errores = h.actualizar_todo() if not self.demo else []
            return {"errores": errores, "estado": self.estado()}
        if ruta == "/api/posicion":
            return self.posicion(d)
        if ruta == "/api/conectar":
            return self.conectar(d)
        if ruta == "/api/demo":
            self.demo = bool(d.get("on"))
            self.guardar_cfg()
            return {"estado": self.estado()}
        raise KeyError(ruta)

    # --- ciclo de vida ---
    def _refrescar(self):
        """Lee cada tanto las luces reales, por si alguien las cambió desde el celular."""
        if self.real.configurado and not self.demo:
            try:
                self.real.actualizar_todo()   # primero, con lo que ya sabemos: la luz aparece enseguida
                self.real.escanear(6)         # después, por si cambió la dirección en el WiFi
                self.real.actualizar_todo()
            except Exception:
                log.debug("Error en la primera lectura", exc_info=True)
        while True:
            time.sleep(10)
            if self.demo or not self.real.configurado or time.monotonic() - self.ultima_orden < 5:
                continue
            if time.monotonic() - self.latido > 30:
                continue  # la ventana no está abierta
            try:
                self.real.actualizar_todo()
            except Exception:
                log.debug("Error actualizando", exc_info=True)

    def iniciar(self):
        threading.Thread(target=self.httpd.serve_forever, daemon=True, name="http").start()
        threading.Thread(target=self._refrescar, daemon=True, name="refresco").start()

    def esperar_cierre(self, sin_ventana_max: float = 120):
        """Termina cuando se cierra la ventana (deja de dar señales de vida)."""
        inicio = time.monotonic()
        while True:
            time.sleep(2)
            ahora = time.monotonic()
            if self.visto and ahora - self.latido > 25:
                break
            if not self.visto and ahora - inicio > sin_ventana_max:
                break
        self.httpd.shutdown()


def _manejador(app: "WebApp"):
    from http.server import BaseHTTPRequestHandler

    class H(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):
            if "/api/latido" not in self.path and "/api/estado" not in self.path:
                log.debug("ventana %s", fmt % args)

        def _enviar(self, code: int, body: bytes, tipo: str):
            self.send_response(code)
            self.send_header("Content-Type", tipo)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _json(self, code: int, obj):
            self._enviar(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

        def do_GET(self):
            ruta = urllib.parse.urlsplit(self.path).path
            if ruta in ("/", "/index.html"):
                with open(recurso("app.html"), encoding="utf-8") as f:
                    html = f.read().replace("{{TOKEN}}", app.token)
                self._enviar(200, html.encode("utf-8"), TIPOS[".html"])
            elif ruta == "/api/hola":
                self._json(200, {"app": APP, "version": VERSION})
            elif ruta.startswith("/recursos/"):
                raiz = os.path.realpath(recurso())
                archivo = os.path.realpath(os.path.join(raiz, *urllib.parse.unquote(ruta[10:]).split("/")))
                if not archivo.startswith(raiz + os.sep) or not os.path.isfile(archivo):
                    self._json(404, {"error": "no existe"})
                    return
                with open(archivo, "rb") as f:
                    self._enviar(200, f.read(), TIPOS.get(os.path.splitext(archivo)[1].lower(), "application/octet-stream"))
            elif ruta.startswith("/api/"):
                self._api("GET", ruta, {})
            else:
                self._json(404, {"error": "no existe"})

        def do_POST(self):
            ruta = urllib.parse.urlsplit(self.path).path
            n = int(self.headers.get("Content-Length") or 0)
            crudo = self.rfile.read(min(n, 1_000_000)) if n else b""
            try:
                datos = json.loads(crudo or b"{}")
            except ValueError:
                datos = {}
            self._api("POST", ruta, datos if isinstance(datos, dict) else {})

        def _api(self, metodo, ruta, datos):
            if self.headers.get("X-Token") != app.token:  # sólo la ventana de este programa
                self._json(403, {"error": "No autorizado"})
                return
            try:
                self._json(200, app.api(metodo, ruta, datos))
            except KeyError:
                self._json(404, {"error": "no existe"})
            except LucesError as e:
                self._json(400, {"error": str(e)})
            except Exception as e:
                log.exception("Error en %s", ruta)
                self._json(500, {"error": f"Error inesperado: {e}"})
    return H


def run_app(sin_ventana: bool = False, puerto: int = PUERTO_APP) -> int:
    # ¿Ya está abierto? Entonces sólo mostramos esa ventana.
    try:
        with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(
                f"http://127.0.0.1:{puerto}/api/hola", timeout=1.5) as r:
            if json.loads(r.read()).get("app") == APP:
                if not sin_ventana:
                    abrir_ventana(f"http://127.0.0.1:{puerto}/")
                return 0
    except (OSError, ValueError):
        pass
    app = WebApp(puerto=puerto)
    app.iniciar()
    log.info("Luces abierto en %s", app.url)
    if not sin_ventana:
        abrir_ventana(app.url)
    try:
        app.esperar_cierre(sin_ventana_max=10 ** 9 if sin_ventana else 120)
    except KeyboardInterrupt:
        pass
    return 0


# ---------------------------------------------------------------------------
# Consola
# ---------------------------------------------------------------------------

def _necesita_config(hogar: Hogar):
    if not hogar.configurado:
        raise LucesError("Todavía no conectaste tu cuenta de Smart Life. Ejecuta:  python luces.py configurar")


def _describir(luz: Luz) -> str:
    if not luz.via:
        return f"  {luz.nombre:<24} sin conexión"
    estado = "encendida" if luz.encendida else "apagada"
    extra = []
    if luz.encendida and luz.brillo is not None:
        extra.append(f"brillo {luz.brillo}%")
    if luz.encendida and luz.modo == "color" and luz.color:
        extra.append(f"color {luz.color[0]}°")
    elif luz.encendida and luz.tono is not None:
        extra.append(f"tono {luz.tono}")
    via = "WiFi" if luz.via == "local" else "internet"
    tipo = "" if luz.es_luz else " (enchufe)"
    return f"  {luz.nombre + tipo:<24} {estado:<10} {', '.join(extra):<24} [{via}]"


def run_cli(args) -> int:
    hogar = Hogar()
    try:
        cmd = args.comando
        if cmd == "configurar":
            print(GUIA, "\n")
            key = input("Access ID: ").strip()
            secret = input("Access Secret: ").strip()
            n = hogar.conectar(key, secret, "", avisar=print)
            print("Buscando las luces en el WiFi de la casa…")
            hogar.escanear(8)
            hogar.actualizar_todo()
            for luz in hogar.todas:
                print(_describir(luz))
            print(f"Listo: {n} dispositivos.")
            return 0
        _necesita_config(hogar)
        if cmd == "buscar":
            n = hogar.escanear(10)
            print(f"Encontré en la red {n} de {len(hogar.todas)} dispositivos.")
            return 0
        if cmd == "lista":
            hogar.actualizar_todo()
            for luz in hogar.todas:
                print(_describir(luz))
            return 0
        if cmd == "escena":
            errores = hogar.aplicar_escena(args.valor)
        else:
            luces = hogar.buscar(args.luz)
            if cmd in ("encender", "apagar"):
                kw = {"on": cmd == "encender"}
            elif cmd == "brillo":
                kw = {"brillo": int(args.valor)}
            elif cmd == "tono":
                kw = {"tono": int(args.valor), "blanco": True}
            elif cmd == "color":
                kw = {"color": parse_color(args.valor)}
            else:  # pragma: no cover
                raise LucesError(f"Comando desconocido: {cmd}")
            hogar._en_paralelo(luces, Luz.actualizar)
            errores = hogar._en_paralelo(luces, lambda l: l.enviar(l.comandos(**kw)))
        for e in errores:
            print("⚠", e)
        return 1 if errores else 0
    except LucesError as e:
        print(e)
        return 1
    except (ValueError, KeyboardInterrupt) as e:
        print(e)
        return 1


def setup_logging(verbose: bool = False) -> None:
    if logging.getLogger().handlers:  # ya configurado (por ejemplo, desde Proyectar)
        return
    handlers: List[logging.Handler] = []
    if sys.stderr:
        h = logging.StreamHandler()
        h.setLevel(logging.DEBUG if verbose else logging.WARNING)
        handlers.append(h)
    try:
        fh = logging.FileHandler(LOG_PATH, "w", encoding="utf-8")
        fh.setLevel(logging.DEBUG)
        handlers.append(fh)
    except OSError:
        pass
    logging.basicConfig(level=logging.DEBUG, handlers=handlers,
                        format="%(asctime)s %(levelname)-7s %(name)s %(message)s", datefmt="%H:%M:%S")


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(prog="luces", description="Controla las luces de Smart Life desde la PC.",
                                epilog="Sin comando abre la ventana.")
    p.add_argument("-v", "--verbose", action="store_true", help="mostrar detalles técnicos")
    p.add_argument("--version", action="version", version=f"{APP} {VERSION}")
    p.add_argument("--sin-ventana", action="store_true", help="sólo el servidor (para pruebas)")
    p.add_argument("--puerto", type=int, default=PUERTO_APP, help=argparse.SUPPRESS)
    sub = p.add_subparsers(dest="comando")
    sub.add_parser("clasica", help="la ventana simple, sin el cuarto 3D")
    sub.add_parser("configurar", help="conectar la cuenta de Smart Life (una vez)")
    sub.add_parser("buscar", help="buscar las luces en la red de la casa")
    sub.add_parser("lista", help="ver las luces y cómo están")
    for nombre, ayuda in (("encender", "encender"), ("apagar", "apagar")):
        sp = sub.add_parser(nombre, help=f"{ayuda} una luz (o todas)")
        sp.add_argument("luz", nargs="?", help="nombre o parte del nombre; sin nombre: todas")
    for nombre, ayuda in (("brillo", "brillo de 1 a 100"), ("tono", "0 = cálida … 100 = fría"),
                          ("color", f"{', '.join(COLORES)} o #rrggbb")):
        sp = sub.add_parser(nombre, help=ayuda)
        sp.add_argument("valor")
        sp.add_argument("luz", nargs="?", help="nombre; sin nombre: todas")
    sp = sub.add_parser("escena", help=f"aplicar una escena ({', '.join(ESCENAS_BASE)} o una guardada)")
    sp.add_argument("valor", metavar="nombre")
    args = p.parse_args(argv)
    setup_logging(args.verbose)
    if not args.comando:
        return run_app(args.sin_ventana, args.puerto)
    if args.comando == "clasica":
        return run_gui()
    return run_cli(args)


if __name__ == "__main__":
    sys.exit(main())

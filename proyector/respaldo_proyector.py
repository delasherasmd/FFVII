#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Respaldo del proyector: se conecta por WiFi al proyector Android (ADB), cuenta qué sistema
y qué programas tiene, y guarda una copia de seguridad en el escritorio.

NO CAMBIA NADA en el proyector: sólo lee y copia.

    python respaldo_proyector.py               (o RespaldoProyector.exe con doble clic)
    python respaldo_proyector.py --ip 192.168.0.40
"""

from __future__ import annotations

import argparse
import ipaddress
import os
import re
import sys
import time
from typing import Dict, List, Optional, Tuple

import identificar as I

VERSION = "1.0"
PUERTO_ADB = 5555
# Sólo comandos que leen. Nada que instale, borre, desactive o cambie ajustes.
LECTURAS = {
    "props": "getprop",
    "pantalla": "wm size; wm density",
    "espacio": "df -h /data",
    "paquetes": "pm list packages -f",
    "terceros": "pm list packages -3",
    "desactivados": "pm list packages -d",
    "versiones": "pm list packages --show-versioncode",
    "inicio": "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME",
    "inicios": "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME",
    "ajustes_global": "settings list global",
    "ajustes_secure": "settings list secure",
    "ajustes_system": "settings list system",
}
PROPS_CLAVE = [
    ("ro.product.brand", "Marca"), ("ro.product.manufacturer", "Fabricante"), ("ro.product.model", "Modelo"),
    ("ro.product.device", "Dispositivo"), ("ro.product.name", "Nombre interno"),
    ("ro.build.version.release", "Android"), ("ro.build.version.sdk", "Nivel de API"),
    ("ro.board.platform", "Chip"), ("ro.hardware", "Hardware"), ("ro.build.display.id", "Versión del sistema"),
    ("ro.build.fingerprint", "Huella del sistema"), ("ro.build.date", "Fecha del sistema"),
    ("ro.product.locale", "Idioma"), ("ro.adb.secure", "ADB con permiso"),
]
PROHIBIDO = re.compile(r"\b(install|uninstall|disable|enable|clear|hide|unhide|suspend|reboot|rm|put|delete|wipe|"
                       r"reset|set|grant|revoke|am\s+force-stop)\b")


def log(m: str = "") -> None:
    print(m, flush=True)


def carpeta_datos() -> str:
    base = os.environ.get("APPDATA") or os.path.join(os.path.expanduser("~"), ".config")
    ruta = os.path.join(base, "Proyectar")
    os.makedirs(ruta, exist_ok=True)
    return ruta


def firmante():
    """Clave de esta PC para ADB (se guarda, así el proyector la recuerda con «Permitir siempre»)."""
    from adb_shell.auth.keygen import keygen
    from adb_shell.auth.sign_pythonrsa import PythonRSASigner
    priv = os.path.join(carpeta_datos(), "adbkey")
    if not os.path.exists(priv):
        keygen(priv)
    with open(priv) as f:
        privada = f.read()
    with open(priv + ".pub") as f:
        publica = f.read()
    return PythonRSASigner(publica, privada)


def buscar_proyectores(red: Optional[str]) -> List[str]:
    red_obj = ipaddress.ip_network(red, strict=False) if red else I.mi_red()
    if not red_obj:
        return []
    propia = I.P.local_ip_for("8.8.8.8") or ""
    viejos = dict(I.PUERTOS)
    I.PUERTOS.clear()
    I.PUERTOS[PUERTO_ADB] = "ADB"
    try:
        abiertos = I.barrer_puertos(red_obj, propia)
    finally:
        I.PUERTOS.clear()
        I.PUERTOS.update(viejos)
    return sorted(abiertos, key=lambda x: tuple(int(n) for n in x.split(".")))


class Proyector:
    """Conexión ADB de sólo lectura."""

    def __init__(self, ip: str, puerto: int = PUERTO_ADB):
        from adb_shell.adb_device import AdbDeviceTcp
        self.ip, self.puerto = ip, puerto
        self.dev = AdbDeviceTcp(ip, puerto, default_transport_timeout_s=10.0)

    def conectar(self, espera_permiso: float = 90.0) -> None:
        log(f"  · Conectando con {self.ip}…")
        log("    MIRA EL PROYECTOR: si aparece «¿Permitir depuración USB?», marca")
        log("    «Permitir siempre desde esta computadora» y elige «Permitir» con el control remoto.")
        self.dev.connect(rsa_keys=[firmante()], auth_timeout_s=espera_permiso, read_timeout_s=20)

    def leer(self, orden: str, espera: float = 30.0) -> str:
        if PROHIBIDO.search(orden.replace("query-activities", "").replace("resolve-activity", "")):
            raise RuntimeError(f"Orden no permitida (sólo lectura): {orden}")
        try:
            return self.dev.shell(orden, read_timeout_s=espera, timeout_s=espera * 2) or ""
        except Exception as e:  # algunos comandos no existen en Android viejos
            return f"(no disponible: {e})"

    def copiar(self, ruta: str, destino: str) -> bool:
        try:
            self.dev.pull(ruta, destino, read_timeout_s=60)
            return os.path.getsize(destino) > 0
        except Exception:
            if os.path.exists(destino):
                os.remove(destino)
            return False

    def cerrar(self):
        try:
            self.dev.close()
        except Exception:
            pass


def props(texto: str) -> Dict[str, str]:
    return {m.group(1): m.group(2) for m in re.finditer(r"^\[([^\]]+)\]:\s*\[([^\]]*)\]", texto, re.M)}


def paquetes_con_ruta(texto: str) -> Dict[str, str]:
    """'package:/data/app/x/base.apk=com.x' -> {com.x: /data/app/x/base.apk}"""
    out = {}
    for linea in texto.splitlines():
        m = re.match(r"package:(.+\.apk)=([\w.]+)\s*$", linea.strip())
        if m:
            out[m.group(2)] = m.group(1)
    return out


def nombres(texto: str) -> List[str]:
    return sorted({m.group(1) for m in re.finditer(r"^package:([\w.]+)", texto, re.M)})


def actividades(texto: str) -> List[str]:
    """Salida de resolve-activity / query-activities -> ['com.pkg/.Actividad', …]"""
    return [x for x in re.findall(r"([\w.]+/[\w.$]+)", texto) if "/" in x and "." in x.split("/")[0]]


def nombre_seguro(texto: str) -> str:
    return re.sub(r"[^\w\- ]+", "", texto).strip()[:40] or "proyector"


def respaldar(p: Proyector, destino_base: str, todo: bool = False) -> Tuple[str, str]:
    """Lee todo y guarda la copia. Devuelve (informe, carpeta)."""
    log("  · Leyendo el sistema del proyector…")
    datos = {clave: p.leer(orden) for clave, orden in LECTURAS.items()}
    pr = props(datos["props"])
    modelo = pr.get("ro.product.model") or "proyector"
    carpeta = os.path.join(destino_base, f"Respaldo proyector {nombre_seguro(modelo)} {time.strftime('%Y-%m-%d %H%M')}")
    os.makedirs(os.path.join(carpeta, "apps"), exist_ok=True)
    for clave, texto in datos.items():
        with open(os.path.join(carpeta, f"{clave}.txt"), "w", encoding="utf-8") as f:
            f.write(texto)

    rutas = paquetes_con_ruta(datos["paquetes"])
    terceros = nombres(datos["terceros"])
    desactivados = nombres(datos["desactivados"])
    inicio = actividades(datos["inicio"])
    inicios = actividades(datos["inicios"]) or inicio
    pkg_inicio = [a.split("/")[0] for a in inicio]
    pkg_inicios = sorted({a.split("/")[0] for a in inicios})
    a_copiar = list(dict.fromkeys(pkg_inicios + terceros + ([*rutas] if todo else [])))
    log(f"  · Copiando {len(a_copiar)} programas (la pantalla de inicio y las apps instaladas)…")
    copiados, fallidos, total = [], [], 0
    for pkg in a_copiar:
        apks = [l.split(":", 1)[1].strip() for l in p.leer(f"pm path {pkg}").splitlines() if l.startswith("package:")]
        apks = apks or ([rutas[pkg]] if pkg in rutas else [])
        ok = True
        for i, apk in enumerate(apks):
            nombre = f"{pkg}.apk" if len(apks) == 1 else f"{pkg}__{i + 1}_{os.path.basename(apk)}"
            local = os.path.join(carpeta, "apps", nombre)
            if p.copiar(apk, local):
                total += os.path.getsize(local)
            else:
                ok = False
        (copiados if ok and apks else fallidos).append(pkg)

    L = [f"INFORME DEL PROYECTOR · Respaldo {VERSION}",
         f"Fecha: {time.strftime('%Y-%m-%d %H:%M')} · Dirección: {p.ip}:{p.puerto}", ""]
    for clave, etiqueta in PROPS_CLAVE:
        if pr.get(clave):
            L.append(f"{etiqueta}: {pr[clave]}")
    pantalla = " · ".join(x.strip() for x in datos["pantalla"].splitlines() if x.strip())
    if pantalla:
        L.append(f"Pantalla: {pantalla}")
    espacio = [x for x in datos["espacio"].splitlines() if x.strip()][-1:] if datos["espacio"] else []
    if espacio:
        L.append(f"Espacio (/data): {espacio[0].strip()}")
    L += ["", f"Pantalla de inicio actual: {', '.join(inicio) or '(no se pudo saber)'}",
          f"Otras pantallas de inicio instaladas: {', '.join(a for a in inicios if a not in inicio) or 'ninguna'}",
          "", f"Programas instalados en total: {len(rutas) or len(nombres(datos['versiones']))}",
          f"Apps agregadas (no del sistema): {len(terceros)}"]
    for pkg in terceros:
        L.append(f"   · {pkg}")
    if desactivados:
        L.append(f"Programas desactivados: {', '.join(desactivados)}")
    L.append("")
    fabricante = sorted(pkg for pkg in rutas if rutas[pkg].startswith(("/system/app", "/system/priv-app", "/vendor", "/product", "/oem"))
                        and not pkg.startswith(("com.android.", "android", "com.google.android.")))
    if fabricante:
        L.append(f"Programas del fabricante ({len(fabricante)}):")
        L += [f"   · {pkg}  ({rutas[pkg]})" for pkg in fabricante]
        L.append("")
    L.append(f"COPIA DE SEGURIDAD: {carpeta}")
    L.append(f"   {len(copiados)} programas copiados ({total / 1048576:.1f} MB)"
             + (f"; no se pudieron copiar: {', '.join(fallidos)}" if fallidos else ""))
    L.append("   También: lista de programas, ajustes y datos del sistema (archivos .txt).")
    L += ["", "No se cambió nada en el proyector.", "Copia todo este texto y pégalo en el chat."]
    informe = "\n".join(L)
    with open(os.path.join(carpeta, "INFORME.txt"), "w", encoding="utf-8") as f:
        f.write(informe)
    return informe, carpeta


COMO_ACTIVAR = """No encontré el proyector con el acceso por red (ADB) abierto.

Para activarlo, en el proyector:
  1. Ajustes → Acerca de / Información del dispositivo.
  2. Pulsa 7 veces «Número de compilación» (Build number) hasta que diga que eres desarrollador.
  3. Vuelve a Ajustes → Opciones de desarrollador (puede estar en Sistema o Avanzado).
  4. Activa «Depuración USB» y, si aparece, «Depuración por red» o «ADB por red».
Después vuelve a abrir este programa. (Si sabes la IP del proyector: RespaldoProyector.exe --ip 192.168.x.x)"""


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Copia de seguridad del proyector Android por WiFi (sólo lectura).")
    ap.add_argument("--ip", help="IP del proyector (si no, se busca en la red)")
    ap.add_argument("--puerto", type=int, default=PUERTO_ADB)
    ap.add_argument("--red", help="red a revisar, p. ej. 192.168.0.0/24")
    ap.add_argument("--salida", help="carpeta donde guardar (por defecto, el escritorio)")
    ap.add_argument("--todo", action="store_true", help="copiar también todos los programas del sistema (ocupa más)")
    ap.add_argument("--sin-pausa", action="store_true")
    args = ap.parse_args(argv)
    for flujo in (sys.stdout, sys.stderr):
        try:
            flujo.reconfigure(errors="replace")
        except Exception:
            pass
    if os.name == "nt":
        os.system("")
    log("Respaldo del proyector — sólo lee y copia, no cambia nada.\n")
    codigo = 1
    try:
        candidatos = [args.ip] if args.ip else buscar_proyectores(args.red)
        if not candidatos:
            log(COMO_ACTIVAR)
        else:
            if len(candidatos) > 1:
                log("Encontré varios equipos con acceso por red:")
                for i, ip in enumerate(candidatos, 1):
                    log(f"  {i}. {ip}  {I.nombre_dns(ip)}")
                elegido = input("¿Cuál es el proyector? (número): ").strip()
                ip = candidatos[int(elegido) - 1] if elegido.isdigit() and 1 <= int(elegido) <= len(candidatos) else candidatos[0]
            else:
                ip = candidatos[0]
            p = Proyector(ip, args.puerto)
            try:
                p.conectar()
                informe, carpeta = respaldar(p, args.salida or I.escritorio(), args.todo)
            finally:
                p.cerrar()
            log("\n" + informe)
            if I.al_portapapeles(informe):
                log("\nEl informe quedó copiado: en el chat pulsa Ctrl+V para pegarlo.")
            codigo = 0
    except Exception as e:
        log(f"\nNo pude terminar: {e}")
        log("Si el proyector mostró un aviso, acéptalo y vuelve a abrir el programa.")
    if not args.sin_pausa:
        try:
            input("\nPulsa Enter para cerrar…")
        except EOFError:
            pass
    return codigo


if __name__ == "__main__":
    sys.exit(main())

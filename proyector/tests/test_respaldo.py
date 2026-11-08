# -*- coding: utf-8 -*-
"""Pruebas de respaldo_proyector.py contra un proyector Android falso (tests/adb_falso.py)."""

import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

try:
    import adb_shell  # noqa: F401
except ImportError:  # pragma: no cover
    adb_shell = None

import respaldo_proyector as R  # noqa: E402
from adb_falso import FakeAdbDevice  # noqa: E402

LAUNCHER = b"APK-del-launcher-original" * 4000
NETFLIX = b"APK-netflix" * 3000
RESPUESTAS = {
    "getprop": "[ro.product.brand]: [Magcubic]\n[ro.product.manufacturer]: [Allwinner]\n[ro.product.model]: [HY300 Pro]\n"
               "[ro.build.version.release]: [11]\n[ro.build.version.sdk]: [30]\n[ro.board.platform]: [sun50iw12p1]\n"
               "[ro.adb.secure]: [1]\n",
    "wm size; wm density": "Physical size: 1280x720\nPhysical density: 160\n",
    "df -h /data": "Filesystem Size Used Avail Use% Mounted on\n/dev/block/by-name/UDISK 5.2G 1.1G 4.1G 22% /data\n",
    "pm list packages -f": "package:/system/app/HyLauncher/HyLauncher.apk=com.hysd.launcher\n"
                          "package:/system/priv-app/HyAds/HyAds.apk=com.hysd.adservice\n"
                          "package:/system/priv-app/Settings/Settings.apk=com.android.settings\n"
                          "package:/data/app/~~x1/com.netflix.ninja-2/base.apk=com.netflix.ninja\n",
    "pm list packages -3": "package:com.netflix.ninja\n",
    "pm list packages -d": "",
    "pm list packages --show-versioncode": "package:com.hysd.launcher versionCode:12\n",
    "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME":
        "priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=true\ncom.hysd.launcher/.MainActivity\n",
    "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME":
        "com.hysd.launcher/.MainActivity\ncom.android.tv.settings/.FallbackHome\n",
    "settings list global": "adb_enabled=1\n", "settings list secure": "", "settings list system": "",
    "pm path com.hysd.launcher": "package:/system/app/HyLauncher/HyLauncher.apk\n",
    "pm path com.android.tv.settings": "",
    "pm path com.netflix.ninja": "package:/data/app/~~x1/com.netflix.ninja-2/base.apk\n",
}
ARCHIVOS = {"/system/app/HyLauncher/HyLauncher.apk": LAUNCHER, "/data/app/~~x1/com.netflix.ninja-2/base.apk": NETFLIX}


@unittest.skipIf(adb_shell is None, "falta adb-shell (pip install adb-shell)")
class TestRespaldo(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.viejo = os.environ.get("APPDATA")
        os.environ["APPDATA"] = os.path.join(self.tmp, "appdata")
        self.dev = FakeAdbDevice(RESPUESTAS, ARCHIVOS)

    def tearDown(self):
        self.dev.close()
        if self.viejo is None:
            os.environ.pop("APPDATA", None)
        else:
            os.environ["APPDATA"] = self.viejo
        shutil.rmtree(self.tmp)

    def test_lee_y_copia_sin_cambiar_nada(self):
        p = R.Proyector("127.0.0.1", self.dev.port)
        p.conectar(espera_permiso=10)
        informe, carpeta = R.respaldar(p, self.tmp)
        p.cerrar()
        self.assertEqual(len(self.dev.claves_aceptadas), 1)  # el «usuario» aceptó la clave en el proyector
        for texto in ("Marca: Magcubic", "Modelo: HY300 Pro", "Android: 11", "Chip: sun50iw12p1",
                      "Pantalla de inicio actual: com.hysd.launcher/.MainActivity", "com.netflix.ninja",
                      "com.hysd.adservice", "No se cambió nada"):
            self.assertIn(texto, informe)
        with open(os.path.join(carpeta, "apps", "com.hysd.launcher.apk"), "rb") as f:
            self.assertEqual(f.read(), LAUNCHER)
        with open(os.path.join(carpeta, "apps", "com.netflix.ninja.apk"), "rb") as f:
            self.assertEqual(f.read(), NETFLIX)
        self.assertTrue(os.path.exists(os.path.join(carpeta, "ajustes_global.txt")))
        self.assertTrue(os.path.exists(os.path.join(carpeta, "INFORME.txt")))
        for orden in self.dev.comandos:   # sólo lecturas
            self.assertIsNone(R.PROHIBIDO.search(orden.replace("query-activities", "").replace("resolve-activity", "")), orden)

    def test_segunda_vez_no_pide_permiso_de_nuevo(self):
        for _ in range(2):
            p = R.Proyector("127.0.0.1", self.dev.port)
            p.conectar(espera_permiso=10)
            self.assertIn("HY300", p.leer("getprop"))
            p.cerrar()
        self.assertEqual(len(self.dev.claves_aceptadas), 1)  # misma clave guardada en la PC

    def test_rechaza_ordenes_que_cambian_algo(self):
        p = R.Proyector("127.0.0.1", self.dev.port)
        for orden in ("pm uninstall com.hysd.launcher", "pm disable-user com.x", "settings put global a 1", "reboot"):
            with self.assertRaises(RuntimeError):
                p.leer(orden)


if __name__ == "__main__":
    unittest.main()

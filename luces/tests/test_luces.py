# -*- coding: utf-8 -*-
"""Pruebas de luces.py con lamparitas falsas (tests/tuya_falso.py).

    python -m unittest discover -s tests -v
"""

import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import luces as L  # noqa: E402
from tuya_falso import FakeBulb  # noqa: E402

# Mapa de una lamparita "vieja" (DPS 1-5, valores de 0 a 255)
MAPA_VIEJO = {
    "1": {"code": "switch_led", "type": "Boolean", "values": {}},
    "2": {"code": "work_mode", "type": "Enum", "values": {"range": ["white", "colour"]}},
    "3": {"code": "bright_value", "type": "Integer", "values": {"min": 25, "max": 255}},
    "4": {"code": "temp_value", "type": "Integer", "values": {"min": 0, "max": 255}},
    "5": {"code": "colour_data", "type": "Json",
          "values": {"h": {"min": 0, "max": 360}, "s": {"min": 0, "max": 255}, "v": {"min": 0, "max": 255}}},
}


class FakeCloud:
    """Imita tinytuya.Cloud: guarda lo que se le pide."""

    def __init__(self, devices=None, apiRegion=None, apiKey=None, apiSecret=None, ok_regions=("us",), **kw):
        self.region = apiRegion
        self.sent = []
        self.token = "tok" if (apiKey == "buena" and apiRegion in ok_regions) or apiRegion is None else None
        self.error = {"Error": "Cloud _gettoken() failed", "Payload": "sign invalid" if apiKey != "buena" else "x"}
        self._devices = devices or []
        self.getdevices_raw = {}

    def getdevices(self, verbose=False, oldlist=(), include_map=False):
        return [dict(d) for d in self._devices]

    def sendcommand(self, dev_id, commands):
        self.sent.append((dev_id, commands))
        return {"success": True, "result": True}

    def getstatus(self, dev_id):
        return {"success": True, "result": [{"code": "switch_led", "value": True},
                                            {"code": "colour_data_v2", "value": '{"h":120,"s":1000,"v":500}'},
                                            {"code": "work_mode", "value": "colour"}]}


class TestColores(unittest.TestCase):
    def test_formatos(self):
        hsv = {"h": 300, "s": 1000, "v": 500}
        self.assertEqual(L.encode_colour(hsv, "hex12"), "012c03e801f4")
        self.assertEqual(L.decode_colour("012c03e801f4"), (hsv, "hex12"))
        viejo = L.encode_colour({"h": 0, "s": 255, "v": 255}, "hex14")
        self.assertEqual(viejo, "ff00000000ffff")
        self.assertEqual(L.decode_colour(viejo), ({"h": 0, "s": 255, "v": 255}, "hex14"))
        self.assertEqual(L.decode_colour('{"h":10,"s":20,"v":30}'), ({"h": 10, "s": 20, "v": 30}, "json"))
        self.assertEqual(L.decode_colour("basura"), (None, None))

    def test_parse_color(self):
        self.assertEqual(L.parse_color("Rojo"), (0, 100))
        self.assertEqual(L.parse_color("#00ff00"), (120, 100))
        self.assertEqual(L.parse_color("ffffff"), (0, 0))
        with self.assertRaises(L.LucesError):
            L.parse_color("transparente")

    def test_normalizar(self):
        self.assertEqual(L.normalizar("  Lámpara   LIVING "), "lampara living")


class TestComandos(unittest.TestCase):
    def setUp(self):
        self.hogar = L.Hogar(tempfile.mkdtemp())

    def test_luz_moderna(self):
        luz = L.Luz({"id": "a", "name": "Living", "category": "dj"}, self.hogar)  # sin mapa: estándar 20-24
        luz.state = {"switch_led": True, "work_mode": "white", "bright_value_v2": 1000, "temp_value_v2": 0}
        self.assertEqual((luz.brillo, luz.tono, luz.modo), (100, 0, "blanco"))
        self.assertEqual(luz.comandos(brillo=50), {"bright_value_v2": 505})
        self.assertEqual(luz.comandos(tono=100, blanco=True),
                         {"work_mode": "white", "temp_value_v2": 1000})
        self.assertEqual(luz.comandos(color=(120, 100)),
                         {"work_mode": "colour", "colour_data_v2": {"h": 120, "s": 1000, "v": 1000}})
        self.assertEqual(luz.comandos(on=False), {"switch_led": False})
        # en modo color, el brillo cambia la intensidad del color
        luz.state.update(work_mode="colour", colour_data_v2={"h": 240, "s": 1000, "v": 1000})
        self.assertEqual(luz.comandos(brillo=30), {"colour_data_v2": {"h": 240, "s": 1000, "v": 300}})
        self.assertEqual(luz.foto(), {"on": True, "modo": "color", "color": [240, 100], "brillo": 100})
        # mover el brillo de una luz apagada la prende
        luz.state["switch_led"] = False
        self.assertTrue(luz.comandos(brillo=10)["switch_led"])

    def test_luz_vieja(self):
        luz = L.Luz({"id": "b", "name": "Velador", "category": "dj", "mapping": MAPA_VIEJO}, self.hogar)
        luz.state = {"switch_led": True, "work_mode": "white", "bright_value": 255, "temp_value": 0}
        self.assertEqual(luz.comandos(brillo=0), {"bright_value": 27})  # mínimo 1%
        self.assertEqual(luz.formato_color(), "hex14")
        cmds = luz.comandos(color=(0, 100), brillo=100)
        self.assertEqual(cmds["colour_data"], {"h": 0, "s": 255, "v": 255})
        self.assertEqual(luz._al_local("colour_data", cmds["colour_data"]), "ff00000000ffff")

    def test_enchufe(self):
        enchufe = L.Luz({"id": "c", "name": "Ventilador", "category": "cz"}, self.hogar)
        self.assertFalse(enchufe.es_luz)
        self.assertEqual(enchufe.comandos(on=True, brillo=50), {"switch_1": True})
        self.hogar.todas = [enchufe]
        self.assertEqual(self.hogar.luces, [])  # «todas las luces» no apaga los enchufes


class TestConLamparitas(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.living = FakeBulb("bf_living_000000000", "0123456789abcdef")
        self.cuarto = FakeBulb("bf_cuarto_000000000", "fedcba9876543210",
                               dps={"20": False, "21": "white", "22": 500, "23": 0, "24": "000003e803e8"})
        enchufe = FakeBulb("bf_enchufe_00000000", "aaaabbbbccccdddd", dps={"1": True})
        self.enchufe = enchufe
        L._escribir_json(os.path.join(self.dir, "dispositivos.json"), [
            self.living.info("Lámpara Living"), self.cuarto.info("Cuarto"),
            enchufe.info("Ventilador", category="cz")])
        self.hogar = L.Hogar(self.dir)

    def tearDown(self):
        for b in (self.living, self.cuarto, self.enchufe):
            b.close()
        for luz in self.hogar.todas:
            luz._cerrar_local()
        shutil.rmtree(self.dir)

    def test_leer_y_mandar_por_wifi(self):
        self.assertEqual(self.hogar.actualizar_todo(), [])
        living = self.hogar.buscar("living")[0]
        self.assertEqual((living.via, living.encendida, living.brillo, living.tono), ("local", True, 100, 50))
        living.enviar(living.comandos(brillo=40))
        self.assertEqual(self.living.received[-1], {"22": 406})
        living.enviar(living.comandos(color=L.parse_color("azul")))
        self.assertEqual(self.living.received[-1], {"21": "colour", "24": "00e603e80190"})
        self.assertEqual(living.brillo, 40)  # al pasar a color mantiene el brillo

    def test_escenas(self):
        self.hogar.actualizar_todo()
        self.assertEqual(self.hogar.aplicar_escena("cine"), [])
        for b in (self.living, self.cuarto):
            self.assertEqual(b.dps["20"], True)
            self.assertEqual(b.dps["21"], "white")
            self.assertEqual(b.dps["22"], 89)   # 8 %
            self.assertEqual(b.dps["23"], 0)    # cálida
        self.assertEqual(self.enchufe.received, [])  # el enchufe no se toca
        self.hogar.aplicar_escena("Fiesta")
        self.assertNotEqual(self.living.dps["24"][:4], self.cuarto.dps["24"][:4])  # un color distinto cada una
        # guardar y restaurar
        self.hogar.encender_todas(False)
        self.hogar.guardar_escena("Todo apagado")
        self.hogar.aplicar_escena("Día")
        self.assertTrue(self.living.dps["20"])
        self.hogar.aplicar_escena("todo apagado")
        self.assertFalse(self.living.dps["20"])
        self.assertIn("Todo apagado", L.Hogar(self.dir).escenas())

    def test_si_no_responde_por_wifi_usa_internet(self):
        self.living.close()  # la luz no contesta en la red local
        nube = FakeCloud()
        self.hogar._nube = nube
        self.hogar.config.update(api_key="buena", api_secret="s", region="us")
        living = self.hogar.buscar("living")[0]
        living.actualizar()
        self.assertEqual(living.via, "nube")
        self.assertEqual((living.modo, living.color, living.brillo), ("color", (120, 100), 50))
        living.enviar(living.comandos(color=(0, 100)))
        self.assertEqual(nube.sent[-1], ("bf_living_000000000", {"commands": [
            {"code": "work_mode", "value": "colour"},
            {"code": "colour_data_v2", "value": {"h": 0, "s": 1000, "v": 500}}]}))

    def test_sin_conexion_da_error_claro(self):
        self.living.close()
        living = self.hogar.buscar("living")[0]
        with self.assertRaises(L.LucesError) as ctx:
            living.enviar(living.comandos(on=True))
        self.assertIn("Lámpara Living", str(ctx.exception))
        self.assertEqual(living.via, "")

    def test_consola(self):
        os.environ["LUCES_DIR"] = self.dir
        try:
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(L.main(["apagar", "living"]), 0)
                self.assertEqual(L.main(["color", "verde", "cuarto"]), 0)
                self.assertEqual(L.main(["lista"]), 0)
                self.assertEqual(L.main(["encender", "cocina"]), 1)
            self.assertFalse(self.living.dps["20"])
            self.assertEqual(self.cuarto.dps["24"][:4], "0078")  # 120° = verde
            self.assertTrue(self.cuarto.dps["20"])
            texto = out.getvalue()
            self.assertIn("Lámpara Living", texto)
            self.assertIn("Ventilador (enchufe)", texto)
            self.assertIn("No hay ninguna luz que se llame «cocina»", texto)
        finally:
            os.environ.pop("LUCES_DIR", None)


class TestConfiguracion(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        import tinytuya
        self.tinytuya = tinytuya
        self.original = tinytuya.Cloud
        devices = [
            {"id": "d1", "name": "Living", "key": "k1", "category": "dj", "ip": "181.1.2.3",
             "mapping": dict(L.MAPA_LUZ)},
            {"id": "d2", "name": "Sensor puerta", "key": "k2", "category": "mcs", "mapping": {
                "1": {"code": "doorcontact_state", "type": "Boolean", "values": {}}}},
        ]
        tinytuya.Cloud = lambda **kw: FakeCloud(devices=devices, **kw)

    def tearDown(self):
        self.tinytuya.Cloud = self.original
        shutil.rmtree(self.dir)

    def test_conectar_prueba_regiones(self):
        hogar = L.Hogar(self.dir)
        avisos = []
        n = hogar.conectar("buena", "secreto", "", avisar=avisos.append)
        self.assertEqual(n, 1)  # el sensor no se puede controlar: no aparece
        self.assertEqual(hogar.config["region"], "us")
        self.assertNotIn("ip", hogar.todas[0].data)  # la IP pública de la nube no sirve en la casa
        guardado = L.Hogar(self.dir)
        self.assertEqual([x.nombre for x in guardado.todas], ["Living"])
        self.assertTrue(any("América Oeste" in a for a in avisos))

    def test_clave_incorrecta(self):
        with self.assertRaises(L.LucesError) as ctx:
            L.Hogar(self.dir).conectar("mala", "secreto", "us")
        self.assertIn("no son correctos", str(ctx.exception))


class TestVentana3D(unittest.TestCase):
    """La ventana con el cuarto 3D: su servidor local y sus órdenes."""

    def setUp(self):
        import urllib.request
        self.dir = tempfile.mkdtemp()
        self.living = FakeBulb("bf_living_000000000", "0123456789abcdef")
        self.tira = FakeBulb("bf_tira_00000000000", "1111222233334444",
                             dps={"20": True, "21": "colour", "22": 500, "23": 0, "24": "010e03e803e8"})
        L._escribir_json(os.path.join(self.dir, "dispositivos.json"), [
            self.living.info("Lámpara Living"), self.tira.info("Tira LED", category="dd")])
        self._escanear = L.Hogar.escanear
        L.Hogar.escanear = lambda self, segundos=8: 0   # sin búsqueda en la red real
        self.app = L.WebApp(self.dir, puerto=0)
        self.app.iniciar()
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def tearDown(self):
        L.Hogar.escanear = self._escanear
        self.app.httpd.shutdown()
        self.app.httpd.server_close()
        for b in (self.living, self.tira):
            b.close()
        for luz in self.app.real.todas:
            luz._cerrar_local()
        shutil.rmtree(self.dir)

    def pedir(self, ruta, datos=None, token=True):
        import urllib.error
        import urllib.request
        req = urllib.request.Request(self.app.url.rstrip("/") + ruta, method="POST" if datos is not None else "GET",
                                     data=json.dumps(datos).encode() if datos is not None else None,
                                     headers={"X-Token": self.app.token} if token else {})
        try:
            with self.opener.open(req, timeout=10) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.read()

    def api(self, ruta, datos=None):
        code, body = self.pedir(ruta, datos)
        self.assertEqual(code, 200, body)
        return json.loads(body)

    def test_pagina_y_archivos(self):
        code, html = self.pedir("/", token=False)
        self.assertEqual(code, 200)
        self.assertIn(self.app.token.encode(), html)
        self.assertIn(b"cuarto3d.js", html)
        self.assertEqual(self.pedir("/recursos/cuarto3d.js", token=False)[0], 200)
        self.assertEqual(self.pedir("/recursos/three/three.module.min.js", token=False)[0], 200)
        self.assertEqual(self.pedir("/recursos/../luces.py", token=False)[0], 404)
        self.assertEqual(self.pedir("/api/estado", token=False)[0], 403)  # otra página no puede manejar las luces

    def test_estado_y_ubicaciones(self):
        self.app.real.actualizar_todo()
        e = self.api("/api/estado")
        self.assertTrue(e["configurado"])
        luces = {x["nombre"]: x for x in e["luces"]}
        self.assertEqual(luces["Lámpara Living"]["pos"]["forma"], "techo")
        self.assertEqual(luces["Tira LED"]["pos"]["forma"], "tira")
        self.assertEqual(luces["Tira LED"]["modo"], "color")
        self.assertIn("Cine", [x["nombre"] for x in e["escenas"]])

    def test_ordenes(self):
        self.app.real.actualizar_todo()
        r = self.api("/api/luz/bf_living_000000000", {"brillo": 40})
        self.assertEqual(r["luz"]["brillo"], 40)
        self.assertEqual(self.living.received[-1], {"22": 406})
        self.api("/api/luz/bf_living_000000000", {"color": [230, 100]})
        self.assertEqual(self.living.received[-1]["21"], "colour")
        r = self.api("/api/escena", {"nombre": "Cine"})
        self.assertEqual(r["errores"], [])
        self.assertEqual(self.living.dps["22"], 89)
        r = self.api("/api/todas", {"on": False})
        self.assertFalse(self.living.dps["20"])
        self.assertFalse(self.tira.dps["20"])
        code, body = self.pedir("/api/luz/no_existe", {"on": True})
        self.assertEqual(code, 400)

    def test_mover_luz_y_modo_prueba(self):
        self.api("/api/posicion", {"id": "bf_tira_00000000000", "x": .5, "y": 1, "z": -1.4, "forma": "foco", "alcance": 1.5})
        guardado = json.load(open(os.path.join(self.dir, "app.json")))
        self.assertEqual(guardado["ubicaciones"]["bf_tira_00000000000"]["forma"], "foco")
        e = self.api("/api/demo", {"on": True})["estado"]
        self.assertTrue(e["demo"])
        self.assertEqual([x["nombre"] for x in e["luces"]], ["Luz del techo"])
        r = self.api("/api/luz/demo_techo", {"on": True, "brillo": 60})
        self.assertEqual((r["luz"]["encendida"], r["luz"]["brillo"], r["luz"]["via"]), (True, 60, "demo"))
        self.assertEqual(self.living.received, [])  # las luces de verdad no se tocaron


if __name__ == "__main__":
    unittest.main()

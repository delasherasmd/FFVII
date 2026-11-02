# -*- coding: utf-8 -*-
"""Pruebas de identificar.py. El barrido de puertos se prueba sólo contra equipos simulados
en direcciones internas de esta máquina (127.0.0.x), nunca contra una red real."""

import ipaddress
import json
import os
import socket
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import identificar as I  # noqa: E402
from chromecast_falso import FakeCast  # noqa: E402
from renderer_falso import FakeRenderer  # noqa: E402

RED_LOCAL = ipaddress.ip_network("127.0.0.0/29")


class CastHttp(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        body = json.dumps({"name": "Proyector Living", "device_info": {"manufacturer": "Magcubic", "model_name": "HY300 Pro"},
                           "build_info": {"cast_build_revision": "1.56.500000", "system_build_number": "android-11"}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class TestIdentificar(unittest.TestCase):
    def test_barrido_y_preguntas_en_red_simulada(self):
        adb = socket.socket()
        adb.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        adb.bind(("127.0.0.2", 5555))
        adb.listen(5)
        web = ThreadingHTTPServer(("127.0.0.3", 8008), CastHttp)
        threading.Thread(target=web.serve_forever, daemon=True).start()
        try:
            puertos = I.barrer_puertos(RED_LOCAL, "127.0.0.1", timeout=.3)
            self.assertIn(5555, puertos.get("127.0.0.2", []))
            self.assertIn(8008, puertos.get("127.0.0.3", []))
            extra = I.preguntar_http("127.0.0.3", puertos["127.0.0.3"])
            self.assertEqual(extra["chromecast"]["modelo"], "HY300 Pro")
            self.assertEqual(extra["chromecast"]["fabricante"], "Magcubic")
        finally:
            adb.close()
            web.shutdown()
            web.server_close()

    def test_upnp_y_mdns_con_equipos_simulados(self):
        try:
            r = FakeRenderer(name="HY300 Pro", analyze=False)
            c = FakeCast(name="Proyector Living")
        except OSError as e:
            self.skipTest(f"sin multicast aquí: {e}")
        try:
            upnp = I.buscar_upnp(timeout=2)
            fichas = [d for lista in upnp.values() for d in lista]
            hy = next(d for d in fichas if d["nombre"] == "HY300 Pro")
            self.assertEqual(hy["tipo"], "MediaRenderer")
            self.assertIn("AVTransport", hy["servicios"])
            mdns = I.buscar_mdns()
            cast = [s for lista in mdns.values() for s in lista if "Cast" in s["servicio"]]
            self.assertEqual(cast[0]["datos"]["fn"], "Proyector Living")
        finally:
            r.close()
            c.close()

    def test_informe_marca_al_proyector(self):
        red = ipaddress.ip_network("192.168.0.0/24")
        puertos = {"192.168.0.1": [80], "192.168.0.40": [5555, 8008, 8009, 7000]}
        upnp = {"192.168.0.40": [{"ip": "192.168.0.40", "ficha": "x", "nombre": "HY300 Pro", "fabricante": "Magcubic",
                                  "modelo": "HY300", "tipo": "MediaRenderer", "servicios": ["AVTransport", "RenderingControl"]}]}
        mdns = {"192.168.0.40": [{"servicio": "Chromecast / Google Cast", "nombre": "Proyector", "puerto": 8009,
                                  "datos": {"fn": "Proyector", "md": "HY300"}}]}
        macs = {"192.168.0.40": "a4:5e:60:11:22:33", "192.168.0.1": "00:11:22:33:44:55"}
        texto = I.armar_informe(red, "192.168.0.10", puertos, macs, upnp, mdns,
                                {"192.168.0.1": {"web_80": {"titulo": "Router"}}}, {"192.168.0.40": "android-abc"}, 20)
        self.assertIn("★ PROBABLEMENTE EL PROYECTOR · 192.168.0.40", texto)
        self.assertIn("ADB (Android con depuración por red)", texto)
        self.assertIn("MAC a4:5e:60:11:22:33", texto)
        self.assertLess(texto.index("192.168.0.40"), texto.index("192.168.0.1 "))  # el proyector primero


if __name__ == "__main__":
    unittest.main()

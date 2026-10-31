# -*- coding: utf-8 -*-
"""Pruebas de proyectar.py contra un proyector falso (tests/renderer_falso.py).

    python -m unittest discover -s tests -v
"""

import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import proyectar as p  # noqa: E402
from renderer_falso import FakeRenderer  # noqa: E402

FFMPEG = shutil.which("ffmpeg")
FFPROBE = shutil.which("ffprobe")
_no_proxy = urllib.request.build_opener(urllib.request.ProxyHandler({}))

SRT_CP1252 = "1\r\n00:00:00,500 --> 00:00:09,000\r\nHola ñandú, ¿cómo estás?\r\n".encode("cp1252")


def ff(*args):
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", *args], check=True,
                   stdin=subprocess.DEVNULL)


def wait_for(cond, timeout=30.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if cond():
            return True
        time.sleep(0.1)
    return False


def codecs_of(analysis):
    """{'video': 'h264', 'audio': 'ac3+aac'} a partir de lo que vio ffprobe."""
    out = {}
    for s in analysis or []:
        kind = s.get("codec_type")
        out[kind] = out[kind] + "+" + s.get("codec_name") if kind in out else s.get("codec_name")
    return out


class TestUtilidades(unittest.TestCase):
    def test_tiempos(self):
        self.assertEqual(p.fmt_time(3723.5), "1:02:03")
        self.assertEqual(p.fmt_time(3723.5, ms=True), "1:02:03.500")
        self.assertEqual(p.parse_time("1:02:03.5"), 3723.5)
        self.assertEqual(p.parse_time("00:05:30"), 330)
        self.assertEqual(p.parse_time("5:30"), 330)
        self.assertEqual(p.parse_time("90"), 90)
        self.assertIsNone(p.parse_time("NOT_IMPLEMENTED"))
        self.assertIsNone(p.parse_time(""))

    def test_ip(self):
        self.assertTrue(p.looks_like_ip("192.168.0.25"))
        self.assertFalse(p.looks_like_ip("proyector"))
        self.assertFalse(p.looks_like_ip("10.1"))

    def test_parse_probe(self):
        text = """Input #0, matroska,webm, from 'x.mkv':
  Metadata:
    title           : Película
  Duration: 01:45:03.52, start: 0.000000, bitrate: 5000 kb/s
  Chapters:
    Chapter #0:0: start 0.000000, end 300.000000
      Metadata:
        title           : Capítulo 1
  Stream #0:0(eng): Video: hevc (Main 10), yuv420p10le(tv, bt709), 3840x2160 [SAR 1:1 DAR 16:9], 23.98 fps (default)
  Stream #0:1(spa): Audio: ac3, 48000 Hz, 5.1(side), fltp, 384 kb/s (default)
    Metadata:
      title           : Español Latino
  Stream #0:2[0x2](eng): Audio: aac (LC) (mp4a / 0x6134706D), 48000 Hz, stereo, fltp, 128 kb/s
  Stream #0:3(spa): Subtitle: subrip (srt)
  Stream #0:4(eng): Subtitle: hdmv_pgs_subtitle (pgssub), 1920x1080
  Stream #0:5: Video: mjpeg (Baseline), yuvj420p, 600x900, 90k tbr (attached pic)
  Stream #0:6: Attachment: ttf
At least one output file must be specified"""
        info = p.parse_probe(text)
        self.assertAlmostEqual(info.duration, 6303.52)
        self.assertEqual(info.video.codec, "hevc")
        self.assertEqual(info.video.size, (3840, 2160))
        self.assertEqual(info.video.pix_fmt, "yuv420p10le")
        self.assertEqual([a.codec for a in info.audios], ["ac3", "aac"])
        self.assertEqual([a.type_index for a in info.audios], [0, 1])
        self.assertEqual(info.default_audio.title, "Español Latino")
        self.assertEqual(info.audios[0].channels, "5.1(side)")
        self.assertEqual(info.audios[0].label(1), "1. Español Latino – AC3 5.1(side) ★")
        self.assertEqual(info.audios[1].label(2), "2. Inglés – AAC stereo")
        self.assertEqual([s.codec for s in info.subtitles], ["subrip", "hdmv_pgs_subtitle"])
        self.assertEqual(len(info.of("video")), 1)  # la carátula no cuenta
        summary, warnings = p.media_summary(info, 1)
        self.assertIn("Duración 1:45:03", summary)
        self.assertEqual(len(warnings), 2)  # HEVC y AC3

    def test_dispositivos_de_audio_windows(self):
        nuevo = '''[dshow @ 0000020f] "Integrated Camera" (video)
[dshow @ 0000020f]   Alternative name "@device_pnp_\\\\?\\usb#vid"
[dshow @ 0000020f] "Micrófono (Realtek(R) Audio)" (audio)
[dshow @ 0000020f]   Alternative name "@device_cm_{33D9A762}"
[dshow @ 0000020f] "Mezcla estéreo (Realtek(R) Audio)" (audio)'''
        self.assertEqual(p.parse_dshow_devices(nuevo),
                         ["Mezcla estéreo (Realtek(R) Audio)", "Micrófono (Realtek(R) Audio)"])
        viejo = '''[dshow @ 01] DirectShow video devices (some may be both video and audio devices)
[dshow @ 01]  "Integrated Camera"
[dshow @ 01]     Alternative name "@device_pnp_x"
[dshow @ 01] DirectShow audio devices
[dshow @ 01]  "Microphone (Realtek High Definition Audio)"
[dshow @ 01]  "Stereo Mix (Realtek High Definition Audio)"
dummy: Immediate exit requested'''
        self.assertEqual(p.parse_dshow_devices(viejo),
                         ["Stereo Mix (Realtek High Definition Audio)", "Microphone (Realtek High Definition Audio)"])
        mac = '''[AVFoundation indev @ 0x1] AVFoundation video devices:
[AVFoundation indev @ 0x1] [0] FaceTime HD Camera
[AVFoundation indev @ 0x1] [1] Capture screen 0
[AVFoundation indev @ 0x1] AVFoundation audio devices:
[AVFoundation indev @ 0x1] [0] BlackHole 2ch
[AVFoundation indev @ 0x1] [1] MacBook Pro Microphone'''
        self.assertEqual(p.parse_avfoundation_devices(mac), ["BlackHole 2ch", "MacBook Pro Microphone"])

    def test_didl(self):
        meta = p.didl_metadata("Mi <peli> & más", "http://1.2.3.4:8765/m/x/video.mkv", "video/x-matroska",
                               p.FILE_FEATURES, duration=3723.5, size=100,
                               sub_url="http://1.2.3.4:8765/m/y/video.srt")
        root = p.parse_xml(meta.encode())
        self.assertEqual(root.findtext(".//title"), "Mi <peli> & más")
        res = root.findall(".//res")
        self.assertEqual(res[0].get("duration"), "1:02:03.500")
        self.assertTrue(res[0].get("protocolInfo").startswith("http-get:*:video/x-matroska:DLNA.ORG_OP=01"))
        self.assertEqual(root.findtext(".//CaptionInfoEx"), "http://1.2.3.4:8765/m/y/video.srt")

    def test_pace_audio_rellena_silencio(self):
        # Fuente muda (Windows no entrega nada en silencio): debe escribir silencio al ritmo del reloj
        now = [0.0]
        out = []
        stop = threading.Event()

        def get(timeout):
            now[0] += 0.02
            if now[0] >= 2.0:
                stop.set()
            return None
        p.pace_audio(get, out.append, stop, rate=48000, channels=2, clock=lambda: now[0])
        frames = sum(len(b) for b in out) // 8
        self.assertGreater(frames, 48000 * 2.0 - 48000 * 0.13)
        self.assertLessEqual(frames, 48000 * 2.0)
        self.assertTrue(all(not any(b) for b in out))

    def test_pace_audio_descarta_si_se_adelanta(self):
        # Fuente que entrega el doble de lo que corresponde: no debe adelantarse más de ~120 ms
        now = [0.0]
        written = [0]
        stop = threading.Event()

        def get(timeout):
            now[0] += 0.01
            if now[0] >= 3.0:
                stop.set()
            return b"\x01" * (960 * 8)  # 20 ms de audio cada 10 ms

        def write(b):
            written[0] += len(b) // 8
        p.pace_audio(get, write, stop, rate=48000, channels=2, clock=lambda: now[0])
        self.assertLessEqual(written[0], 48000 * 3.0 + 48000 * 0.12 + 960)
        self.assertGreater(written[0], 48000 * 2.8)


class TestServidor(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.path = os.path.join(cls.tmp, "datos.mp4")
        cls.data = bytes(range(256)) * 40
        with open(cls.path, "wb") as f:
            f.write(cls.data)
        cls.server = p.MediaServer(port=0)
        cls.url = f"http://127.0.0.1:{cls.server.port}" + cls.server.add(p.FileMedia(cls.path))

    @classmethod
    def tearDownClass(cls):
        cls.server.close()
        shutil.rmtree(cls.tmp)

    def get(self, rng=None, method="GET"):
        req = urllib.request.Request(self.url, method=method, headers={"Range": rng} if rng else {})
        try:
            with _no_proxy.open(req, timeout=5) as r:
                return r.status, dict(r.headers), r.read()
        except urllib.error.HTTPError as e:
            return e.code, dict(e.headers), e.read()

    def test_completo(self):
        status, headers, body = self.get()
        self.assertEqual(status, 200)
        self.assertEqual(body, self.data)
        self.assertEqual(headers["Content-Type"], "video/mp4")
        self.assertEqual(headers["Accept-Ranges"], "bytes")
        self.assertIn("DLNA.ORG_OP=01", headers["contentFeatures.dlna.org"])

    def test_rangos(self):
        status, headers, body = self.get("bytes=10-19")
        self.assertEqual((status, body), (206, self.data[10:20]))
        self.assertEqual(headers["Content-Range"], f"bytes 10-19/{len(self.data)}")
        self.assertEqual(self.get("bytes=-5")[2], self.data[-5:])
        self.assertEqual(self.get("bytes=100-")[2], self.data[100:])
        self.assertEqual(self.get("bytes=100-999999")[2], self.data[100:])
        self.assertEqual(self.get(f"bytes={len(self.data)}-")[0], 416)

    def test_head_y_404(self):
        status, headers, body = self.get(method="HEAD")
        self.assertEqual((status, body), (200, b""))
        self.assertEqual(headers["Content-Length"], str(len(self.data)))
        with self.assertRaises(urllib.error.HTTPError):
            _no_proxy.open(f"http://127.0.0.1:{self.server.port}/m/nada/x.mp4", timeout=5)


@unittest.skipUnless(FFMPEG and FFPROBE, "hace falta ffmpeg")
class TestConProyectorFalso(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        t = cls.tmp
        cls.srt = os.path.join(t, "peli.srt")
        with open(cls.srt, "wb") as f:
            f.write(SRT_CP1252)
        # Película "difícil": H.264 + audio AC3 5.1 (español) + AAC (inglés) + subtítulos internos
        cls.mkv = os.path.join(t, "peli.mkv")
        ff("-f", "lavfi", "-i", "testsrc2=size=640x360:rate=24:duration=12",
           "-f", "lavfi", "-i", "sine=frequency=440:duration=12",
           "-f", "lavfi", "-i", "sine=frequency=880:duration=12",
           "-sub_charenc", "CP1252", "-i", cls.srt,
           "-map", "0:v", "-map", "1:a", "-map", "2:a", "-map", "3:s",
           "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
           "-c:a:0", "ac3", "-ac:a:0", "6", "-c:a:1", "aac", "-c:s", "srt",
           "-metadata:s:a:0", "language=spa", "-metadata:s:a:0", "title=Español Latino",
           "-metadata:s:a:1", "language=eng", "-metadata:s:s:0", "language=spa", cls.mkv)
        # Video HEVC con audio MP2 (el proyector quizás no lo reproduzca)
        cls.hevc = os.path.join(t, "hevc.mkv")
        ff("-f", "lavfi", "-i", "testsrc2=size=720x480:rate=25:duration=6",
           "-f", "lavfi", "-i", "sine=duration=6", "-c:v", "libx265", "-preset", "ultrafast",
           "-x265-params", "log-level=error", "-c:a", "mp2", cls.hevc)
        cls.fr = FakeRenderer(name="Proyector Sala", ssdp=False)
        cls.renderer = p.load_renderer(cls.fr.location)

    @classmethod
    def tearDownClass(cls):
        cls.fr.close()
        shutil.rmtree(cls.tmp)

    def setUp(self):
        self.caster = p.Caster()
        self.fr.actions.clear()

    def tearDown(self):
        self.caster.close()

    def actions(self):
        return [a for a, _ in self.fr.actions]

    def test_probe_real(self):
        info = p.probe(self.mkv)
        self.assertAlmostEqual(info.duration, 12, delta=0.5)
        self.assertEqual(info.video.codec, "h264")
        self.assertEqual([a.codec for a in info.audios], ["ac3", "aac"])
        self.assertEqual(info.default_audio.title, "Español Latino")
        self.assertEqual(info.subtitles[0].codec, "subrip")
        self.assertEqual(p.find_external_subs(self.mkv), [self.srt])
        self.assertEqual(p.subtitle_charenc(self.srt), "CP1252")

    def test_modo_original(self):
        self.caster.play_file(self.renderer, self.mkv, subtitle=self.srt)
        self.assertTrue(wait_for(self.fr.played.is_set))
        self.assertEqual(self.actions()[-2:], ["SetAVTransportURI", "Play"])
        self.assertIn("/video.mkv", self.fr.uri)
        self.assertIn("video/x-matroska", self.fr.meta)
        self.assertIn("CaptionInfoEx", self.fr.meta)
        self.assertEqual(codecs_of(self.fr.analysis), {"video": "h264", "audio": "ac3+aac", "subtitle": "subrip"})
        st = self.caster.status()
        self.assertEqual((st["state"], st["mode"], st["duration"]), ("PLAYING", "archivo", 100))
        self.assertGreaterEqual(st["requests"], 1)
        self.assertEqual(self.caster.toggle_pause(), "PAUSED_PLAYBACK")
        self.assertEqual(self.fr.state, "PAUSED_PLAYBACK")
        self.assertEqual(self.caster.toggle_pause(), "PLAYING")
        self.caster.seek(7)
        self.assertEqual(self.fr.actions[-1], ("Seek", {"InstanceID": "0", "Unit": "REL_TIME", "Target": "0:00:07"}))
        self.assertGreaterEqual(self.caster.status()["position"], 7)
        self.caster.seek(65)  # más allá del final (12 s): se limita
        self.assertEqual(self.fr.actions[-1][1]["Target"], "0:00:09")
        self.caster.renderer.set_volume(42)
        self.assertEqual(self.fr.volume, 42)
        self.caster.stop()
        self.assertEqual(self.fr.state, "STOPPED")
        self.assertIsNone(self.caster.mode)

    def test_modo_compatible_con_audio_y_subtitulos_internos(self):
        info = p.probe(self.mkv)
        self.caster.play_file(self.renderer, self.mkv, compatible=True, audio=info.audios[1],
                              subtitle=info.subtitles[0], info=info)
        self.assertTrue(wait_for(self.fr.played.is_set, 60))
        self.assertIn("/pelicula.ts", self.fr.uri)
        self.assertIn("DLNA.ORG_OP=00", self.fr.meta)
        self.assertEqual(codecs_of(self.fr.analysis), {"video": "h264", "audio": "aac"})
        self.assertIsNone(self.caster.media.last_error)
        # Adelantar en modo compatible: reinicia la conversión desde ese punto
        first_uri = self.fr.uri
        self.caster.seek(5)
        self.assertNotEqual(self.fr.uri, first_uri)
        self.assertTrue(wait_for(self.fr.played.is_set, 60))
        st = self.caster.status()
        self.assertEqual(st["mode"], "convertido")
        self.assertGreaterEqual(st["position"], 5)
        self.assertAlmostEqual(st["duration"], 12, delta=0.5)

    def test_compatible_copia_el_video_si_ya_sirve(self):
        info = p.probe(self.mkv)
        args = p.build_transcode_args(FFMPEG, self.mkv, info)
        self.assertIn("copy", args)
        self.assertIn("0:a:0", args)
        args = p.build_transcode_args(FFMPEG, self.mkv, info, offset=30, sub_file=self.srt)
        self.assertNotIn("copy", args)
        graph = args[args.index("-filter_complex") + 1]
        self.assertTrue(graph.startswith("[0:v:0]setpts=PTS+30.000/TB,subtitles=filename="))
        self.assertIn("charenc=CP1252", graph)

    def test_compatible_hevc(self):
        info = p.probe(self.hevc)
        self.assertEqual(info.video.codec, "hevc")
        self.caster.play_file(self.renderer, self.hevc, compatible=True, info=info)
        self.assertTrue(wait_for(self.fr.played.is_set, 60))
        self.assertEqual(codecs_of(self.fr.analysis), {"video": "h264", "audio": "aac"})
        self.assertIsNone(self.caster.media.last_error)

    def test_subtitulos_de_imagen_se_superponen(self):
        # ffmpeg no puede fabricar subtítulos de DVD/Blu-ray para la prueba: se revisa el comando
        info = p.probe(self.hevc)
        pgs = p.Stream(index=2, kind="subtitle", codec="hdmv_pgs_subtitle", type_index=0)
        args = p.build_transcode_args(FFMPEG, self.hevc, info, sub_stream=pgs)
        self.assertEqual(args[args.index("-filter_complex") + 1],
                         "[0:v:0][0:s:0]overlay=(W-w)/2:H-h,format=yuv420p[v]")

    def test_subtitulos_quemados_con_nombre_raro(self):
        # Rutas con comillas, corchetes, comas, punto y coma y dos puntos
        weird = os.path.join(self.tmp, "it's [a], b; c:d.srt")
        shutil.copy(self.srt, weird)

        def frame_md5(vf):
            out = subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
                                  "color=black:s=320x240:d=2", "-filter_complex", vf, "-map", "[v]", "-frames:v", "1",
                                  "-ss", "1", "-f", "framemd5", "-"], capture_output=True)
            self.assertEqual(out.returncode, 0, out.stderr.decode())
            return out.stdout.splitlines()[-1]
        with_subs = frame_md5("[0:v]" + p.subtitles_filter(weird) + "[v]")
        without = frame_md5("[0:v]null[v]")
        self.assertNotEqual(with_subs, without)

    def test_proyector_rechaza_play_y_reintenta(self):
        calls = {"n": 0}
        original = self.fr.handle

        def flaky(action, args):
            if action == "Play":
                calls["n"] += 1
                if calls["n"] < 3:
                    self.fr.actions.append((action, args))
                    from renderer_falso import Fault
                    raise Fault(701, "Transition not available")
            return original(action, args)
        self.fr.handle = flaky
        try:
            self.caster.play_file(self.renderer, self.mkv)
        finally:
            self.fr.handle = original
        self.assertEqual(self.actions().count("Play"), 3)
        self.assertEqual(self.fr.state, "PLAYING")

    def test_live_media_prueba_alternativas(self):
        bad = [FFMPEG, "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "noexiste_filtro", "-f", "mpegts",
               "pipe:1"]
        good = [FFMPEG, "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
                "testsrc2=size=320x240:rate=10:duration=2", "-c:v", "libx264", "-f", "mpegts", "pipe:1"]
        media = p.LiveMedia("x.ts", "video/mpeg", [lambda: p.FFmpegProcess(bad), lambda: p.FFmpegProcess(good)])
        server = p.MediaServer(port=0)
        try:
            url = f"http://127.0.0.1:{server.port}" + server.add(media)
            with _no_proxy.open(url, timeout=20) as r:
                data = r.read()
            self.assertGreater(len(data), 1000)
            self.assertEqual(data[0], 0x47)  # sincronismo MPEG-TS
            self.assertEqual(media._good, 1)
        finally:
            server.close()

    def test_error_claro_si_no_hay_archivo(self):
        with self.assertRaises(p.ProyectarError):
            self.caster.play_file(self.renderer, os.path.join(self.tmp, "no-existe.mp4"))


@unittest.skipUnless(FFMPEG and FFPROBE and shutil.which("Xvfb") and sys.platform.startswith("linux"),
                     "hace falta ffmpeg y Xvfb")
class TestPantalla(unittest.TestCase):
    def test_transmitir_pantalla(self):
        self._run(audio=None, expected={"video": "h264"})

    def test_transmitir_pantalla_con_sonido_de_la_pc(self):
        # Mismo camino que «Sonido de la PC» en Windows, con un tono en lugar de la placa de sonido
        def fake_feeder(stdin, stop, rate=48000, channels=2):
            import math
            import struct
            block = rate // 100
            samples = [math.sin(2 * math.pi * 440 * i / rate) * 0.3 for i in range(block)]
            tone = struct.pack(f"<{block * channels}f", *[v for v in samples for _ in range(channels)])
            state = {"n": 0}

            def get(timeout):
                time.sleep(0.005)
                state["n"] += 1
                return None if state["n"] % 50 < 10 else tone  # con silencios, como Windows

            def write(data):
                stdin.write(data)
                stdin.flush()
            p.pace_audio(get, write, stop, rate, channels)
        original = p.loopback_feeder
        p.loopback_feeder = fake_feeder
        try:
            self._run(audio=("loopback",), expected={"video": "h264", "audio": "aac"})
        finally:
            p.loopback_feeder = original

    def _run(self, audio, expected):
        display = ":77"
        xvfb = subprocess.Popen(["Xvfb", display, "-screen", "0", "1280x720x24"],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        old = os.environ.get("DISPLAY")
        os.environ["DISPLAY"] = display
        fr = FakeRenderer(ssdp=False)
        caster = p.Caster()
        try:
            time.sleep(1)
            caster.play_screen(p.load_renderer(fr.location), height=720, fps=24, audio=audio)
            self.assertTrue(wait_for(fr.played.is_set, 60))
            self.assertEqual(codecs_of(fr.analysis), expected)
            self.assertIsNone(caster.media.last_error)
            self.assertIn("/pantalla.ts", fr.uri)
            with self.assertRaises(p.ProyectarError):
                caster.seek(10)
        finally:
            caster.close()
            fr.close()
            xvfb.terminate()
            xvfb.wait()
            if old is None:
                os.environ.pop("DISPLAY", None)
            else:
                os.environ["DISPLAY"] = old


class TestBusqueda(unittest.TestCase):
    def test_descubrir_y_listar(self):
        try:
            fr = FakeRenderer(name="Proyector Living", analyze=False)
        except OSError as e:
            self.skipTest(f"no se puede usar SSDP aquí: {e}")
        try:
            found = p.discover(timeout=2)
            names = [r.name for r in found]
            self.assertIn("Proyector Living", names)
            r = found[names.index("Proyector Living")]
            self.assertTrue(r.avt_url.endswith("/ctl/avt"))  # controlURL relativa resuelta bien
            self.assertEqual([x.name for x in p.discover(timeout=1.5, hosts=[fr.ip])], ["Proyector Living"])
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(p.main(["--listar"]), 0)
            self.assertIn("Proyector Living", out.getvalue())
        finally:
            fr.close()


if __name__ == "__main__":
    unittest.main()

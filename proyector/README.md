# Proyectar: películas de la PC al proyector por WiFi

Programa para ver en el proyector (o en un televisor smart) las películas que tienes
en la PC, **sin cables**: la PC y el proyector solo tienen que estar en la misma red WiFi.

Hace tres cosas:

| Modo | Para qué sirve | Calidad | Retraso |
|---|---|---|---|
| **Película · Original** | Mandar un archivo (MP4, MKV, AVI…) tal cual. El proyector lo reproduce solo. | Máxima | Ninguno |
| **Película · Compatible** | Lo mismo, pero convirtiéndolo en vivo. Úsalo si **no se ve o no se escucha** (audio AC3/DTS, video HEVC…) o si quieres **elegir el idioma o los subtítulos**. | Muy buena | Ninguno |
| **Pantalla de la PC** | Mostrar todo lo que se ve y se escucha en la PC (Netflix en el navegador, YouTube, etc.). | Buena | 2 a 5 segundos |

Funciona con proyectores y televisores compatibles con **DLNA**. En los menús suele
aparecer como «DLNA», «Media Renderer», «DMR», «Screen Mirroring», «EShare» o «Multi-Screen».
Lo traen casi todos los proyectores smart con Android.

---

## Cómo empezar (Windows)

1. **Instala Python** desde <https://www.python.org/downloads/>.
   En el instalador **marca la casilla «Add python.exe to PATH»**.
2. **Descarga esta carpeta** (`proyector`) en la PC.
3. Haz **doble clic en `Proyectar.bat`**.
   La primera vez instala ffmpeg y la captura de sonido, lo que puede tardar un minuto.
4. Si Windows pregunta por el **Firewall**, marca **redes privadas y públicas** y elige **Permitir**.
   Sin ese permiso el proyector no puede pedirle el video a la PC.
5. En el **proyector**, abre la app de DLNA / Screen Mirroring. Algunos solo reciben videos con esa app abierta.
6. En el programa, elige el proyector, pulsa **Elegir película…** y después **▶ Proyectar película**.

> **Atajo:** arrastra una película y suéltala sobre `Proyectar.bat`. Se abre con ese archivo ya elegido.

Mientras proyectas, desde la ventana puedes **pausar**, **adelantar o atrasar** (la barra y
los botones de 10 y 30 segundos), **detener** y cambiar el **volumen**.

En Mac o Linux: `python3 proyectar.py` (para los modos Compatible y Pantalla hace falta
`ffmpeg` instalado).

### Subtítulos

* Si junto a la película hay un `.srt` con el mismo nombre (`Pelicula.srt` o `Pelicula.es.srt`),
  el programa lo elige solo.
* En modo **Original**, los subtítulos se envían al proyector, pero muchos no los muestran.
* En modo **Compatible**, los subtítulos se dibujan sobre la imagen y se ven siempre.
  También funcionan los subtítulos que vienen dentro del MKV.
* Los `.srt` en español guardados con acentos «raros» (Windows-1252) se leen bien.

---

## Identificar el proyector

`IdentificarProyector.exe` (o `python identificar.py`) revisa la red WiFi de la casa y arma un
informe con cada equipo y lo que sabe hacer: DLNA, Chromecast, AirPlay, Android con ADB por red,
Miracast. El informe queda en el escritorio (`informe_proyector.txt`) y copiado en el portapapeles.

## Copia de seguridad del proyector (Android)

`RespaldoProyector.exe` (o `python respaldo_proyector.py`, que necesita `pip install adb-shell`)
se conecta al proyector por WiFi con ADB y **sólo lee**: no instala, no borra ni cambia ajustes.
Guarda en el escritorio una carpeta «Respaldo proyector …» con:

* `INFORME.txt`: marca, modelo, versión de Android, chip, pantalla de inicio actual, apps instaladas
  y programas del fabricante.
* `apps/`: copia de la pantalla de inicio original y de las apps instaladas (archivos `.apk`).
* La lista completa de programas y los ajustes del sistema (archivos `.txt`).

Requisitos: en el proyector, *Opciones de desarrollador → Depuración USB* (y *Depuración por red* si
aparece). La primera vez el proyector pregunta «¿Permitir depuración?»: marca «Permitir siempre» y acepta.

## Si algo no funciona

| Problema | Solución |
|---|---|
| **No aparece el proyector** | Revisa que esté encendido y en la **misma WiFi** que la PC (no en la red «de invitados»). Abre en el proyector la app de DLNA / Screen Mirroring y pulsa **Buscar**. Si sabes la IP del proyector (aparece en su menú de red), usa **Por IP…**. |
| El programa dice «el proyector todavía no pidió el video» | Es el **Firewall de Windows**. Ve a *Panel de control → Firewall de Windows → Permitir una aplicación* y habilita **Python** en redes privadas y públicas. Otra opción es marcar tu WiFi como *Red privada*. |
| **Se ve pero no se escucha** | La película tiene audio AC3 o DTS (el programa te avisa). Usa el modo **Compatible**. |
| **Se escucha pero no se ve**, o el proyector dice «formato no compatible» | Usa el modo **Compatible**. |
| Se corta o se traba | Acerca el proyector al router o usa la red de 5 GHz. En el modo Pantalla, baja la calidad a 720p. |
| Modo Pantalla **sin sonido** | En «Sonido» elige «Sonido de la PC (automático)». Si no aparece, cierra y vuelve a abrir `Proyectar.bat` para que lo instale. |
| Modo Pantalla: Netflix o Disney+ se ven **en negro** | Esas páginas bloquean la captura en algunos navegadores. Prueba con Chrome o Firefox en lugar de Edge, o usa la app del propio proyector. |

Si necesitas ayuda, el registro detallado de lo que hizo el programa está en
`%TEMP%\proyectar.log` (en Windows; escribe esa ruta en el Explorador).

### Otras opciones que ya trae Windows

* **Win + K** (Proyectar → «Conectar a una pantalla inalámbrica»). Usa Miracast y tiene menos retraso
  para duplicar la pantalla, si el proyector y la placa WiFi de la PC lo admiten.
* Si el proyector tiene **Chromecast** integrado (Google TV), en Chrome: menú ⋮ → **Transmitir…**

---

## Uso por consola (opcional)

```bash
python proyectar.py --listar                           # buscar proyectores
python proyectar.py "C:\Peliculas\peli.mkv"            # proyectar (modo Original)
python proyectar.py peli.mkv --compatible --audio 2    # segunda pista de audio
python proyectar.py peli.mkv --subs peli.srt           # con subtítulos (o --subs 1 para la pista interna)
python proyectar.py peli.mkv -p "Living"               # elegir el proyector por nombre o IP
python proyectar.py --pantalla --calidad 720           # transmitir la pantalla
```

Mientras reproduce: `p` pausa o sigue, `+` adelanta 30 s, `-` atrasa 10 s, `ir 1:20:00`,
`vol 50`, `s` sale. Con `Enter` muestra el estado.

## Cómo funciona

1. Busca en la red los equipos que se anuncian como *Media Renderer* (SSDP/UPnP).
2. Abre un pequeño servidor web en la PC (puerto 8765) que **solo** entrega la película
   elegida, y solo mientras el programa está abierto.
3. Le dice al proyector «reproduce este enlace» (UPnP AVTransport). El proyector descarga el
   video y lo reproduce con su propio reproductor.
4. En los modos Compatible y Pantalla, ffmpeg convierte el video en vivo a H.264 + AAC
   (MPEG-TS), que reproduce cualquier proyector. Si el video ya es H.264, solo convierte el audio
   y casi no usa el procesador.

Solo usa la biblioteca estándar de Python. ffmpeg (`imageio-ffmpeg`) y `soundcard`
(sonido en el modo Pantalla) son opcionales y `Proyectar.bat` los instala solo.

## Pruebas

`tests/renderer_falso.py` es un proyector simulado: responde a la búsqueda, acepta las
órdenes y descarga el video como lo haría uno real. Con él se prueba todo sin hardware:

```bash
python -m unittest discover -s tests -v
```

Para probar a mano, ejecuta `python tests/renderer_falso.py` en una PC y `proyectar.py` en otra.

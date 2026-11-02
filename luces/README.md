# Luces: la luz del techo de Smart Life, desde la PC

Programa para manejar desde la computadora la **luz del techo** (Smart Life) del cuarto:
prender y apagar, brillo, tono (cálida o fría), colores y **escenas** como «Cine» o «Relax».

La ventana muestra **el cuarto en 3D**: el escritorio con el monitor, el teclado RGB y el joystick,
la PC, las dos sillas, el bajo Precision sunburst, la planta y el amplificador. **La luz del techo del cuarto
3D copia a la real**: si la pones roja, el cuarto se tiñe de rojo; si la apagas, queda a oscuras y sólo
brillan el monitor, el teclado y la PC. Y al revés: si alguien la cambia desde el celular, el cuarto 3D
se actualiza solo.

| | |
|---|---|
| **Panel de la derecha** | Botón para prender o apagar, barras de brillo y tono, y colores. |
| **Escenas** | Cine (muy tenue y cálida), Relax, Lectura, Día, Noche (naranja suave) y Fiesta (un color vivo distinto cada vez). |
| **+ Guardar actual** | Guarda cómo está la luz ahora como una escena propia. |
| **El cuarto 3D** | Arrastra con el mouse para girarlo, la rueda acerca y aleja, doble clic vuelve a la vista inicial. |
| **Modo prueba** | En *Ajustes*: una luz de mentira para probar el programa sin tocar la real. |

## Instalar (Windows)

1. Copia **`Luces.exe`** al escritorio y ábrelo con doble clic. No hace falta instalar nada más.
2. Como el programa no está firmado, Windows puede mostrar **«Windows protegió su PC»**.
   Elige **Más información → Ejecutar de todas formas**. Pasa sólo la primera vez.
3. Si Windows pregunta por el **Firewall**, elige **Permitir**. Así el programa encuentra la luz en el WiFi.
4. Se abre la ventana con el cuarto. La primera vez te pide conectar la cuenta de Smart Life
   (ver abajo). Mientras tanto puedes pulsar **«Ver el cuarto en modo prueba»**.

Al cerrar la ventana, el programa se cierra solo.

> También funciona sin el `.exe`: con Python instalado, `Luces.bat` o `python luces.py`.
> Para volver a armar el `.exe` en Windows: `construir_exe.bat`.

---

## Primera vez: conectar tu cuenta de Smart Life (unos 10 minutos)

Smart Life no deja que otros programas manejen las luces sin permiso. Ese permiso se crea
**gratis y una sola vez** en la página de Tuya, la empresa que fabrica Smart Life.

1. Ten a mano el celular con la app Smart Life.
2. Abre **`Luces.exe`**. La ventana muestra los mismos pasos que siguen.
3. Entra a <https://platform.tuya.com> y crea una cuenta.
4. Arriba: **Cloud → Development → Create Cloud Project**.
   * *Project Name*: el que quieras (por ejemplo «Luces casa»).
   * *Industry*: **Smart Home**. *Development Method*: **Smart Home**.
   * *Data Center*: **Western America** si estás en Latinoamérica. Tiene que ser la región de tu
     cuenta de Smart Life; si no estás seguro, después elige «Automática» en el programa.
5. En la pantalla de servicios (APIs) que aparece, deja los que vienen marcados y confirma.
6. Dentro del proyecto: pestaña **Devices → Link App Account → Add App Account**. Aparece un QR.
7. En el celular, en **Smart Life**: pestaña **Yo** → ícono de **escanear** (arriba a la derecha) →
   escanea el QR → **Confirmar**.
8. En la pestaña **Overview** del proyecto copia **Access ID** y **Access Secret**.
9. Pégalos en el programa y pulsa **Conectar**. En unos segundos aparecen tus luces.

Si Windows pregunta por el **Firewall**, elige **Permitir**. Así el programa encuentra las luces en el WiFi.

> **Sobre el «período de prueba» de Tuya:** el servicio de la página de Tuya (IoT Core) es gratis,
> pero hay que renovarlo cada algunos meses desde la misma página. **Aunque venza, las luces se
> siguen manejando por el WiFi de la casa.** Solo deja de funcionar el plan B por internet y el
> botón «Configurar» (que hace falta si agregas luces nuevas o vuelves a vincular una en la app).

---

## Si algo no funciona

| Problema | Solución |
|---|---|
| «El Access ID o el Access Secret no son correctos» | Cópialos de nuevo desde *Overview*, sin espacios al principio ni al final. |
| «No pude traer las luces… permission deny» | Falta el paso 6–7 (vincular la cuenta de Smart Life con el QR), o el servicio *IoT Core* no está activo. |
| «La cuenta no tiene dispositivos en esta región» | El *Data Center* del proyecto no es el de tu cuenta. Elige región «Automática»; si sigue igual, crea otro proyecto con otra región. |
| Una luz dice **«por internet»** en lugar de «por WiFi» | La PC y la luz no están en la misma red, o el Firewall bloqueó la búsqueda. Permite a Python en el Firewall y pulsa **Actualizar**. |
| Una luz dice **«Sin conexión»** | Está apagada desde la tecla de la pared o sin WiFi. Préndela y pulsa **Actualizar**. |
| Agregaste una luz nueva en Smart Life | Pulsa **Configurar… → Conectar** otra vez. |

El registro detallado está en `%TEMP%\luces.log`.

## Desde la consola (o accesos directos)

```bash
python luces.py lista                   # cómo están todas
python luces.py apagar                  # apaga todas las luces
python luces.py encender living         # por nombre (o parte del nombre)
python luces.py brillo 30 living
python luces.py tono 0                  # 0 = cálida … 100 = fría
python luces.py color violeta cuarto    # rojo, naranja, amarillo, verde, cian, azul, violeta, rosa o #rrggbb
python luces.py escena cine
```

En Windows también funciona como `Luces.bat escena cine`. Puedes hacer un acceso directo con eso
y ponerle un atajo de teclado.

## Si te mudas

El cuarto 3D está modelado en `recursos/cuarto3d.js` (paredes, muebles, el bajo, la ubicación
de la luz del techo). Para otro cuarto se cambia ese archivo y se vuelve a armar el `.exe`.

## Cómo funciona

* La primera vez, con tu permiso, la nube de Tuya entrega la lista de tus luces y la **clave
  local** de cada una. Queda guardada solo en esta PC, en `%APPDATA%\Luces`.
* Después el programa habla con cada luz **directo por el WiFi**, con el mismo protocolo cifrado
  que usa la app (vía la biblioteca [tinytuya](https://github.com/jasonacox/tinytuya)).
* Si una luz no contesta por WiFi, prueba por internet con la API oficial de Tuya.
* La ventana es una página local (sólo en esta PC, `127.0.0.1`) que se abre con Edge en modo
  aplicación, sin barras de navegador. El cuarto 3D usa [three.js](https://threejs.org) (incluido en
  `recursos/three`, licencia MIT), así que funciona sin internet.

## Pruebas

`tests/tuya_falso.py` simula lamparitas reales, con el protocolo cifrado incluido:

```bash
python -m unittest discover -s tests -v
```

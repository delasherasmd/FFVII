# Final Fantasy VII para R36S, como port y desde un solo archivo

Un port para la **R36S** (y otras consolas RK3326 con ArkOS, dArkOS,
ROCKNIX o AmberELEC). **Final Fantasy VII** aparece en el menú **Ports** y
se juega con un solo archivo: los 3 discos van juntos en un `.pbp`.

## ¿Hay un port nativo de FF7 para la R36S?

**No** (revisado en octubre de 2026):

- **PortMaster**, el catálogo de ports para estas consolas, no tiene FF7
  (revisé su catálogo completo, 1436 ports).
- **[Xeeynamo/ff7-decomp](https://github.com/Xeeynamo/ff7-decomp)** es la
  decompilación de la versión de PlayStation. Todavía no está completa, y lo
  que genera es otra vez el ejecutable de PS1, no un programa para Linux/ARM.
- Las decompilaciones de la versión de PC (1998) son parciales, y esa versión
  es para Windows x86, que la R36S no puede correr.

Por eso este "port" corre **tus discos de PS1** con **RetroArch +
PCSX-ReARMed**, el emulador de PS1 que ya trae la consola. Un lanzador en el
menú Ports se encarga de todo, y los 3 discos quedan unidos en un solo
archivo `Final Fantasy VII.pbp`.

## Qué hay en este repositorio

| Carpeta / archivo | Para qué sirve |
|---|---|
| `ports/Final Fantasy VII.sh` | El lanzador que aparece en el menú Ports |
| `ports/finalfantasy7/bin/pbpack` | El programa que junta los discos (compilado para la R36S, ARM64) |
| `ports/finalfantasy7/discos/` | Acá van tus discos `.bin` (o `.cue` + `.bin`) |
| `pc/` | El mismo programa para Windows y Linux, si preferís armar el `.pbp` en la PC |
| `src/pbpack.c` | Código fuente del programa |
| `tests/` | Pruebas (discos falsos y prueba con el emulador real) |

**Los discos del juego no están ni tienen que estar en este repositorio**
(ver [más abajo](#no-subas-los-discos-a-github)).

## Instalación en la R36S

1. Descargá este repositorio: botón verde **Code → Download ZIP** y
   descomprimilo.
2. Poné la tarjeta SD de la consola en la PC y abrí la carpeta `ports`:
   - **ArkOS / dArkOS**: partición `EASYROMS` → `ports` (si usás dos
     tarjetas, la de los juegos).
   - **ROCKNIX / AmberELEC**: `roms/ports`.
3. Copiá **el contenido** de la carpeta `ports/` del ZIP dentro de esa
   carpeta `ports`. Tiene que quedar así:
   ```
   ports/
   ├── Final Fantasy VII.sh
   └── finalfantasy7/
       ├── bin/pbpack
       └── discos/
   ```
4. Copiá los **3 archivos `.bin`** de FF7 en `ports/finalfantasy7/discos/`.
   Alcanza con los `.bin`; si también tenés los `.cue`, copialos igual.
   Los nombres no importan: el orden se saca del código de cada disco.
5. *(Recomendado)* Copiá una BIOS de PS1 (`scph1001.bin` o `scph5501.bin`)
   en la carpeta `bios` de la SD. Sin BIOS también anda, con la BIOS
   interna del emulador.
6. Poné la SD en la consola, reiniciala y entrá a **Ports →
   Final Fantasy VII**.

**La primera vez** el lanzador junta los 3 discos en
`ports/finalfantasy7/Final Fantasy VII.pbp`, lo verifica y arranca el juego.
Tarda **unos 5 a 10 minutos**. En algunos sistemas la pantalla queda negra
mientras tanto: **no apagues la consola**. Las siguientes veces arranca
directo.

Cuando el juego ya funciona, podés **borrar los `.bin`/`.cue`** de
`discos/` para recuperar espacio. Hace falta lugar libre para el `.pbp`
(alrededor de 1,3 a 1,5 GB) además de los discos, solo durante esa primera
vez.

## Cambiar de disco

Cuando el juego pida el disco 2 (o el 3):

1. Abrí el menú de RetroArch (en ArkOS: **SELECT + X**).
2. **Control de discos** (*Disc Control*) → **Expulsar disco**
   (*Eject Disc*).
3. **Índice del disco actual** (*Current Disc Index*) → elegí el **2**
   (o el 3).
4. **Insertar disco** (*Insert Disc*) y volvé al juego.

No hay otro archivo que buscar: los 3 discos están dentro del `.pbp`.
RetroArch se acuerda en qué disco quedaste para la próxima vez.

## Partidas guardadas

La memory card la guarda RetroArch como siempre, con el nombre
`Final Fantasy VII.srm` en su carpeta de partidas. Si ya venías jugando
FF7 desde el menú de PlayStation, renombrá tu `.srm` viejo (por ejemplo
`Final Fantasy VII (USA) (Disc 1).srm`) a `Final Fantasy VII.srm` y seguís
desde donde estabas.

## Opcional: armar el `.pbp` en la PC (más rápido)

**Windows:** poné `pc/pbpack-windows-x86_64.exe` y `pc/juntar_discos.bat`
en la carpeta donde están los 3 `.bin` y hacé doble clic en
`juntar_discos.bat`.

**Linux:** `pc/juntar_discos.sh carpeta_con_los_discos`

Después copiá el `Final Fantasy VII.pbp` que se crea a
`ports/finalfantasy7/` en la SD. Así no hace falta copiar los `.bin` a la
consola.

Ese `.pbp` también se puede poner en la carpeta `psx` de la SD para jugarlo
desde el menú de PlayStation, como cualquier juego.

## Problemas comunes

- **"No hay discos todavía"**: los `.bin` no están en
  `ports/finalfantasy7/discos/`.
- **"parece una imagen ISO de 2048 bytes"**: ese archivo no es un ripeo
  completo del disco. Hace falta el `.bin` de 2352 bytes por sector (el que
  viene con un `.cue`).
- **"No se encontró RetroArch con un núcleo de PlayStation"**: falta el
  núcleo `pcsx_rearmed`. Actualizá el sistema de la consola.
- **No aparece en Ports**: reiniciá la consola o actualizá la lista de
  juegos.
- **Volver a armar el `.pbp`**: borrá `ports/finalfantasy7/Final Fantasy VII.pbp`
  con los discos en `discos/` y abrí el juego otra vez.
- Todo lo que pasó en la última ejecución queda en
  `ports/finalfantasy7/log.txt`.

Al principio de `Final Fantasy VII.sh` hay dos opciones:
`PREFER_RA=64` o `32` (qué RetroArch usar si la consola tiene los dos) y
`BORRAR_DISCOS=1`, para borrar los `.bin`/`.cue` automáticamente cuando el
`.pbp` quedó creado y verificado.

## No subas los discos a GitHub

Este repositorio es **público**. Si subís los `.bin`, cualquiera los puede
descargar, y GitHub puede dar de baja el repositorio por copyright. Además
GitHub no acepta archivos de más de 100 MB, y cada disco pesa unos 700 MB.
No hace falta subirlos: todo el proceso corre en la consola o en tu PC. El
`.gitignore` ya excluye `.bin`, `.cue`, `.pbp`, `.chd` e `.iso`.

## Detalles técnicos

`pbpack` arma un `.pbp` multidisco (formato EBOOT de PS1, `PSTITLEIMG` con
un `PSISOIMG` por disco). Comprime cada bloque de 16 sectores con zlib,
usando todos los núcleos del procesador. El formato se armó leyendo los
lectores de
[PCSX-ReARMed](https://github.com/libretro/pcsx_rearmed/blob/master/libpcsxcore/cdriso.c)
y [DuckStation/SwanStation](https://github.com/stenzek/duckstation/blob/master/src/util/cd_image_pbp.cpp).
Un detalle importante: la entrada final del índice lleva el offset de fin
de datos. Las herramientas tipo popstation dejan esa entrada en cero, y con
eso PCSX-ReARMed no puede leer el último bloque de cada disco.

```
pbpack [opciones] -o salida.pbp disco1.cue|bin [disco2 ...]
  -t TITULO  -i ID  -l NIVEL(1-9)  -j HILOS  -s (ordenar por código)
  -V (verificar)  -n (solo mostrar info)  -q
```

Compilar los binarios (Ubuntu/Debian con `gcc`, `gcc-aarch64-linux-gnu`,
`gcc-mingw-w64-x86-64`): `./tools/build.sh`. El script descarga zlib 1.3.1
y verifica su SHA-256.

Pruebas: `./tests/run_tests.sh`. Con `PCSX_CORE=/ruta/pcsx_rearmed_libretro.so`
también arranca cada disco en el núcleo real del emulador. Lo que se probó:

- Los 3 discos se detectan en PCSX-ReARMed y cada uno arranca con su
  código (SCUS94163/4/5), incluso con los archivos de arranque en el último
  bloque del disco.
- Un `.pbp` de 2,6 GB y 4 discos arranca incluso en el disco guardado más
  allá de los 2 GB.
- Los binarios de ARM64 (la R36S, probado con qemu), Linux y Windows
  (probado con Wine) generan exactamente el mismo archivo, igual byte a byte.
- Los datos descomprimidos son idénticos a los `.bin` originales.
- El lanzador se probó simulando ArkOS y ROCKNIX: sin discos, con `.bin`
  sueltos, con `.cue` + `.bin`, con el `.pbp` ya armado y con `.chd`.

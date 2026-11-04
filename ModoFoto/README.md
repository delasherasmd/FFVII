# Modo Foto

Addon para sacar capturas de pantalla limpias en **WoW Classic Era** y **WoW Forever**: oculta la interfaz y también los nombres, las placas y los bocadillos de chat que aparecen sobre los personajes. Al terminar, deja todo como estaba.

## Instalación

Copiá la carpeta `ModoFoto` a `World of Warcraft\<versión>\Interface\AddOns\`:

- Classic Era: `_classic_era_`
- Forever: la carpeta de Forever

Tiene que quedar `...\Interface\AddOns\ModoFoto\ModoFoto.toc`.

## Uso

| Comando | Qué hace |
|---|---|
| `/foto` | Entra o sale del modo foto. Con la interfaz oculta, **Impr Pant** saca la captura y **Esc** sale. |
| `/foto ya` | Saca una foto limpia en el momento y vuelve a mostrar la interfaz. |
| `/foto timer [segundos]` | Cuenta regresiva (3 segundos por defecto) y foto limpia. Sirve para acomodar la cámara con el mouse antes de la foto. |
| `/foto tiempo <segundos>` | Cambia la duración por defecto del temporizador (de 1 a 60). |
| `/foto nombres` | Elige si se ocultan o no los nombres, las placas y los bocadillos. |
| `/foto calidad` | Configura las capturas en PNG con la máxima calidad. |

También hay atajos de teclado en **Opciones > Atajos de teclado > AddOns > Modo Foto**.

Las capturas se guardan en `World of Warcraft\<versión>\Screenshots`.

## Notas

- No funciona en combate: el juego no deja ocultar la interfaz con un addon durante el combate. Si entrás en combate en modo foto, la interfaz vuelve sola.
- Si el juego se cierra en modo foto, los nombres y las placas se restauran la próxima vez que entres.
- Para que no salga el círculo de selección en la foto, quitá el objetivo antes de sacarla.

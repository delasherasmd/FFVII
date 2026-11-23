# Modo Foto

Addon para sacar capturas de pantalla limpias en **WoW Classic Era** y **WoW Forever**. En la foto no sale nada de interfaz: ni barras, ni chat, ni ventanas de otros addons, ni los nombres de personajes y PNJ, ni las placas de vida, los bocadillos de chat, los números de combate o los íconos de interacción. Al terminar, deja todo como estaba.

## Instalación

Copiá la carpeta `ModoFoto` a `World of Warcraft\<versión>\Interface\AddOns\`:

- Classic Era: `_classic_era_`
- Forever: `_forever_`

Tiene que quedar `...\Interface\AddOns\ModoFoto\ModoFoto.toc`.

## El botón

Aparece un botón con un **catalejo** arriba a la derecha de la pantalla.

| Acción | Qué hace |
|---|---|
| **Clic** | Oculta todo, saca la foto y vuelve a mostrar todo. La interfaz desaparece solo un instante. |
| **Clic derecho** | Lo mismo, con cuenta regresiva (3 segundos), para acomodar la cámara antes. |
| **Ctrl+clic** | Entra en el modo foto y se queda ahí: **Impr Pant** saca fotos y **Esc** sale. |
| **Mayús+arrastrar** | Mueve el botón a otro lugar. |

El botón no sale en las fotos. Si no lo querés en pantalla, `/foto boton` lo oculta y lo vuelve a mostrar.

## La cámara

La cámara del juego siempre sigue al personaje: ningún addon la puede soltar para que vuele libre. Lo que sí se puede es **correrla a un costado**, para que el personaje no quede en el centro de la foto, y **alejarla más** que lo normal.

| Comando | Qué hace |
|---|---|
| `/foto camara izquierda` | En el modo foto, la cámara se corre a la izquierda. |
| `/foto camara derecha` | En el modo foto, la cámara se corre a la derecha. |
| `/foto camara 2` | Corrida a la medida que quieras, de -3 (izquierda) a 3 (derecha). |
| `/foto camara centro` | Personaje en el centro, como siempre. |
| `/foto lejos` | Elige si en el modo foto se puede alejar la cámara más que lo normal (viene activado). |

Para moverla **mientras estás en el modo foto**, asigná teclas en **Opciones > Atajos de teclado > AddOns > Modo Foto** a *Correr la cámara a la izquierda*, *a la derecha* y *Centrar la cámara*. Cada vez que apretás, la cámara se corre un poco y aparece un aviso que no sale en la foto. Con la rueda del mouse acercás o alejás, y con el botón derecho girás alrededor del personaje.

La cámara solo se corre durante el modo foto. Al salir vuelve a estar centrada, y el alejamiento vuelve a ser el normal.

## Comandos

| Comando | Qué hace |
|---|---|
| `/foto` | Entra o sale del modo foto. Con la interfaz oculta, **Impr Pant** saca la captura y **Esc** sale. |
| `/foto ya` | Saca una foto limpia en el momento y vuelve a mostrar la interfaz (lo mismo que el clic en el botón). |
| `/foto timer [segundos]` | Cuenta regresiva (3 segundos por defecto) y foto limpia. |
| `/foto tiempo <segundos>` | Cambia la duración por defecto del temporizador (de 1 a 60). |
| `/foto nombres` | Elige si se ocultan o no los nombres, las placas y los bocadillos. |
| `/foto boton` | Muestra u oculta el botón. |
| `/foto calidad` | Configura las capturas en PNG con la máxima calidad. |

Los atajos de teclado para la foto, el temporizador y la cámara están en **Opciones > Atajos de teclado > AddOns > Modo Foto**.

Las capturas se guardan en `World of Warcraft\<versión>\Screenshots`.

## Notas

- No funciona en combate: el juego no deja ocultar la interfaz con un addon durante el combate. Si entrás en combate en modo foto, la interfaz vuelve sola.
- Si el juego se cierra en modo foto, los nombres, las placas y la cámara se restauran la próxima vez que entres.
- No se puede sacar la imagen del mundo "por debajo" de la interfaz: el juego guarda la pantalla tal como se ve. Por eso el addon oculta todo, espera a que el juego dibuje la pantalla sin interfaz y recién ahí saca la foto.
- Para que no salga el círculo de selección en la foto, quitá el objetivo antes de sacarla.
- Correr la cámara usa una opción del juego que Blizzard marca como experimental. Si en alguna versión no existe, el addon avisa y lo demás funciona igual.

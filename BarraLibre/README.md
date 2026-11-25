# Barra Libre

Addon para **WoW Forever** y **WoW Classic Era**: barras propias para pociones, objetos, hechizos y macros que usás de vez en cuando, **con teclas del teclado**. Funcionan aunque juegues **con mando** (el modo mando del juego o ConsolePort), porque no dependen de las barras de acción ni de lo que tengas asignado en el mando.

Podés tener **hasta 6 barras**, cada una **horizontal o vertical**, con 1 a 12 botones, en una o varias filas (o columnas).

Además, una **barra de clase** que se arma sola con lo que tu personaje conoce: los tótems del chamán, las auras y bendiciones del paladín, los aspectos del cazador, los venenos del pícaro, etc.

## Instalación

Copiá la carpeta `BarraLibre` a `World of Warcraft\<versión>\Interface\AddOns\` (`_forever_` o `_classic_era_`). Tiene que quedar `...\AddOns\BarraLibre\BarraLibre.toc`.

Cada personaje guarda sus propias barras y teclas.

## Llenar la barra

- **Arrastrá** a un botón un objeto de las bolsas, un hechizo del libro o una macro. Si el botón ya tenía algo, lo que había queda en el cursor.
- `/barra auto` llena los botones vacíos con lo que tengas en las bolsas: primero pociones, después vendas, comida y bebida, elixires, frascos y pergaminos, y la piedra de hogar al final.
- Sin mouse: `/barra poner 3 Poción de sanación`, o escribí `/barra poner 3 ` y hacé Mayús+clic en el objeto.
- Para sacar algo: arrastralo fuera del botón (con la barra bloqueada, Mayús+arrastrar), o `/barra quitar 3`.

Cada botón muestra cuántos te quedan (gris si no te queda ninguno), el tiempo de reutilización y su tecla.

## Teclas

- `/barra teclas`: los botones se marcan en verde. Pasá el mouse por un botón y apretá la tecla, con Mayús, Ctrl o Alt si querés. **Supr** borra la tecla; **Esc** termina. Si la tecla ya hacía otra cosa (por ejemplo, un botón de la barra de acción), te avisa: mientras esté el addon, la tecla usa la Barra Libre.
- Sin mouse: `/barra tecla 3 SHIFT-1` (borrar: `/barra tecla 3 borrar`). Para otra barra: `/barra 2 tecla 1 F2`.
- También están en **Opciones > Atajos de teclado > AddOns > Barra Libre**.

Las teclas funcionan en combate. Lo que no se puede en combate (porque el juego no lo permite) es cambiar los botones o las teclas: si lo intentás, se aplica al terminar el combate.

## Varias barras

| Comando | Qué hace |
|---|---|
| `/barra barras 3` | Usar 3 barras (de 1 a 6). Las nuevas aparecen arriba de la principal o a los costados. |
| `/barra 2 vertical` / `/barra 2 horizontal` | Orientación de la barra 2. También: **clic derecho en la agarradera** de la barra. |
| `/barra 2 botones 8` | Cuántos botones tiene la barra 2 (de 1 a 12). |
| `/barra 2 filas 2` | En cuántas filas (o columnas, si es vertical). |
| `/barra 2 escala 1.2` | Tamaño de la barra 2. |
| `/barra 2 ocultar` | Ocultar o mostrar la barra 2 (sus teclas siguen andando). |
| `/barra 2 centrar` | Volver a la posición de inicio. |

Sin número, los comandos son para la barra 1. Si bajás la cantidad de barras, las que sobran se ocultan con su contenido y sus teclas guardados: vuelven si las volvés a activar.

## Barra de clase

Aparece sola, debajo de la barra 1, con un botón por grupo. Solo muestra los grupos de los que ya conocés algo, y siempre usa **el rango más alto que tengas**. Al aprender un hechizo o un rango nuevo, se actualiza.

- **Clic (o su tecla):** usa lo elegido en ese grupo.
- **Clic derecho:** elegir qué usa ese botón (por ejemplo, qué tótem de tierra). Fuera de combate.

| Clase | Botones |
|---|---|
| Chamán | Tótem de Tierra, Fuego, Agua y Aire, y **Todos**: pone los tótems elegidos, uno por pulsación. |
| Paladín | Aura, Sello, Bendición y Bendición superior. |
| Cazador | Aspecto, Picadura, Trampa y Mascota (aliviar, llamar, revivir...). |
| Mago | Armadura, Intelecto, Conjurar (agua, comida, gemas de maná) y Teletransporte (y portales). |
| Brujo | Demonio, Armadura, Piedra (de salud, de alma...) y Maldición. |
| Sacerdote | Entereza, Espíritu, Sombras (protección y Resguardo de miedo) y Fuego interno. |
| Druida | Marca (o Don) de lo Salvaje y Espinas. |
| Guerrero | Grito y Ira (Sed de sangre, Ira rabiosa). |
| Pícaro | Veneno para la mano principal y para la secundaria, con los que tengas en las bolsas. |

`/barra clase` la oculta o la muestra. Se configura como las otras con `clase` en vez del número: `/barra clase vertical`, `/barra clase escala 1.2`, `/barra clase tecla 1 F5`, `/barra clase centrar`. En el modo `/barra teclas` también le podés poner teclas pasando el mouse.

## Mover y bloquear

Cada barra tiene una **agarradera** celeste con su número (a la izquierda si es horizontal, arriba si es vertical): arrastrala para mover la barra. `/barra bloquear` fija todas las barras y oculta las agarraderas; vuelve a desbloquear con el mismo comando.

`/barra` solo muestra la ayuda.

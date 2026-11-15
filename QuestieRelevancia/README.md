# Questie Relevancia

Addon para **WoW Forever** y **WoW Classic Era** que ordena tus misiones por relevancia y prioridad, con un puntaje de **0 a 100**. Usa los datos de **Questie**: niveles, zonas, cadenas de misiones, recompensas, mazmorras y misiones de clase.

## Requisitos

- **Questie 12.9 o más nuevo**, con su base de datos **QuestieDB** (vienen juntos en el paquete oficial).

## Instalación

Copiá la carpeta `QuestieRelevancia` a `World of Warcraft\<versión>\Interface\AddOns\`, al lado de `Questie` y `QuestieDB`. Las versiones son `_forever_` y `_classic_era_`.

Al entrar al juego aparece en el chat **"Questie Relevancia: listo"** y un **botón con un libro en el minimapa**.

## Dónde se ve

- **En la barra lateral de Questie** (el seguimiento de misiones): delante de cada misión van su puntaje, sus íconos y, si mejora tu equipo, cuántos niveles de objeto (por ejemplo `87 📖 ⚔ +6`). La barra también se ordena por relevancia; si Questie la agrupa por zona, ordena adentro de cada zona.
- **En la ventana:** clic en el botón del minimapa, o **/qr** (también **/qrel** o **/relevancia**).

## Pestañas

| Pestaña | Qué muestra |
|---|---|
| **Mis misiones** | Las que tomaste, ordenadas por puntaje. Las listas para entregar van arriba. |
| **Recomendadas** | Las que podés tomar en tu zona, de tu facción y de un nivel adecuado. Las de clase, siempre. |
| **El resto** | Las demás misiones disponibles. |
| **Por nivel** | Todas las misiones que tu personaje puede ver, agrupadas por nivel: "Mi nivel" (tu nivel −4 a +2), tramos de 10 niveles o todas. Botones para mostrar u ocultar las ya hechas, las bloqueadas y las de relleno. |
| **Mazmorra** | Las mazmorras y bandas con misiones para tu personaje. Elegís una y te muestra qué preparar afuera y qué hacer adentro, en orden. |
| **Equipo** | Ranura por ranura, lo que llevás contra el mejor premio de misión que tu clase puede usar a tu nivel, con un veredicto (de "Equipo al día" a "Muy desactualizado") y las tres mejoras más grandes. |

**Clic derecho en una misión: catálogo de la cadena.** Muestra todos los pasos de la cadena (hechos, en curso y pendientes), qué da cada paso (XP, objetos y reputación) y el total de lo que te falta conseguir.

### Íconos

| Ícono | Significa |
|---|---|
| Libro | Historia: es parte de una cadena de 3 o más misiones |
| **XP** | Da mucha experiencia para tu nivel |
| Monedas | Buena recompensa en oro (o un objeto que se vende bien) |
| Espada | Mejora tu equipo (con `+N`: niveles de objeto) |
| Calavera | Mazmorra o banda |
| Ícono de tu clase | Misión de clase |
| Signo **?** de Questie | Lista para entregar |
| *relleno* | Misión suelta, sin cadena ni recompensa especial |

## Cómo se calcula el puntaje

Siete criterios: **XP** a tu nivel, **oro**, **mejora de equipo** (por nivel de objeto y tipo de armadura o arma de tu clase), **historia** (largo de la cadena), **cadena** (cuánto valen los pasos que siguen: si una cadena termina en algo bueno, sus primeras misiones suben), **clase** y **mazmorra**.

Después se ajusta por prioridad:

- Las misiones muy por encima de tu nivel tienden a cero.
- Las grises casi no valen, salvo las de clase, mazmorra o las que desbloquean algo, que valen la mitad.
- Las de tu zona suben y las listas para entregar van primero.
- Por encima de 70 el puntaje se comprime, para que las mejores no queden empatadas.

## Perfiles y comandos

El botón **Perfil** cambia qué se prioriza: **Equilibrado**, **Subir rápido**, **Equipo**, **Historia** u **Oro**.

| Comando | Qué hace |
|---|---|
| `/qr nivel`, `/qr mazmorra`, `/qr equipo` | Abre esa pestaña |
| `/qr seguimiento` | Puntaje e íconos en la barra de Questie: sí o no (también con clic derecho en el botón del minimapa) |
| `/qr orden` | Ordenar la barra de Questie por relevancia: sí o no |
| `/qr minimapa` | Muestra u oculta el botón del minimapa |
| `/qr perfil historia` | Elige un perfil |
| `/qr peso equipo 1.5` | Ajusta un criterio, de 0 (no importa) a 2 (lo más importante) |
| `/qr pesos` / `/qr reiniciar` | Muestra los pesos / vuelve a los del perfil |

Si otro addon también usa `/qr`, al entrar te avisa: usá `/qrel` o el botón del minimapa.

## Limitaciones

- El oro de recompensa solo se conoce de las misiones que ya tomaste, y solo en Forever. Para las demás se usa lo que vale vender el objeto de recompensa.
- La mejora de equipo se mide por nivel de objeto y tipo de armadura o arma, no por estadísticas.
- El "equipo ideal" son los premios de misión: no cuenta botín de mazmorras, vendedores ni la subasta. Es un piso realista, no lo máximo posible.
- Las misiones disponibles son las que Questie muestra en el mapa.
- Las misiones nuevas de Forever que todavía no están en la base de datos de Questie no aparecen.

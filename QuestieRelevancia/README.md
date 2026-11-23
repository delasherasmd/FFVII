# Questie Relevancia

Addon para **WoW Forever** y **WoW Classic Era** que ordena tus misiones por relevancia y prioridad, con un puntaje de **0 a 100**. Usa los datos de **Questie**: niveles, zonas, cadenas de misiones, recompensas, mazmorras y misiones de clase.

También **evalúa tu equipo por estadísticas**: detecta tu rama de talentos, te deja elegir rol (DPS, tanque o sanador), compara lo que llevás con la media de tu nivel y con lo mejor que podés conseguir, y te recomienda los objetos **infaltables** con cómo conseguirlos.

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
| **Estadísticas** | Tu equipo evaluado por las estadísticas que importan para tu rama de talentos y rol. Ver abajo. |

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

## Estadísticas

**Arriba**, tres botones con las ramas de tu clase y los puntos que tenés en cada una: la detectada (la de más puntos) queda marcada. Al lado, los roles que puede cubrir tu clase (**DPS**, **Tanque**, **Sanador**). Podés cambiar los dos a mano, por ejemplo para probar un druida feral tanque o felino; **Auto** vuelve a lo detectado.

Debajo, el resumen: **qué porcentaje de la media de tu nivel** tiene tu equipo y **qué porcentaje de lo mejor que podés conseguir**. En nivel 60 también contra lo mejor con bandas.

La lista tiene tres partes:

| Parte | Qué muestra |
|---|---|
| **Infaltables** | Hasta 10 objetos que más suman para tu rama y rol, primero los más fáciles de conseguir. Cada uno dice cuánto mejora tu equipo y **cómo conseguirlo**: misión (normal, de mazmorra o de banda), jefe y probabilidad de botín (con la mazmorra), vendedor, profesión y nivel, botín del mundo (subasta) o cofre. Clic: el lugar en el mapa. Mayús+clic: enlazarlo en el chat. |
| **Por ranura** | Lo que llevás en cada ranura, en porcentaje de la media de tu nivel (verde: arriba de la media; rojo: muy abajo), y lo mejor que podés conseguir para esa ranura. El cuadro de ayuda muestra los números y lo mejor con bandas. |
| **Estadísticas clave** | Las que más pesan para tu rama y rol, cuánto suma tu equipo de cada una y cuánto suma un equipo medio de tu nivel. |

Cómo se calcula:

- Cada estadística tiene un **peso** según clase, rama y rol (por ejemplo, un guerrero Furia valora fuerza, crítico y golpe; un sacerdote Sagrado, sanación, espíritu y maná cada 5 segundos). El **poder** de un objeto es la suma de sus estadísticas por sus pesos, incluidos los efectos "al equipar" (golpe, crítico, daño con hechizos, sanación, defensa...).
- **La media** es el poder típico de los objetos verdes y azules de tu nivel (de hasta 5 niveles menos) que tu clase puede usar.
- **Lo mejor** es el objeto de más poder que podés usar a tu nivel, sin bandas y sin rangos de JcJ.
- Un **infaltable** se ordena por lo que suma dividido por lo que cuesta conseguirlo: una misión cuesta poco; un jefe con 10% de probabilidad, varias vueltas a la mazmorra; una banda, mucho.
- Los objetos con **sufijo al azar** ("del Mono", "del Oso") se calculan con el mejor sufijo para tu rama (llevan una `~`).
- Las estadísticas de los objetos salen de la base de datos abierta de **CMaNGOS Classic**; las misiones, PNJ y zonas, de Questie. Un objeto que la base no conoce (por ejemplo, nuevo de Forever) se evalúa con los datos del juego.

## Perfiles y comandos

El botón **Perfil** cambia qué se prioriza: **Equilibrado**, **Subir rápido**, **Equipo**, **Historia** u **Oro**.

| Comando | Qué hace |
|---|---|
| `/qr nivel`, `/qr mazmorra`, `/qr equipo`, `/qr estadisticas` | Abre esa pestaña |
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
- **Estadísticas:** los pesos son aproximados, de la comunidad de Classic. No cuentan los efectos de uso de los abalorios, los efectos con probabilidad al golpear, las bonificaciones de conjunto ni el tope de golpe. La probabilidad de botín sale de la base del servidor y puede diferir un poco del juego.

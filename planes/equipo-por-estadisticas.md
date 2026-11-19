# Plan: evaluación de equipo por estadísticas (para el lunes 23/11)

## Qué tiene que hacer

1. Detecta en qué **rama de talentos** estás, según dónde pusiste más puntos. Por ejemplo, un guerrero puede estar en Armas, Furia o Protección. Lo muestra arriba de todo y lo podés cambiar a mano si estás probando otra build.
2. A partir de la rama propone tu **rol**: DPS, tanque o sanador. También lo podés cambiar, porque hay ramas que sirven para más de uno (un druida Feral puede ser tanque o DPS).
3. Mide **qué tan arriba o abajo de la media** está tu equipo, según las **estadísticas clave** de tu clase, rama de talentos, rol y nivel.
4. Lo compara también con el **mejor equipo posible** para tu nivel (el "techo").
5. Recomienda los objetos **infaltables**: los que más mejoran tu personaje en esa rama y rol, ordenados por cuánto suman y qué tan fácil es conseguirlos, con **cómo conseguirlos** (misión, jefe de mazmorra, vendedor, profesión o subasta) y dónde.
6. Funciona en **WoW Forever** y **WoW Classic Era**.

## Cómo se calcula

- **Rama de talentos.** Se lee cuántos puntos tenés en cada una de las tres ramas de tu clase. La que tiene más puntos es tu rama; si dos están parejas, se avisa ("híbrido") y se usa la que elijas.
- **Pesos por clase, rama y rol.** Cada estadística vale distinto según la rama y el rol. Por ejemplo, un guerrero Protección valora aguante, armadura y defensa; un guerrero Furia, fuerza, golpe crítico e índice de golpe; un sacerdote Sagrado, intelecto, espíritu, sanación y maná cada 5 segundos. Con eso, cada objeto tiene un **puntaje de poder**: la suma de sus estadísticas por sus pesos.
- **La media.** Para cada ranura, el poder típico de los objetos comunes de tu nivel (calidad verde o azul, nivel de objeto cercano al tuyo). Se muestra como porcentaje arriba o abajo de esa media, ranura por ranura y en total.
- **El techo.** El mejor objeto de cada ranura que se puede conseguir hasta tu nivel. En nivel máximo, la lista de "pre-banda".
- **Infaltables.** Los objetos con mayor ganancia sobre lo que llevás, dividida por un costo de conseguirlos: una misión cuesta poco; un jefe con 10% de probabilidad, más.

## De dónde salen los datos

- **En el juego:** tus puntos de talento por rama, las estadísticas de lo que llevás puesto y de los objetos que el cliente ya conoce (`C_Item.GetItemStats`). Sirve para tu equipo actual.
- **Base propia de objetos (lo principal):** se genera fuera del juego a partir de la base de datos abierta de un servidor de Classic (VMaNGOS o CMaNGOS en GitHub). Trae estadísticas, nivel requerido, ranura, calidad y de dónde sale cada objeto: qué jefe lo suelta y con qué probabilidad, qué misión lo da, qué vendedor lo vende y qué receta lo fabrica. Se guarda comprimida dentro del addon.
- **Questie:** misiones, NPC y coordenadas para señalar en el mapa dónde se consigue cada cosa. Ya lo usamos en Questie Relevancia.
- **Forever:** usa el contenido de Classic, pero puede tener objetos o cambios nuevos. Lo que no esté en la base propia se completa con los datos del juego, y se marca como "dato del juego".

## Cómo se vería

Una pestaña nueva **"Estadísticas"** dentro de Questie Relevancia, para reutilizar la ventana, los íconos, el minimapa y los datos de Questie. Si preferís un addon aparte, se puede separar.

- **Arriba:** tu rama de talentos detectada (con los puntos, por ejemplo "Furia 31 / Armas 20 / Protección 0"), el selector de rol (DPS / Tanque / Sanador) y un resumen, por ejemplo "Tu equipo: 87% de la media de tu nivel, 54% del techo".
- **Por ranura:** lo que llevás, su poder, la media, el techo y la diferencia, en colores.
- **Infaltables:** los 5 a 10 mejores objetos para conseguir, cada uno con su ganancia y cómo conseguirlo ("Jefe X en la mazmorra Y, 12%", o "Misión Z en zona W", con clic para verlo en el mapa).
- **Estadísticas clave:** cuáles importan para tu rama y rol y cuánto tenés de cada una comparado con la media.

## Pasos para el lunes

1. Buscar y bajar la base de datos de objetos (VMaNGOS o CMaNGOS) y armar el script que genera la tabla comprimida para el addon.
2. Detectar la rama de talentos en los dos clientes. Classic Era y Forever pueden usar funciones distintas para leer los talentos: hay que verificarlo en el código de Blizzard de cada uno.
3. Definir los pesos por clase, rama y rol (9 clases × 3 ramas, más los roles alternativos como Feral tanque o DPS), con valores de la comunidad de Classic.
4. Calcular la media y el techo por ranura y nivel, y el puntaje de los infaltables.
5. Armar la pestaña con la rama detectada, el selector de rol, la tabla por ranura y la lista de infaltables.
6. Probarlo fuera del juego con datos reales y varios personajes (como Questie Relevancia), empaquetarlo y pasarte el comando de instalación.

## Para decidir antes de empezar

1. ¿Pestaña dentro de Questie Relevancia (recomendado) o addon aparte?
2. ¿Incluyo como fuente los objetos de profesiones y de la subasta, o solo misiones, mazmorras y vendedores?
3. ¿Qué personaje uso primero para calibrar? (clase, rama de talentos, nivel y rol que más jugás)
4. ¿En nivel máximo comparo con la lista de "pre-banda" o también con objetos de bandas?

## Límites conocidos

- Las estadísticas "ocultas" de algunos objetos (efectos al equipar, por ejemplo "aumenta el golpe crítico 1%") se pueden contar, pero los pesos de esos efectos son aproximados.
- La probabilidad de botín sale de la base del servidor y puede diferir un poco del juego real.
- Los objetos nuevos de Forever que no estén en la base pública se evalúan solo cuando el juego ya los conoce.
- Si Forever cambió talentos de alguna clase, los pesos de esa rama hay que revisarlos a mano.

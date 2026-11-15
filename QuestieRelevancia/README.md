# Questie Relevancia

Addon para **WoW Forever** (también carga en Classic Era) que ordena tus misiones por relevancia y prioridad, con un puntaje de **0 a 100**. Usa los datos de **Questie**: niveles, zonas, cadenas de misiones, recompensas y misiones de clase.

## Requisitos

- **Questie 12.9 o más nuevo**, con su base de datos **QuestieDB** (vienen juntos en el paquete oficial).

## Instalación

Copiá la carpeta `QuestieRelevancia` a `World of Warcraft\<versión>\Interface\AddOns\`, al lado de `Questie` y `QuestieDB`.

## Uso

Escribí **/qr** (o **/relevancia**) para abrir la ventana. También hay un atajo de teclado en *Opciones → Atajos de teclado → AddOns → Questie Relevancia*.

La ventana tiene tres pestañas:

| Pestaña | Qué muestra |
|---|---|
| **Mis misiones** | Las que ya tomaste, ordenadas por puntaje. Las que están listas para entregar quedan arriba de todo. |
| **Recomendadas** | Las que podés tomar en tu zona actual, de tu facción y de un nivel adecuado (ni grises ni rojas). Las misiones de clase aparecen siempre. |
| **El resto** | Las demás misiones disponibles, de otras zonas o niveles. |

Y filtros para ver un solo tipo: **Historia, XP, Oro, Equipo, Mazmorra, Clase y Relleno**.

### Íconos

| Ícono | Significa |
|---|---|
| Libro | Historia: es parte de una cadena de 3 o más misiones |
| **XP** | Da mucha experiencia para tu nivel |
| Monedas | Buena recompensa en oro (o un objeto que se vende bien) |
| Espada | Mejora tu equipo |
| Calavera | Mazmorra o banda |
| Ícono de tu clase | Misión de clase |
| Signo **?** de Questie | Lista para entregar |
| *relleno* | Misión suelta, sin cadena ni recompensa especial |

Al pasar el mouse por una misión se ve por qué tiene ese puntaje, en qué paso de la cadena está y cómo sigue. Al hacer clic se abre en el registro de misiones o, si todavía no la tomaste, su zona en el mapa.

## Cómo se calcula el puntaje

Cada misión se evalúa en siete criterios:

- **XP:** la experiencia que te da a tu nivel.
- **Oro:** el oro de recompensa, más lo que vale vender el objeto de recompensa.
- **Equipo:** si algún objeto de recompensa es mejor que lo que tenés puesto (por nivel de objeto) y lo puede usar tu clase.
- **Historia:** qué tan larga es su cadena de misiones.
- **Cadena:** cuánto valen los pasos que siguen. Si una cadena termina en algo bueno, sus primeras misiones suben aunque den poco: así no te salteás el comienzo de una cadena que vale la pena.
- **Clase:** misiones de tu clase.
- **Mazmorra:** misiones de mazmorra o de banda.

Después se ajusta por prioridad. Bajan las misiones grises (casi no dan nada) y las rojas (todavía muy difíciles). Suben las del registro que son de la zona donde estás. Las listas para entregar van primero.

## Perfiles

El botón **Perfil** de la ventana cambia qué se prioriza: **Equilibrado**, **Subir rápido**, **Equipo**, **Historia** u **Oro**.

| Comando | Qué hace |
|---|---|
| `/qr perfil historia` | Elige un perfil |
| `/qr peso equipo 1.5` | Ajusta un criterio, de 0 (no importa) a 2 (lo más importante) |
| `/qr pesos` | Muestra los pesos actuales |
| `/qr reiniciar` | Vuelve a los pesos del perfil |

## Limitaciones

- El oro de recompensa solo se conoce de las misiones que ya tomaste, y solo en Forever. Para las demás se usa lo que vale vender el objeto de recompensa.
- La mejora de equipo se mide por nivel de objeto y tipo de armadura o arma, no por estadísticas.
- Las misiones disponibles son las que Questie muestra en el mapa: si en Questie ocultaste, por ejemplo, las de mazmorra, acá tampoco aparecen.
- Las misiones nuevas de Forever que todavía no están en la base de datos de Questie no aparecen.

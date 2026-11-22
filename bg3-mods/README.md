# Mods de Baldur's Gate 3

Dos mods independientes:

| Mod | Qué hace | Estado |
|---|---|---|
| `FourFromScratch` | Empezar con 4 personajes creados de cero (creador completo, todo desbloqueado), controlados por un solo jugador | Código escrito, **sin probar en el juego** |
| `MinotaurSatyr` | Razas jugables Minotauro y Sátiro | Reglas, textos y localización escritos. **Faltan los modelos y la integración visual** |

Herramientas en `tools/`:
- `gen_minotaur_satyr.py`: genera todos los archivos de texto del mod de razas. Si querés cambiar algo, se edita este script y se vuelve a correr: `python3 bg3-mods/tools/gen_minotaur_satyr.py`.
- `kitbash.py`: ensambla los modelos con Blender en modo script (sin interfaz) y renderiza una vista previa. Ya está probado con figuras simples.

## Lo que tenés que instalar en tu PC (Windows)

1. **BG3 Script Extender** (Norbyte). Lo necesita `FourFromScratch`.
2. **BG3 Mod Manager** (LaughingLeader), para activar los mods y ordenarlos.
3. **LSLib / ConverterApp** (Norbyte, en GitHub > Releases). Sirve para:
   - Extraer los modelos del juego: abrir `Models.pak` y exportar a **glTF (.glb)**.
   - Empaquetar cada mod en un `.pak`.
   - Convertir los modelos terminados de `.glb` a `.GR2`. Necesita el archivo `granny2.dll` que viene con tu instalación del juego, por eso se hace en tu PC.

Blender no hace falta en tu PC: lo corro yo en el servidor.

## FourFromScratch: cómo funciona

1. Al entrar al Nautiloide (`TUT_Avernus_C`) se crean 3 personajes junto al tuyo y se suman al grupo.
2. Para cada uno se abre el creador de personajes, de a uno por vez.
3. Comandos para la consola de Script Extender:
   - `!ffs_start`: fuerza el inicio si no se disparó solo.
   - `!ffs_cc`: vuelve a abrir el creador para tu personaje principal.

**Lo que hay que verificar en el juego:** las funciones de Osiris que abren el creador completo no están documentadas. El script prueba varias en orden (`StartCharacterCreation`, `StartRespecToTutorial`, `StartRespec`) y escribe en el log cuál funcionó.
- Si solo funciona `StartRespec`, la raza queda bloqueada y hay que buscar otra vía.
- En la primera prueba, mandame el log de la consola (líneas con `[FourFromScratch]`).

## MinotaurSatyr: reglas

Están basadas en *Monsters of the Multiverse*, que es la versión más moderna de ambas razas, aplicadas con el criterio del PHB 2024: la raza no da aumentos de característica, porque en BG3 el +2/+1 ya se asigna libremente.

**Minotauro** (Humanoide, mediano; en lo visual, humano grande con escala ~1.18)
- **Cuernos:** ataque de 1d6 + Fuerza, daño perforante.
- **Embestida Corneadora:** después de usar Correr, puede atacar con los cuernos como acción adicional.
- **Cuernos Martilladores:** después de acertar un ataque cuerpo a cuerpo, puede empujar 3 m al objetivo como acción adicional.
- **Memoria Laberíntica:** ventaja en las tiradas de Supervivencia.

**Sátiro** (Feérico, mediano, velocidad 10,5 m)
- **Topetazo:** ataque de 1d6 + Fuerza, daño contundente.
- **Resistencia Mágica:** ventaja en las salvaciones contra conjuros.
- **Saltos Alegres:** salto ×1,3.
- **Juerguista:** competencia en Interpretación, Persuasión e instrumentos.

### Pendiente (necesita los archivos del juego)

- [ ] En `Races.lsx`: copiar de la raza base (Humano o Elfo) los tags, colores de ojos, piel y pelo, y los visuales. Agregar el tag `FEY` al sátiro.
- [ ] `CharacterCreationPresets.lsx`: cuerpos masculino y femenino de cada raza (hacen falta los RootTemplate del juego).
- [ ] Convertir `palettes.json` a LSX: pelaje, cuernos con base y punta, marcas.
- [ ] Modelos: extraer en tu PC, ensamblar acá con `kitbash.py`, convertir a `.GR2` en tu PC.
- [ ] Verificar en el juego los nombres de los boosts marcados como dudosos: `JumpMaxDistanceMultiplier`, `IF(IsSpell())`, `Proficiency(MusicalInstrument)`.

### Modelos: qué extraer del juego

Desde `Models.pak` y `Shared.pak`, exportar como `.glb`:
- Cuerpo humano masculino y femenino, tipo "Strong" (BT2/BT4).
- Cuerpo elfo masculino y femenino.
- Cabeza y piernas del minotauro (el monstruo de la Infraoscuridad).
- Cuernos de tiflin, como referencia de cómo el juego maneja los cuernos.

Subilos a Google Drive o pasámelos como prefieras.

No se usan modelos de otros juegos (WoW, etc.) por derechos de autor. El estilo robusto se toma solo como referencia.

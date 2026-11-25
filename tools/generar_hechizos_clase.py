"""Genera BarraLibre/ClassSpells.lua: los tótems del chamán por elemento, con los números de cada rango.

Es lo único que la barra de clase necesita de la base: las demás clases usan la barra de la mascota
o la de posturas, que el juego ya sabe armar.

Uso:
    python3 tools/generar_hechizos_clase.py ClassicDB_1_12_1_zXXXX.sql[.gz] BarraLibre/ClassSpells.lua

Los hechizos se buscan por nombre (en inglés, como en la base de CMaNGOS Classic) entre los que enseñan
los entrenadores y sus rangos; en el juego se muestran con el nombre en tu idioma. Un nombre que termina
en * toma todos los hechizos que empiezan así (por ejemplo, las piedras de salud de cada rango).
"""
import gzip
import re
import sys
from collections import defaultdict
from pathlib import Path

SOURCE, OUTPUT = Path(sys.argv[1]), Path(sys.argv[2])

# Familia de hechizos de cada clase en la base (SpellFamilyName).
FAMILY = {"MAGE": 3, "WARRIOR": 4, "WARLOCK": 5, "PRIEST": 6, "DRUID": 7, "ROGUE": 8, "HUNTER": 9,
          "PALADIN": 10, "SHAMAN": 11}

# Grupos: clave, nombre en la barra, opciones (en orden de uso).
GROUPS = {
    "SHAMAN": [
        ("tierra", "Tierra", ["Strength of Earth Totem", "Stoneskin Totem", "Tremor Totem", "Earthbind Totem",
                              "Stoneclaw Totem"]),
        ("fuego", "Fuego", ["Searing Totem", "Flametongue Totem", "Magma Totem", "Fire Nova Totem",
                            "Frost Resistance Totem"]),
        ("agua", "Agua", ["Mana Spring Totem", "Healing Stream Totem", "Mana Tide Totem", "Poison Cleansing Totem",
                          "Disease Cleansing Totem", "Fire Resistance Totem"]),
        ("aire", "Aire", ["Windfury Totem", "Grace of Air Totem", "Grounding Totem", "Tranquil Air Totem",
                          "Nature Resistance Totem", "Windwall Totem", "Sentry Totem"]),
    ],
}
TOKEN = re.compile(r"'(?:[^'\\]|\\.)*'|NULL|-?[0-9.eE+-]+|[(),]")


def read(tables):
    opener = gzip.open if SOURCE.suffix == ".gz" else open
    columns, rows, current = {}, defaultdict(list), None
    with opener(SOURCE, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("CREATE TABLE `"):
                current = line.split("`")[1]
                if current in tables:
                    columns[current] = []
                continue
            if current in columns and line.startswith("  `"):
                columns[current].append(line.split("`")[1])
                continue
            if line.startswith("INSERT INTO `") and line.split("`")[1] in tables:
                table = line.split("`")[1]
                cols, row, depth = columns[table], [], 0
                for m in TOKEN.finditer(line, line.index(" VALUES ") + 8):
                    t = m.group(0)
                    if t == "(":
                        depth, row = 1, []
                    elif t == ")":
                        depth = 0
                        rows[table].append(dict(zip(cols, row)))
                    elif t != "," and depth:
                        if t == "NULL":
                            row.append(None)
                        elif t[0] == "'":
                            row.append(t[1:-1].replace("\\'", "'"))
                        else:
                            row.append(int(t) if re.fullmatch(r"-?\d+", t) else float(t))
    return rows


DB = read({"spell_template", "npc_trainer", "npc_trainer_template", "item_template"})
spells = {s["Id"]: s for s in DB["spell_template"]}

# Lo que enseñan los entrenadores (el hechizo que enseña -> el aprendido).
taught = set()
for r in DB["npc_trainer"] + DB["npc_trainer_template"]:
    s = spells.get(r["spell"])
    if not s:
        continue
    learned = [s[f"EffectTriggerSpell{n}"] for n in (1, 2, 3) if s[f"Effect{n}"] == 36]
    taught.update(learned or [r["spell"]])


def rank_number(s):
    m = re.search(r"(\d+)", s.get("Rank1") or "")
    return int(m.group(1)) if m else 0


def family_ids(class_file, name):
    family = FAMILY[class_file]
    prefix = name.endswith("*")
    base = name.rstrip("*")
    found = []
    for s in spells.values():
        spell_name = s["SpellName"] or ""
        if prefix and spell_name.startswith(base) and (s["SpellFamilyName"] == family or s["Id"] in taught):
            found.append(s)
        elif not prefix and spell_name == base and s["SpellFamilyName"] in (family, 0):
            # Puede colarse algún hechizo que no es del jugador (el efecto de un tótem, por ejemplo):
            # en el juego solo se usan los rangos que el personaje conoce, así que no molesta.
            found.append(s)
    # Orden: por nivel del hechizo y rango, del más bajo al más alto.
    found.sort(key=lambda s: (s["SpellLevel"] or 0, rank_number(s), s["Id"]))
    return [s["Id"] for s in found]


lines = ["-- Generado por tools/generar_hechizos_clase.py a partir de la base de CMaNGOS Classic. No editar a mano.",
         "-- [clase] = { {clave, nombre, { {nombre en inglés, {rangos de menor a mayor}}, ... }}, ... }",
         "BarraLibreClassSpells = {"]
missing = []
for class_file, groups in GROUPS.items():
    lines.append(f"\t{class_file} = {{")
    for key, label, names in groups:
        options = []
        for name in names:
            ids = family_ids(class_file, name)
            if ids:
                options.append(f'{{ "{name.rstrip("*")}", {{ {", ".join(map(str, ids))} }} }}')
            else:
                missing.append(f"{class_file}: {name}")
        lines.append(f'\t\t{{ "{key}", "{label}", {{ {", ".join(options)} }} }},')
    lines.append("\t},")
lines.append("}")
OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("Escrito", OUTPUT)
print("No encontrados:", missing or "ninguno")

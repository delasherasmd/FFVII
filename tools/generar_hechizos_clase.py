"""Genera BarraLibre/ClassSpells.lua: los grupos de la barra de clase con los números de cada rango.

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

# Grupos por clase: clave, nombre en la barra, ícono si no hay ninguno elegido, opciones (en orden de uso).
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
    "PALADIN": [
        ("aura", "Aura", ["Devotion Aura", "Retribution Aura", "Concentration Aura", "Sanctity Aura",
                          "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura"]),
        ("sello", "Sello", ["Seal of Righteousness", "Seal of Command", "Seal of the Crusader", "Seal of Wisdom",
                            "Seal of Light", "Seal of Justice"]),
        ("bendicion", "Bendición", ["Blessing of Might", "Blessing of Wisdom", "Blessing of Kings",
                                    "Blessing of Salvation", "Blessing of Light", "Blessing of Sanctuary",
                                    "Blessing of Freedom", "Blessing of Protection", "Blessing of Sacrifice"]),
        ("superior", "Bendición superior", ["Greater Blessing of Might", "Greater Blessing of Wisdom",
                                            "Greater Blessing of Kings", "Greater Blessing of Salvation",
                                            "Greater Blessing of Light", "Greater Blessing of Sanctuary"]),
    ],
    "HUNTER": [
        ("aspecto", "Aspecto", ["Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Cheetah",
                                "Aspect of the Pack", "Aspect of the Wild", "Aspect of the Beast"]),
        ("picadura", "Picadura", ["Serpent Sting", "Viper Sting", "Scorpid Sting", "Wyvern Sting"]),
        ("trampa", "Trampa", ["Freezing Trap", "Immolation Trap", "Frost Trap", "Explosive Trap"]),
        ("mascota", "Mascota", ["Mend Pet", "Call Pet", "Revive Pet", "Dismiss Pet", "Feed Pet"]),
    ],
    "MAGE": [
        ("armadura", "Armadura", ["Mage Armor", "Ice Armor", "Frost Armor"]),
        ("intelecto", "Intelecto", ["Arcane Intellect", "Arcane Brilliance", "Amplify Magic", "Dampen Magic"]),
        ("conjurar", "Conjurar", ["Conjure Water", "Conjure Food", "Conjure Mana Ruby", "Conjure Mana Citrine",
                                  "Conjure Mana Jade", "Conjure Mana Agate"]),
        ("viaje", "Teletransporte", ["Teleport: Stormwind", "Teleport: Ironforge", "Teleport: Darnassus",
                                     "Teleport: Orgrimmar", "Teleport: Undercity", "Teleport: Thunder Bluff",
                                     "Portal: Stormwind", "Portal: Ironforge", "Portal: Darnassus",
                                     "Portal: Orgrimmar", "Portal: Undercity", "Portal: Thunder Bluff"]),
    ],
    "WARLOCK": [
        ("demonio", "Demonio", ["Summon Imp", "Summon Voidwalker", "Summon Succubus", "Summon Felhunter"]),
        ("armadura", "Armadura", ["Demon Armor", "Demon Skin"]),
        ("piedra", "Piedra", ["Create Healthstone*", "Create Soulstone*", "Create Spellstone*",
                              "Create Firestone*"]),
        ("maldicion", "Maldición", ["Curse of Agony", "Curse of the Elements", "Curse of Shadow",
                                    "Curse of Recklessness", "Curse of Weakness", "Curse of Tongues",
                                    "Curse of Exhaustion", "Curse of Doom"]),
    ],
    "PRIEST": [
        ("entereza", "Entereza", ["Power Word: Fortitude", "Prayer of Fortitude"]),
        ("espiritu", "Espíritu", ["Divine Spirit", "Prayer of Spirit"]),
        ("sombras", "Sombras", ["Shadow Protection", "Prayer of Shadow Protection", "Fear Ward"]),
        ("fuego", "Fuego interno", ["Inner Fire"]),
    ],
    "DRUID": [
        ("marca", "Marca", ["Mark of the Wild", "Gift of the Wild"]),
        ("espinas", "Espinas", ["Thorns", "Omen of Clarity"]),
    ],
    "WARRIOR": [
        ("grito", "Grito", ["Battle Shout", "Demoralizing Shout", "Challenging Shout"]),
        ("ira", "Ira", ["Bloodrage", "Berserker Rage"]),
    ],
}
# Pícaro: venenos (objetos), uno por arma.
POISONS = ["Instant Poison", "Deadly Poison", "Crippling Poison", "Mind-numbing Poison", "Wound Poison"]

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
# Venenos: objetos, de menor a mayor nivel.
poison_items = defaultdict(list)
for r in DB["item_template"]:
    for base in POISONS:
        if r["class"] == 0 and re.fullmatch(re.escape(base) + r"( [IVX]+)?", r["name"] or ""):
            poison_items[base].append((r["RequiredLevel"], r["entry"]))
options = []
for base in POISONS:
    ids = [entry for _, entry in sorted(poison_items[base])]
    if ids:
        options.append(f'{{ "{base}", {{ {", ".join(map(str, ids))} }} }}')
    else:
        missing.append(f"ROGUE: {base}")
poison_list = ", ".join(options)
lines.append("\tROGUE = {")
lines.append(f'\t\t{{ "veneno1", "Veneno: mano principal", {{ {poison_list} }}, items = true, slot = 16 }},')
lines.append(f'\t\t{{ "veneno2", "Veneno: mano secundaria", {{ {poison_list} }}, items = true, slot = 17 }},')
lines.append("\t},")
lines.append("}")
OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("Escrito", OUTPUT)
print("No encontrados:", missing or "ninguno")

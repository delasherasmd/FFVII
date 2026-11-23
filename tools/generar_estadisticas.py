"""Genera QuestieRelevancia/StatsData.lua a partir de la base de datos abierta de CMaNGOS Classic.

Uso:
    python3 tools/generar_estadisticas.py ClassicDB_1_12_1_zXXXX.sql[.gz] QuestieRelevancia/StatsData.lua [classicNpcDB.lua]

El tercer archivo (opcional) es la base de PNJ de Questie (github.com/Questie/questiedb, data/Classic):
sirve para ubicar a los jefes que aparecen invocados (Ragnaros, Nefarian, C'Thun...). Necesita lupa.

La base sale de https://github.com/cmangos/classic-db (Full_DB). Del volcado se toman:
- item_template: estadísticas, ranura, calidad, niveles y clases de cada objeto equipable;
- spell_template: lo que hacen los efectos "al equipar" (golpe, crítico, daño con hechizos...);
- creature_loot_template / reference_loot_template / creature_template / creature: qué criatura
  suelta cada objeto, con qué probabilidad y en qué mazmorra;
- npc_vendor(+_template), quest_template, npc_trainer(+_template), gameobject_loot_template,
  item_loot_template: vendedores, misiones, recetas y cofres.

Cada objeto queda en una cadena compacta que el addon decodifica cuando la necesita.
"""
import gzip
import re
import sys
from collections import defaultdict
from pathlib import Path

SOURCE, OUTPUT = Path(sys.argv[1]), Path(sys.argv[2])
NPC_DB = Path(sys.argv[3]) if len(sys.argv) > 3 else None

TABLES = {
    "item_template", "spell_template", "creature_loot_template", "reference_loot_template",
    "creature_template", "creature", "npc_vendor", "npc_vendor_template", "creature_template_extra",
    "quest_template", "npc_trainer", "npc_trainer_template", "gameobject_loot_template",
    "gameobject_template", "gameobject", "item_loot_template",
}
# Columnas que hacen falta de cada tabla (el resto se descarta al leer, para ahorrar memoria).
KEEP = {
    "creature_template": {"Entry", "Name", "MinLevel", "MaxLevel", "Rank", "LootId", "VendorTemplateId",
                          "TrainerTemplateId"},
    "creature": {"id", "map"},
    "gameobject": {"id", "map"},
    "gameobject_template": {"entry", "type", "name", "data1"},
    "quest_template": {"entry", "MinLevel", "QuestLevel", "RequiredClasses", "RequiredRaces", "Title", "Type",
                       "PrevQuestId", "NextQuestId", "NextQuestInChain", "RequiredMinRepFaction",
                       "ZoneOrSort", "ReqItemId1", "ReqItemId2", "ReqItemId3", "ReqItemId4",
                       "RewChoiceItemId1", "RewChoiceItemId2", "RewChoiceItemId3", "RewChoiceItemId4",
                       "RewChoiceItemId5", "RewChoiceItemId6", "RewItemId1", "RewItemId2", "RewItemId3",
                       "RewItemId4"},
}

TOKEN = re.compile(r"'(?:[^'\\]|\\.)*'|NULL|-?[0-9.eE+-]+|[(),]")


def read_dump():
    opener = gzip.open if SOURCE.suffix == ".gz" else open
    columns, rows = {}, defaultdict(list)
    current = None
    with opener(SOURCE, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("CREATE TABLE `"):
                current = line.split("`")[1]
                if current in TABLES:
                    columns[current] = []
                continue
            if current in columns and line.startswith("  `"):
                name = line.split("`")[1]
                if name not in columns[current]:
                    columns[current].append(name)
                continue
            if line.startswith("INSERT INTO `"):
                table = line.split("`")[1]
                if table not in TABLES:
                    continue
                cols = columns[table]
                keep = KEEP.get(table)
                index = [i for i, c in enumerate(cols) if keep is None or c in keep]
                names = [cols[i] for i in index]
                start = line.index(" VALUES ") + 8
                row, depth = [], 0
                for m in TOKEN.finditer(line, start):
                    t = m.group(0)
                    if t == "(":
                        depth += 1
                        row = []
                    elif t == ")":
                        depth -= 1
                        values = [row[i] if i < len(row) else None for i in index]
                        rows[table].append(dict(zip(names, values)))
                    elif t == ",":
                        continue
                    elif depth:
                        if t == "NULL":
                            row.append(None)
                        elif t[0] == "'":
                            row.append(t[1:-1].replace("\\'", "'").replace('\\"', '"').replace("\\\\", "\\"))
                        else:
                            row.append(float(t) if ("." in t or "e" in t.lower()) and not t.lstrip("-").isdigit() else int(t))
    return rows


def num(v):
    return v if isinstance(v, (int, float)) else 0


print("Leyendo", SOURCE)
DB = read_dump()
for t in sorted(TABLES):
    print(f"  {t}: {len(DB.get(t, []))}")

# --------------------------------------------------------------------------------------------
# Hechizos "al equipar"
# --------------------------------------------------------------------------------------------
SPELLS = {r["Id"]: r for r in DB["spell_template"]}

SCHOOLS = {2: "Ho", 4: "Fi", 8: "Na", 16: "Fr", 32: "Sh", 64: "Ar"}
STAT_FROM_MISC = {0: "S", 1: "A", 2: "T", 3: "I", 4: "P"}
WEAPON_SKILLS = {43, 44, 45, 46, 54, 55, 160, 172, 173, 226, 229, 136, 473}


def spell_effects(spell_id, out, unknown):
    """Suma a `out` lo que aporta un hechizo de "al equipar"."""
    spell = SPELLS.get(spell_id)
    if not spell:
        return
    for n in (1, 2, 3):
        effect = spell[f"Effect{n}"]
        if effect != 6:  # APPLY_AURA
            continue
        aura = spell[f"EffectApplyAuraName{n}"]
        value = spell[f"EffectBasePoints{n}"] + spell[f"EffectBaseDice{n}"]
        misc = spell[f"EffectMiscValue{n}"]
        if aura == 13:  # daño de hechizos
            mask = misc & 126
            if mask == 126:
                out["sp"] += value
            elif mask:
                for bit, code in SCHOOLS.items():
                    if mask & bit:
                        out["sp" + code] += value
        elif aura == 135:
            out["heal"] += value
        elif aura == 54:
            out["hit"] += value
        elif aura == 55:
            out["shit"] += value
        elif aura == 52:
            out["crit"] += value
        elif aura == 57:
            out["scrit"] += value
        elif aura == 71:
            if (misc & 126) == 126 or misc == 0:
                out["scrit"] += value
            else:
                for bit, code in SCHOOLS.items():
                    if misc & bit:
                        out["scrit" + code] += value
        elif aura == 99:
            out["ap"] += value
        elif aura == 124:
            out["rap"] += value
        elif aura == 85 and misc == 0:
            out["mp5"] += value
        elif aura == 84:
            out["hp5"] += value
        elif aura == 30:
            if misc == 95:
                out["def"] += value
            elif misc in WEAPON_SKILLS:
                out["ws"] += value
        elif aura == 49:
            out["dodge"] += value
        elif aura == 47:
            out["parry"] += value
        elif aura == 51:
            out["block"] += value
        elif aura == 158:
            out["B"] += value
        elif aura == 22 and misc & 1:
            out["R"] += value
        elif aura == 29:
            if misc == -1:
                for code in STAT_FROM_MISC.values():
                    out[code] += value
            elif misc in STAT_FROM_MISC:
                out[STAT_FROM_MISC[misc]] += value
        elif aura == 34:
            out["hp"] += value
        elif aura == 123:
            out["pen"] += value
        else:
            unknown[aura] += 1


# --------------------------------------------------------------------------------------------
# Objetos equipables
# --------------------------------------------------------------------------------------------
SKIP_INVENTORY = {0, 4, 18, 19, 24, 27}
ITEM_STAT = {3: "A", 4: "S", 5: "I", 6: "P", 7: "T", 1: "hp", 0: "mana"}
BAD_NAME = re.compile(r"^(Monster -|TEST|Test |Deprecated|\[PH\]|QA|OLD|Unused|zzOLD|Dummy)|\bDEBUG\b", re.I)

items = {}
unknown_auras = defaultdict(int)
for r in DB["item_template"]:
    inv = r["InventoryType"]
    if inv in SKIP_INVENTORY or r["Quality"] in (0, 6, 7) or r["Quality"] > 5:
        continue
    if r["class"] not in (2, 4):  # armas y armaduras
        continue
    if BAD_NAME.search(r["name"] or ""):
        continue
    if r["Duration"]:
        continue  # objetos temporales (duran un rato y desaparecen)
    stats = defaultdict(int)
    for n in range(1, 11):
        t, v = r[f"stat_type{n}"], r[f"stat_value{n}"]
        if v and t in ITEM_STAT:
            stats[ITEM_STAT[t]] += v
    if r["armor"]:
        stats["R"] += r["armor"]
    if r["block"]:
        stats["B"] += r["block"]
    if r["class"] == 2 and r["delay"]:
        low = sum(num(r[f"dmg_min{n}"]) for n in range(1, 6))
        high = sum(num(r[f"dmg_max{n}"]) for n in range(1, 6))
        speed = r["delay"] / 1000
        if speed > 0 and high > 0:
            stats["D"] += round((low + high) / 2 / speed * 10)  # DPS x10
            stats["W"] += round(speed * 10)  # velocidad x10
    for n in range(1, 6):
        if r[f"spelltrigger_{n}"] == 1 and r[f"spellid_{n}"] > 0:
            spell_effects(r[f"spellid_{n}"], stats, unknown_auras)
        elif r[f"spelltrigger_{n}"] == 2 and r[f"spellid_{n}"] > 0:
            stats["proc"] = 1  # efecto con probabilidad al golpear
    items[r["entry"]] = {
        "inv": inv, "cls": r["class"], "sub": r["subclass"], "q": r["Quality"], "ilvl": r["ItemLevel"],
        "req": r["RequiredLevel"], "allow": r["AllowableClass"], "race": r["AllowableRace"],
        "bind": r["bonding"], "random": 1 if r["RandomProperty"] else 0, "set": r["itemset"],
        "stats": {k: v for k, v in stats.items() if v}, "name": r["name"],
        "skill": r["RequiredSkill"], "skillRank": r["RequiredSkillRank"],
        "honor": r["requiredhonorrank"], "repFaction": r["RequiredReputationFaction"],
        "repRank": r["RequiredReputationRank"],
    }
print("Objetos equipables:", len(items))
print("Auras al equipar sin interpretar (aura: cantidad):", dict(sorted(unknown_auras.items(), key=lambda x: -x[1])[:12]))

# --------------------------------------------------------------------------------------------
# Dónde está cada criatura y cada cofre
# --------------------------------------------------------------------------------------------
INSTANCES = {
    33, 34, 36, 43, 47, 48, 70, 90, 109, 129, 189, 209, 229, 230, 249, 289, 309, 329, 349, 389,
    409, 429, 469, 509, 531, 533,
}
RAIDS = {249, 309, 409, 469, 509, 531, 533, 999}  # 999: jefes del mundo (Azuregos, Kazzak, dragones)
INSTANCES.add(999)
creature_maps = defaultdict(set)
for r in DB["creature"]:
    creature_maps[r["id"]].add(r["map"])
object_maps = defaultdict(set)
for r in DB["gameobject"]:
    object_maps[r["id"]].add(r["map"])
creatures = {r["Entry"]: r for r in DB["creature_template"]}


def instance_of(maps):
    inside = [m for m in maps if m in INSTANCES]
    return inside[0] if inside else 0


# --------------------------------------------------------------------------------------------
# Botín: probabilidad efectiva de cada objeto en cada tabla, siguiendo las tablas de referencia
# --------------------------------------------------------------------------------------------
def table_chances(rows_by_entry):
    """Probabilidad (0-100) de cada objeto directo en cada tabla, repartiendo grupos."""
    result = defaultdict(list)  # entry -> [(item, chance) | (-ref, chance)]
    for entry, rows in rows_by_entry.items():
        groups = defaultdict(list)
        for r in rows:
            groups[r["groupid"]].append(r)
        for group, members in groups.items():
            if group == 0:
                for r in members:
                    chance = abs(r["ChanceOrQuestChance"])
                    target = r["item"] if r["mincountOrRef"] >= 0 else -abs(r["mincountOrRef"])
                    result[entry].append((target, chance))
            else:
                explicit = sum(abs(r["ChanceOrQuestChance"]) for r in members if r["ChanceOrQuestChance"])
                equal = [r for r in members if not r["ChanceOrQuestChance"]]
                share = max(0.0, 100 - explicit) / len(equal) if equal else 0
                for r in members:
                    chance = abs(r["ChanceOrQuestChance"]) or share
                    target = r["item"] if r["mincountOrRef"] >= 0 else -abs(r["mincountOrRef"])
                    result[entry].append((target, chance))
    return result


def by_entry(rows):
    out = defaultdict(list)
    for r in rows:
        out[r["entry"]].append(r)
    return out


REF = table_chances(by_entry(DB["reference_loot_template"]))
resolved_ref = {}


def resolve(entry, depth=0):
    """Objetos de una tabla de referencia con su probabilidad final."""
    if entry in resolved_ref:
        return resolved_ref[entry]
    out = defaultdict(float)
    if depth < 5:
        for target, chance in REF.get(entry, []):
            if target < 0:
                for item, sub in resolve(-target, depth + 1).items():
                    out[item] += chance * sub / 100
            else:
                out[target] += chance
    resolved_ref[entry] = dict(out)
    return resolved_ref[entry]


def expand(table):
    out = defaultdict(dict)  # loot entry -> item -> chance
    for entry, pairs in table.items():
        for target, chance in pairs:
            if target < 0:
                for item, sub in resolve(-target).items():
                    out[entry][item] = out[entry].get(item, 0) + chance * sub / 100
            else:
                out[entry][target] = out[entry].get(target, 0) + chance
    return out


creature_loot = expand(table_chances(by_entry(DB["creature_loot_template"])))
object_loot = expand(table_chances(by_entry(DB["gameobject_loot_template"])))
item_loot = expand(table_chances(by_entry(DB["item_loot_template"])))

loot_users = defaultdict(list)  # loot id -> creatures
for entry, c in creatures.items():
    if c["LootId"]:
        loot_users[c["LootId"]].append(entry)

# Jefes invocados (Ragnaros, Ouro...) no tienen aparición fija: su mazmorra se deduce de las tablas
# de botín que comparten con criaturas que sí aparecen, y de los objetos que solo se sueltan ahí.
CREATURE_LOOT_ROWS = by_entry(DB["creature_loot_template"])
ref_places = defaultdict(set)
item_places = defaultdict(set)
for entry, c in creatures.items():
    maps = creature_maps.get(entry)
    if not maps or not c["LootId"]:
        continue
    place = instance_of(maps)
    for r in CREATURE_LOOT_ROWS.get(c["LootId"], []):
        if r["mincountOrRef"] < 0:
            ref_places[-r["mincountOrRef"]].add(place)
        else:
            item_places[r["item"]].add(place)
inferred = 0
for entry, c in creatures.items():
    if entry in creature_maps or not c["LootId"]:
        continue
    votes = defaultdict(int)
    for r in CREATURE_LOOT_ROWS.get(c["LootId"], []):
        places = ref_places.get(-r["mincountOrRef"]) if r["mincountOrRef"] < 0 else item_places.get(r["item"])
        if places and len(places) == 1:
            place = next(iter(places))
            if place:
                votes[place] += 1
    if votes:
        creature_maps[entry] = {max(votes, key=votes.get)}
        inferred += 1
print("Criaturas sin aparición ubicadas por su botín:", inferred)

# Zona según Questie (área) -> mapa de la instancia.
AREA_TO_MAP = {
    209: 33, 717: 34, 1581: 36, 718: 43, 491: 47, 719: 48, 1337: 70, 721: 90, 1477: 109, 722: 129,
    796: 189, 1176: 209, 1583: 229, 1584: 230, 2159: 249, 2057: 289, 1977: 309, 2017: 329, 2100: 349,
    2437: 389, 2717: 409, 2557: 429, 2677: 469, 3429: 509, 3428: 531, 3456: 533,
}
if NPC_DB and NPC_DB.exists():
    import lupa.lua51 as lua51
    text = NPC_DB.read_text(encoding="utf-8", errors="replace")
    start = text.index("QuestieDB.npcData = [[") + len("QuestieDB.npcData = [[")
    end = text.index("]]", start)
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    npc_data = lua.execute(text[start:end])
    placed = 0
    for entry, c in creatures.items():
        if entry in creature_maps or not c["LootId"]:
            continue
        row = npc_data[entry]
        if row is None:
            continue
        zones = [row[9]] if row[9] else []
        spawns = row[7]
        if spawns is not None:
            zones += list(spawns.keys())
        for zone in zones:
            if zone in AREA_TO_MAP:
                creature_maps[entry] = {AREA_TO_MAP[zone]}
                placed += 1
                break
    print("Criaturas sin aparición ubicadas con Questie:", placed)

# Los que ni la base ni Questie ubican, y los jefes del mundo (de banda, aunque estén afuera).
KNOWN_PLACES = {11583: 469, 15989: 533, 15990: 533, 6109: 999, 12397: 999, 14887: 999, 14888: 999,
                14889: 999, 14890: 999}
for entry, place in KNOWN_PLACES.items():
    creature_maps[entry] = {place}

drop_places = defaultdict(set)  # cualquier objeto -> mapas donde lo sueltan (0 = mundo)
for loot_id, loot in creature_loot.items():
    for item in loot:
        for creature in loot_users.get(loot_id, []):
            maps = creature_maps.get(creature)
            if maps:
                drop_places[item].add(instance_of(maps))
drops = defaultdict(list)  # item -> [(chance, creature)]
unspawned = defaultdict(int)
for loot_id, loot in creature_loot.items():
    for item, chance in loot.items():
        if item in items:
            for creature in loot_users.get(loot_id, []):
                drops[item].append((chance, creature))
                if creature not in creature_maps and items[item]["q"] >= 3:
                    unspawned[creature] += 1

print("Criaturas sin aparición que sueltan azules o mejores:", len(unspawned))
print("  ", sorted(((n, c, creatures[c]["Name"]) for c, n in unspawned.items()), reverse=True)[:40])
object_users = defaultdict(list)
for r in DB["gameobject_template"]:
    if r["type"] == 3 and r["data1"]:  # cofre: data1 = tabla de botín
        object_users[r["data1"]].append(r["entry"])
chests = defaultdict(list)
for loot_id, loot in object_loot.items():
    for item, chance in loot.items():
        if item in items:
            for obj in object_users.get(loot_id, []):
                chests[item].append((chance, obj))

containers = defaultdict(list)
for container, loot in item_loot.items():
    for item, chance in loot.items():
        if item in items:
            containers[item].append((chance, container))

# --------------------------------------------------------------------------------------------
# Vendedores, misiones y recetas
# --------------------------------------------------------------------------------------------
vendors = defaultdict(set)
vendor_templates = by_entry(DB["npc_vendor_template"])
for r in DB["npc_vendor"]:
    if r["item"] in items:
        vendors[r["item"]].add(r["entry"])
for entry, c in creatures.items():
    template = c.get("VendorTemplateId")
    if template and template in vendor_templates:
        for r in vendor_templates[template]:
            if r["item"] in items:
                vendors[r["item"]].add(entry)

# Tipo de misión: "q" normal, "Q" de mazmorra, "R" de banda (por su tipo, su zona o porque pide
# objetos que solo se consiguen ahí).
RAID_AREAS = {2717, 2677, 2159, 1977, 3429, 3428, 3456, 19}
# Facciones cuya reputación solo se sube en bandas: Linaje de Nozdormu, Srs. del Agua de Hydraxis, Tribu Zandalar.
RAID_FACTIONS = {910, 749, 270}
DUNGEON_AREAS = {209, 717, 718, 719, 721, 722, 796, 1176, 1337, 1477, 1581, 1583, 1584, 2017, 2057,
                 2100, 2437, 2557, 491, 3457}
quest_kind, quest_level = {}, {}
for r in DB["quest_template"]:
    kind = "q"
    zone = r["ZoneOrSort"]
    if r["Type"] == 62 or zone in RAID_AREAS:
        kind = "R"
    elif r["Type"] == 81 or zone in DUNGEON_AREAS:
        kind = "Q"
    for n in (1, 2, 3, 4):
        places = drop_places.get(r[f"ReqItemId{n}"])
        if places and 0 not in places:
            if all(m in RAIDS for m in places):
                kind = "R"
            elif kind == "q":
                kind = "Q"
    if r["RequiredMinRepFaction"] in RAID_FACTIONS:
        kind = "R"
    quest_kind[r["entry"]] = kind
    quest_level[r["entry"]] = r["MinLevel"] or max(1, (r["QuestLevel"] or 1) - 5)

# Una misión es de banda si viene después de una de banda o pide algo que da una de banda.
rewarded_by = defaultdict(set)
for r in DB["quest_template"]:
    for key in ("RewChoiceItemId1", "RewChoiceItemId2", "RewChoiceItemId3", "RewChoiceItemId4",
                "RewChoiceItemId5", "RewChoiceItemId6", "RewItemId1", "RewItemId2", "RewItemId3", "RewItemId4"):
        if r[key]:
            rewarded_by[r[key]].add(r["entry"])
QUEST_ROWS = {r["entry"]: r for r in DB["quest_template"]}
changed = True
while changed:
    changed = False
    for entry, r in QUEST_ROWS.items():
        if quest_kind[entry] == "R":
            continue
        before = [abs(r["PrevQuestId"] or 0)]
        raid = any(quest_kind.get(prev) == "R" for prev in before if prev)
        for n in (1, 2, 3, 4):
            if any(quest_kind.get(q) == "R" for q in rewarded_by.get(r[f"ReqItemId{n}"], ())):
                raid = True
        if raid:
            quest_kind[entry] = "R"
            changed = True
# Y la misión siguiente de una cadena de banda (NextQuestId / NextQuestInChain) también lo es.
changed = True
while changed:
    changed = False
    for entry, r in QUEST_ROWS.items():
        if quest_kind[entry] == "R":
            for nxt in (r["NextQuestId"], r["NextQuestInChain"]):
                nxt = abs(nxt or 0)
                if nxt in quest_kind and quest_kind[nxt] != "R":
                    quest_kind[nxt] = "R"
                    changed = True

quests = defaultdict(set)
for r in DB["quest_template"]:
    for key in ("RewChoiceItemId1", "RewItemId1"):
        reward = items.get(r[key])
        if reward and (reward["q"] == 5 or reward["ilvl"] >= 80):
            quest_kind[r["entry"]] = "R"  # legendarios y recompensas de nivel de banda
    for key in ("RewChoiceItemId1", "RewChoiceItemId2", "RewChoiceItemId3", "RewChoiceItemId4",
                "RewChoiceItemId5", "RewChoiceItemId6", "RewItemId1", "RewItemId2", "RewItemId3", "RewItemId4"):
        item = r[key]
        if item in items:
            quests[item].add(r["entry"])

# Hechizos que fabrican cada objeto, y qué profesión y nivel piden.
crafted_by = defaultdict(set)
for s in DB["spell_template"]:
    for n in (1, 2, 3):
        if s[f"Effect{n}"] == 24 and s[f"EffectItemType{n}"] in items:
            crafted_by[s["Id"]].add(s[f"EffectItemType{n}"])
teaches = {}  # hechizo que enseña -> hechizo que fabrica
for s in DB["spell_template"]:
    for n in (1, 2, 3):
        if s[f"Effect{n}"] == 36 and s[f"EffectTriggerSpell{n}"] in crafted_by:
            teaches[s["Id"]] = s[f"EffectTriggerSpell{n}"]
craft_skill = {}
for r in DB["item_template"]:  # recetas: al usarlas enseñan el hechizo que fabrica
    if r["class"] == 9:
        for n in range(1, 6):
            spell = r[f"spellid_{n}"]
            target = spell if spell in crafted_by else teaches.get(spell)
            if target and r["RequiredSkill"]:
                craft_skill.setdefault(target, (r["RequiredSkill"], r["RequiredSkillRank"], "r"))
for r in DB["npc_trainer"] + DB["npc_trainer_template"]:
    spell = teaches.get(r["spell"], r["spell"] if r["spell"] in crafted_by else None)
    if spell and r["reqskill"]:
        current = craft_skill.get(spell)
        if not current or current[2] == "r":
            craft_skill[spell] = (r["reqskill"], r["reqskillvalue"], "t")
unknown_craft = sum(1 for spell in crafted_by if spell not in craft_skill)
print("Recetas sin profesión conocida:", unknown_craft, "de", len(crafted_by))
crafts = defaultdict(list)
for spell, made in crafted_by.items():
    if spell in craft_skill:
        for item in made:
            crafts[item].append(craft_skill[spell])

# --------------------------------------------------------------------------------------------
# Fuentes por objeto
# --------------------------------------------------------------------------------------------
WORLD_DROP_CREATURES = 25  # más que esto: botín del mundo
# Intendentes de Garganta Grito de Guerra, Valle de Alterac y Cuenca de Arathi.
PVP_VENDORS = {14753, 14754, 13216, 13217, 13218, 13219, 15126, 15127}


def encode_sources(item_id, item):
    parts = []
    q = sorted(quests.get(item_id, ()), key=lambda quest: ("qQR".index(quest_kind[quest]), quest))
    for kind in "qQR":
        ids = [quest for quest in q if quest_kind[quest] == kind][:4]
        if ids:
            parts.append(kind + ".".join(map(str, ids)))
    v = sorted(vendors.get(item_id, ()))
    if v:
        parts.append("v" + ".".join(map(str, v[:4])))
        if all(vendor in PVP_VENDORS for vendor in v):
            parts.append("p")  # intendentes de campos de batalla: piden reputación de JcJ
    c = crafts.get(item_id)
    if c:
        skill, rank, _ = min(c, key=lambda x: x[1])
        parts.append(f"c{skill}.{rank}")
    d = drops.get(item_id, [])
    if d:
        if len(d) > WORLD_DROP_CREATURES:
            best = max(ch for ch, _ in d)
            parts.append(f"w{best:.2g}")
        else:
            ranked = sorted(d, key=lambda x: (-x[0], x[1]))[:3]
            enc = []
            for chance, creature in ranked:
                cr = creatures.get(creature, {})
                instance = instance_of(creature_maps.get(creature, ()))
                enc.append(f"{creature}:{chance:.3g}:{instance}:{cr.get('Rank', 0)}")
            parts.append("d" + ",".join(enc))
    if item["repFaction"] in RAID_FACTIONS:
        parts = [part if not part.startswith(("q", "Q", "v")) else part for part in parts]
        parts.append("x")  # requiere reputación de banda
    ch = chests.get(item_id, [])
    if ch:
        chance, obj = max(ch)
        parts.append(f"g{obj}:{chance:.3g}:{instance_of(object_maps.get(obj, ()))}")
    co = containers.get(item_id, [])
    if co:
        chance, container = max(co)
        parts.append(f"i{container}:{chance:.3g}")
    return "|".join(parts)


STAT_ORDER = ["S", "A", "T", "I", "P", "hp", "mana", "R", "B", "D", "W", "ap", "rap", "crit", "hit",
              "sp", "spHo", "spFi", "spNa", "spFr", "spSh", "spAr", "heal", "scrit", "scritHo", "scritFi",
              "scritNa", "scritFr", "scritSh", "scritAr", "shit", "mp5", "hp5", "def", "ws", "dodge",
              "parry", "block", "pen", "proc"]

# Presupuesto de estadísticas de los objetos con sufijo al azar ("del Mono", "del Oso"...): la base no
# trae sus estadísticas, así que se estima con los objetos parecidos de estadísticas fijas, como
# puntos de atributos principales por nivel de objeto, según ranura y calidad.
PRIMARY = ("S", "A", "T", "I", "P")
ratios = defaultdict(list)
for item in items.values():
    if not item["random"] and item["q"] in (2, 3):
        total = sum(item["stats"].get(k, 0) for k in PRIMARY)
        if total > 0 and item["ilvl"] >= 10:
            ratios[(item["inv"], item["q"])].append(total / item["ilvl"])
budget = {}
for (inv, q), values in ratios.items():
    if len(values) >= 8:
        values.sort()
        budget[(inv, q)] = values[len(values) // 2]
print("Presupuestos por ranura y calidad:", {k: round(v, 2) for k, v in sorted(budget.items())})

def effective_level(item_id, item):
    """Nivel desde el que sirve: el requerido o, si no tiene, el de su misión o de quien lo suelta."""
    if item["req"] > 0:
        return item["req"]
    options = [quest_level[quest] for quest in quests.get(item_id, ())]
    for _, creature in drops.get(item_id, [])[:50]:
        level = creatures.get(creature, {}).get("MinLevel")
        if level:
            options.append(max(1, level - 3))
    if options:
        return min(options)
    return max(0, item["ilvl"] - 5) if item["q"] >= 2 else 0


lines = []
kept = 0
for item_id in sorted(items):
    item = items[item_id]
    sources = encode_sources(item_id, item)
    if not sources:
        continue  # sin forma conocida de conseguirlo
    stats = ",".join(f"{k}{item['stats'][k]}" for k in STAT_ORDER if k in item["stats"])
    rep_text = f"{item['repFaction']}.{item['repRank']}" if item["repFaction"] else "0"
    head = ",".join(str(x) for x in (item["inv"], item["cls"], item["sub"], item["q"], item["ilvl"],
                                       effective_level(item_id, item), item["allow"], item["race"], item["bind"],
                                       item["random"], item["set"], item["honor"], rep_text))
    lines.append(f'[{item_id}]="{head};{stats};{sources}",')
    kept += 1

OUTPUT.write_text(
    "-- Generado por tools/generar_estadisticas.py a partir de la base de datos de CMaNGOS Classic\n"
    "-- (github.com/cmangos/classic-db). No editar a mano.\n"
    "-- Formato: ranura,clase,subclase,calidad,nivelObjeto,nivelRequerido,clases,razas,ligado,azar,conjunto,"
    "rangoJcJ,reputación;estadísticas;fuentes\n"
    "local _, QR = ...\n"
    "QR.StatsData = {\n"
    f'\tsource = "{SOURCE.name}",\n'
    "\t-- Puntos de atributos por nivel de objeto, para los objetos con sufijo al azar: [ranura] = {verde, azul}\n"
    "\tbudget = {\n" + "\n".join(
        f"\t\t[{inv}] = {{ {budget.get((inv, 2), 0):.3f}, {budget.get((inv, 3), 0):.3f} }},"
        for inv in sorted({inv for inv, _ in budget})) + "\n\t},\n"
    "\titems = {\n" + "\n".join(lines) + "\n\t},\n}\n",
    encoding="utf-8",
)
print(f"Escrito {OUTPUT} con {kept} objetos ({OUTPUT.stat().st_size // 1024} KB)")

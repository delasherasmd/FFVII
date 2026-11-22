#!/usr/bin/env python3
"""Genera los archivos de texto del mod MinotaurSatyr (razas, progresiones,
stats y localizacion en ingles y espanol) desde una sola fuente de datos.

Uso:  python3 bg3-mods/tools/gen_minotaur_satyr.py

Reglas: Minotauro y Satiro de "Mordenkainen Presents: Monsters of the Multiverse"
(la version mas moderna de ambas razas) aplicadas con la logica del PHB 2024:
las razas NO dan aumentos de caracteristica (en BG3 el +2/+1 ya es libre).
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "MinotaurSatyr"
MOD = "MinotaurSatyr"
MOD_UUID = "5c65d01a-5022-40d3-8164-306baf81014a"

RACE_MINO = "56efb91c-23c9-4f11-a741-4b9bf6e4d1e9"
RACE_SATY = "9fec2d6e-be61-4fbe-b7c0-0e83eec9e2ca"
PROG_MINO = "041a44f1-bd4e-4852-b553-6896c4e12da7"
PROG_SATY = "e503995e-6b75-480c-9f3c-98df306e45a4"

# handle: (ingles, espanol)
TEXT = {
    "mino_name": ("h756091eegbccag1f29g934fgc1b305661c55", "Minotaur", "Minotauro"),
    "mino_desc": ("hbfad556cgf81dg220ag0573g23537cc86080",
                  "Towering, horned and relentless, minotaurs charge into battle and never lose their way.",
                  "Imponentes, astados e implacables, los minotauros cargan contra sus enemigos y nunca se pierden."),
    "saty_name": ("h5b9a30dagbc05gad34g3353g6c1c21a7e11a", "Satyr", "Sátiro"),
    "saty_desc": ("hbcd2999cg38c4gdf3cg5c43gda06c6908ce4",
                  "Fey revelers with goat legs and curling horns, as resistant to magic as they are to sobriety.",
                  "Juerguistas feéricos de patas de cabra y cuernos curvos, tan resistentes a la magia como a la sobriedad."),
    "horns_n": ("h4a0cf88eg7c5cga9edgd4eege4a9201a1950", "Horns", "Cuernos"),
    "horns_d": ("h89b890dag3808gbd1fgcd6eg86f250edf67e",
                "Attack with your horns: [1] + Strength modifier Piercing damage.",
                "Ataca con tus cuernos: [1] + modificador de Fuerza de daño perforante."),
    "goring_n": ("h11de2664g6fc6gc9e7gee35gca94b4a4fd52", "Goring Rush", "Embestida Corneadora"),
    "goring_d": ("h36683462g0f57g91efg6f3dg569274973be6",
                 "After you Dash, you can make a horn attack as a bonus action.",
                 "Después de usar Correr, puedes atacar con los cuernos como acción adicional."),
    "hammer_n": ("h270e6489ga726gbafbgd81bg6826ee0c5da2", "Hammering Horns", "Cuernos Martilladores"),
    "hammer_d": ("hf93809cfgc63fg77c6gc4bagbeeeb80de357",
                 "After you hit with a melee attack, you can use a bonus action to shove the target 3m away.",
                 "Después de acertar un ataque cuerpo a cuerpo, puedes usar una acción adicional para empujar al objetivo 3 m."),
    "laby_n": ("h7674d517g692dg767ag4144ga31c0b493741", "Labyrinthine Recall", "Memoria Laberíntica"),
    "laby_d": ("h86ee3b76ga755g826bgb0ddg6ecdc987f107",
               "You always know which way is north and have Advantage on Survival checks.",
               "Siempre sabes dónde está el norte y tienes ventaja en las tiradas de Supervivencia."),
    "ram_n": ("h883cb880g185cg37b4gb635g55c125a0c3c8", "Ram", "Topetazo"),
    "ram_d": ("hc4e72b97gdd7ag3175g272fg1463380744ca",
              "Headbutt with your horns: [1] + Strength modifier Bludgeoning damage.",
              "Embiste con tus cuernos: [1] + modificador de Fuerza de daño contundente."),
    "magres_n": ("hfef64eebge240g4d29g556cg0fec0da16a73", "Magic Resistance", "Resistencia Mágica"),
    "magres_d": ("ha06936ecg03cbg2b9egbc49g83df6e6c8e33",
                 "You have Advantage on saving throws against spells.",
                 "Tienes ventaja en las tiradas de salvación contra conjuros."),
    "leap_n": ("ha18b3899gfe30g934bga3aag8a06d7486d22", "Mirthful Leaps", "Saltos Alegres"),
    "leap_d": ("hf01a37f2g9046g9fedg21a9gf75ad55552aa",
               "Your jump distance is increased.",
               "Tu distancia de salto aumenta."),
    "revel_n": ("h679fbec0g2f31g33a1gf2e5gd3e91dc1f621", "Reveler", "Juerguista"),
    "revel_d": ("hb2d4273fgf614g9cd1gd874g71dffedcc1ab",
                "You gain proficiency in Performance, Persuasion and Musical Instruments.",
                "Obtienes competencia en Interpretación, Persuasión e instrumentos musicales."),
}


def H(key):
    return TEXT[key][0]


def ts(attr, key):
    return f'<attribute id="{attr}" type="TranslatedString" handle="{H(key)}" version="1"/>'


def lsx(region, body):
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<save>
  <version major="4" minor="0" revision="9" build="331"/>
  <region id="{region}">
    <node id="root">
      <children>
{body}
      </children>
    </node>
  </region>
</save>
'''


def race(uuid, name, nkey, dkey, prog):
    # TODO tras extraer el juego: copiar Tags, Visuals, EyeColors, SkinColors, etc.
    # de la raza base (Humano para el minotauro, Elfo para el satiro).
    return f'''        <node id="Race">
          <attribute id="Name" type="FixedString" value="{name}"/>
          {ts("DisplayName", nkey)}
          {ts("Description", dkey)}
          <attribute id="ParentGuid" type="guid" value=""/>
          <attribute id="ProgressionTableUUID" type="guid" value="{prog}"/>
          <attribute id="RaceSoundSwitch" type="FixedString" value="Human"/>
          <attribute id="UUID" type="guid" value="{uuid}"/>
        </node>'''


def progression(uuid, table, name, passives):
    return f'''        <node id="Progression">
          <attribute id="Level" type="uint8" value="1"/>
          <attribute id="Name" type="LSString" value="{name}"/>
          <attribute id="PassivesAdded" type="LSString" value="{';'.join(passives)}"/>
          <attribute id="ProgressionType" type="uint8" value="2"/>
          <attribute id="TableUUID" type="guid" value="{table}"/>
          <attribute id="UUID" type="guid" value="{uuid}"/>
        </node>'''


def stat(name, typ, using=None, **data):
    lines = [f'new entry "{name}"', f'type "{typ}"']
    if using:
        lines.append(f'using "{using}"')
    for k, v in data.items():
        lines.append(f'data "{k}" "{v}"')
    return "\n".join(lines) + "\n\n"


def loc(key):  # texto traducido para stats
    return f"{H(key)};1"


PASSIVES = "".join([
    # ---------- Minotauro ----------
    stat("MS_Minotaur_Horns", "PassiveData",
         DisplayName=loc("horns_n"), Description=loc("horns_d"), DescriptionParams="1d6",
         Icon="Action_Headbutt", Properties="Highlighted",
         Boosts="UnlockSpell(Target_MS_MinotaurHorns)"),
    stat("MS_Minotaur_GoringRush", "PassiveData",
         DisplayName=loc("goring_n"), Description=loc("goring_d"), Icon="Action_Dash",
         StatsFunctorContext="OnCast", Conditions="SpellId('Shout_Dash') or SpellId('Shout_Dash_BonusAction')",
         StatsFunctors="ApplyStatus(SELF,MS_GORING_RUSH,100,1)",
         Boosts="UnlockSpell(Target_MS_GoringRush)"),
    stat("MS_Minotaur_HammeringHorns", "PassiveData",
         DisplayName=loc("hammer_n"), Description=loc("hammer_d"), Icon="Action_Shove",
         StatsFunctorContext="OnAttack",
         Conditions="IsMeleeAttack() and HasDamageEffectFlag(DamageFlags.Hit)",
         StatsFunctors="ApplyStatus(SELF,MS_HAMMERING_READY,100,1)",
         Boosts="UnlockSpell(Target_MS_HammeringHorns)"),
    stat("MS_Minotaur_LabyrinthineRecall", "PassiveData",
         DisplayName=loc("laby_n"), Description=loc("laby_d"), Icon="PassiveFeature_Generic_Tactical",
         Boosts="Advantage(Skill,Survival)"),
    # ---------- Satiro ----------
    stat("MS_Satyr_Ram", "PassiveData",
         DisplayName=loc("ram_n"), Description=loc("ram_d"), DescriptionParams="1d6",
         Icon="Action_Headbutt", Boosts="UnlockSpell(Target_MS_SatyrRam)"),
    stat("MS_Satyr_MagicResistance", "PassiveData",
         DisplayName=loc("magres_n"), Description=loc("magres_d"), Icon="PassiveFeature_MagicResistance",
         Boosts="IF(IsSpell()):Advantage(AllSavingThrows)"),
    stat("MS_Satyr_MirthfulLeaps", "PassiveData",
         DisplayName=loc("leap_n"), Description=loc("leap_d"), Icon="Action_Jump",
         Boosts="JumpMaxDistanceMultiplier(1.3)"),
    stat("MS_Satyr_Reveler", "PassiveData",
         DisplayName=loc("revel_n"), Description=loc("revel_d"), Icon="PassiveFeature_Generic_Explore",
         Boosts="ProficiencyBonus(Skill,Performance);ProficiencyBonus(Skill,Persuasion);Proficiency(MusicalInstrument)"),
    # Velocidad 35 pies (BG3: 9 m = 30 pies -> +1,5 m)
    stat("MS_Satyr_Speed", "PassiveData", Properties="IsHidden",
         Boosts="ActionResource(Movement,1.5,0)"),
])

SPELLS = "".join([
    stat("Target_MS_MinotaurHorns", "SpellData", using="Target_UnarmedAttack",
         SpellType="Target", DisplayName=loc("horns_n"), Description=loc("horns_d"),
         DescriptionParams="1d6", Icon="Action_Headbutt",
         SpellSuccess="DealDamage(1d6+StrengthModifier,Piercing)"),
    stat("Target_MS_GoringRush", "SpellData", using="Target_MS_MinotaurHorns",
         SpellType="Target", DisplayName=loc("goring_n"), Description=loc("goring_d"),
         UseCosts="BonusActionPoint:1",
         RequirementConditions="HasStatus('MS_GORING_RUSH')",
         SpellSuccess="DealDamage(1d6+StrengthModifier,Piercing);RemoveStatus(SELF,MS_GORING_RUSH)"),
    stat("Target_MS_HammeringHorns", "SpellData", using="Target_Shove",
         SpellType="Target", DisplayName=loc("hammer_n"), Description=loc("hammer_d"),
         UseCosts="BonusActionPoint:1",
         RequirementConditions="HasStatus('MS_HAMMERING_READY')",
         TargetConditions="not Self() and not Dead() and not Tagged('SIZE_HUGE') and not Tagged('SIZE_GARGANTUAN')",
         SpellSuccess="Force(3);RemoveStatus(SELF,MS_HAMMERING_READY)"),
    stat("Target_MS_SatyrRam", "SpellData", using="Target_UnarmedAttack",
         SpellType="Target", DisplayName=loc("ram_n"), Description=loc("ram_d"),
         DescriptionParams="1d6", Icon="Action_Headbutt",
         SpellSuccess="DealDamage(1d6+StrengthModifier,Bludgeoning)"),
])

STATUSES = "".join([
    stat("MS_GORING_RUSH", "StatusData", StatusType="BOOST", DisplayName=loc("goring_n"),
         Icon="Action_Dash", StackId="MS_GORING_RUSH", StatusPropertyFlags="DisableOverhead;DisableCombatlog"),
    stat("MS_HAMMERING_READY", "StatusData", StatusType="BOOST", DisplayName=loc("hammer_n"),
         Icon="Action_Shove", StackId="MS_HAMMERING_READY", StatusPropertyFlags="DisableOverhead;DisableCombatlog"),
])

MINO_PASSIVES = ["MS_Minotaur_Horns", "MS_Minotaur_GoringRush",
                 "MS_Minotaur_HammeringHorns", "MS_Minotaur_LabyrinthineRecall"]
SATY_PASSIVES = ["MS_Satyr_Ram", "MS_Satyr_MagicResistance", "MS_Satyr_MirthfulLeaps",
                 "MS_Satyr_Reveler", "MS_Satyr_Speed"]


def loca(lang_index):
    rows = "\n".join(
        f'  <content contentuid="{h}" version="1">{v[lang_index]}</content>'
        for h, *v in TEXT.values())
    return f'<?xml version="1.0" encoding="utf-8"?>\n<contentList>\n{rows}\n</contentList>\n'


META = f'''<?xml version="1.0" encoding="UTF-8"?>
<save>
  <version major="4" minor="0" revision="9" build="331"/>
  <region id="Config">
    <node id="root">
      <children>
        <node id="Dependencies"/>
        <node id="ModuleInfo">
          <attribute id="Author" type="LSString" value="delasherasmd"/>
          <attribute id="Description" type="LSString" value="Playable Minotaur and Satyr races (Monsters of the Multiverse rules)."/>
          <attribute id="Folder" type="LSString" value="{MOD}"/>
          <attribute id="MD5" type="LSString" value=""/>
          <attribute id="Name" type="LSString" value="Minotaur and Satyr"/>
          <attribute id="Tags" type="LSString" value=""/>
          <attribute id="Type" type="FixedString" value="Add-on"/>
          <attribute id="UUID" type="FixedString" value="{MOD_UUID}"/>
          <attribute id="Version64" type="int64" value="36028797018963968"/>
          <children>
            <node id="PublishVersion">
              <attribute id="Version64" type="int64" value="36028797018963968"/>
            </node>
          </children>
        </node>
      </children>
    </node>
  </region>
</save>
'''


def write(rel, content):
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    print("escrito", p.relative_to(ROOT.parent))


def main():
    pub = f"Public/{MOD}"
    write(f"Mods/{MOD}/meta.lsx", META)
    write(f"{pub}/Races/Races.lsx", lsx("Races", "\n".join([
        race(RACE_MINO, "Minotaur", "mino_name", "mino_desc", PROG_MINO),
        race(RACE_SATY, "Satyr", "saty_name", "saty_desc", PROG_SATY)])))
    write(f"{pub}/Progressions/Progressions.lsx", lsx("Progressions", "\n".join([
        progression("a6b1d1a2-3c8e-4f0e-9b7d-0d6f2e1c4a01", PROG_MINO, "Minotaur", MINO_PASSIVES),
        progression("b7c2e2b3-4d9f-4a1f-8c8e-1e7a3f2d5b02", PROG_SATY, "Satyr", SATY_PASSIVES)])))
    data = f"{pub}/Stats/Generated/Data"
    write(f"{data}/Passive.txt", PASSIVES)
    write(f"{data}/Spell_Target.txt", SPELLS)
    write(f"{data}/Status_BOOST.txt", STATUSES)
    write(f"Localization/English/{MOD}.loca.xml", loca(0))
    write(f"Localization/Spanish/{MOD}.loca.xml", loca(1))


if __name__ == "__main__":
    main()

"""Pruebas de Barra Libre fuera del juego (Lua 5.1 con lupa).

Uso: python3 tools/pruebas/barralibre/run.py BarraLibre
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
import lupa.lua51 as lua51

HERE = Path(__file__).resolve().parent
ADDON = Path(sys.argv[1]).resolve()
SOURCE = (ADDON / "BarraLibre.lua").read_text()
CLASS_SOURCE = (ADDON / "ClassSpells.lua").read_text()
failures = []

SETUP = r"""
local saved, class, known = ...
BarraLibreDB = saved
T.class = class or "WARRIOR"
for _, id in ipairs(known or {}) do T.known[id] = true end
assert(loadstring(CLASS_SOURCE, "@ClassSpells.lua"))("BarraLibre", {})
local chunk = assert(loadstring(ADDON_SOURCE, "@BarraLibre.lua"))
chunk("BarraLibre", {})
Fire("ADDON_LOADED", "BarraLibre")
Fire("PLAYER_LOGIN")
function Slash(msg) SlashCmdList.BARRALIBRE(msg) end
function B(i) return _G["BarraLibreBoton" .. i] end
function C(n) return B(72 + n) end
function Bag(list) T.bags[0] = {} for i, e in ipairs(list) do T.bags[0][i] = { id = e[1], count = e[2] } end end
function Shown(from, to) local n = 0 for i = from, to do if B(i):IsShown() then n = n + 1 end end return n end
"""


def scenario(name, body, saved_lua="nil", cls=None, known=()):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute((HERE / "mock.lua").read_text())
    lua.globals().ADDON_SOURCE = SOURCE
    lua.globals().CLASS_SOURCE = CLASS_SOURCE
    lua.execute("CHECKS = {}; function check(c, m) if not c then table.insert(CHECKS, m) end end")
    try:
        lua.execute(SETUP, lua.eval(saved_lua), cls, lua.table_from(list(known)))
        lua.execute(body)
        problems = list(lua.globals().CHECKS.values())
        blocked = list(lua.globals().T.blocked.values())
        if blocked:
            problems.append("blocked in combat: " + ", ".join(blocked))
        if lua.globals().T.insecure:
            problems.append(f"addon code ran inside a click {lua.globals().T.insecure} times")
    except Exception as e:  # noqa: BLE001
        problems = [f"error: {e}"]
    print(("OK   " if not problems else "FAIL ") + name)
    for p in problems:
        print("       -", p)
        failures.append((name, p))


scenario("bar with secure buttons that answer key down and mouse up", r"""
check(BarraLibreBarra1 and BarraLibreBarra1.parent == UIParent, "bar missing")
check(Shown(1, 12) == 10, "default should show 10 buttons")
check(BarraLibreBarra1:IsShown() and not BarraLibreBarra2:IsShown(), "only bar 1 by default")
check(B(1).template == "SecureActionButtonTemplate", "not secure")
check(B(1).clicks[1] == "AnyUp" and B(1).clicks[2] == "AnyDown", "clicks not registered for key down")
check(B(1).attrs.type == nil, "empty button has an action")
check(not B(1).scripts.PreClick and not B(1).scripts.PostClick and not B(1).scripts.OnClick, "addon code in the click path")
check(#UISpecialFrames == 0, "frames added to the game's Esc list")
check(T.chat[#T.chat]:find("/barra auto"), "first-login hint missing")
""")

scenario("drop an item, use it with a key, count and cooldown shown", r"""
Bag({ { 118, 4 }, { 6948, 1 } })
T.cursor = { "item", 118 }
B(1).scripts.OnReceiveDrag(B(1))
check(T.cursor == nil, "cursor not cleared")
check(B(1).attrs.type == "item" and B(1).attrs.item == "item:118", "item action not set")
check(B(1).icon.texture == 1 and B(1).count.text == 4, "icon/count")
T.cursor = { "item", 6948 }
B(1).scripts.OnReceiveDrag(B(1))
check(B(1).attrs.item == "item:6948" and T.cursor and T.cursor[2] == 118, "swap did not return the old item to the cursor")
T.cursor = nil
Slash("tecla 1 shift-q")
check(T.overrides["SHIFT-Q"] == "BarraLibreBoton1:LeftButton", "key not bound")
check(B(1).hotkey.text == "sQ", "hotkey label " .. tostring(B(1).hotkey.text))
PressKey("SHIFT-Q")
check(T.used[1] == "item:6948", "key did not use the item")
T.cooldowns[6948] = { 100, 1800 }
Fire("BAG_UPDATE_COOLDOWN")
check(B(1).cooldown.cd and B(1).cooldown.cd[2] == 1800, "cooldown not shown")
""")

scenario("works in combat: keys use items; changes wait until combat ends", r"""
Bag({ { 118, 4 } })
Slash("poner 2 Poción de sanación menor")
Slash("tecla 2 F")
Fire("PLAYER_REGEN_DISABLED")
T.combat = true
PressKey("F"); PressKey("F")
check(T.used[1] == "item:118" and T.used[2] == "item:118", "potion not usable in combat")
T.cursor = { "item", 2455 }
B(3).scripts.OnReceiveDrag(B(3))
check(T.chat[#T.chat]:find("combate"), "no combat message for drop")
Hover(B(3), true); MouseClick(B(3)); Hover(B(3), false)
Slash("botones 6"); Slash("barras 3"); Slash("teclas")
check(not BarraLibreAsignador:IsShown(), "bind mode opened in combat")
Fire("BAG_UPDATE_DELAYED"); Fire("SPELLS_CHANGED"); Fire("UPDATE_SHAPESHIFT_FORMS"); Advance(1)
T.combat = false
T.cursor = nil
Fire("PLAYER_REGEN_ENABLED")
check(Shown(1, 12) == 10 and BarraLibreDB.numBars == 1, "change made in combat was applied")
check(T.overrides["F"], "binding lost after combat")
""")

scenario("bind mode: hover and press, modifiers, move a key, delete, Esc", r"""
Slash("teclas")
check(BarraLibreAsignador:IsShown(), "bind mode not open")
check(B(1).bindGlow.shown, "buttons not highlighted")
local key = BarraLibreAsignador.scripts.OnKeyDown
Hover(B(2), true)
T.shift = true
key(BarraLibreAsignador, "LSHIFT")
check(next(T.overrides) == nil, "modifier alone was bound")
key(BarraLibreAsignador, "1")
T.shift = false
check(T.overrides["SHIFT-1"] == "BarraLibreBoton2:LeftButton", "SHIFT-1 not bound")
Hover(B(2), false); Hover(B(5), true)
key(BarraLibreAsignador, "1")
check(T.overrides["1"] == "BarraLibreBoton5:LeftButton", "plain 1 not bound")
check(table.concat(T.chat, "\n"):find("Botón de acción 1"), "no warning about replacing an action bar key")
Hover(B(5), false); Hover(B(3), true)
T.ctrl = true; key(BarraLibreAsignador, "1"); T.ctrl = false
check(T.overrides["CTRL-1"] == "BarraLibreBoton3:LeftButton", "ctrl combo")
Hover(B(3), false); Hover(B(4), true)
T.shift = true; key(BarraLibreAsignador, "1"); T.shift = false
check(T.overrides["SHIFT-1"] == "BarraLibreBoton4:LeftButton" and BarraLibreDB.keys[2] == nil, "key not moved to the new button")
key(BarraLibreAsignador, "DELETE")
check(T.overrides["SHIFT-1"] == nil and BarraLibreDB.keys[4] == nil, "delete did not clear")
check(B(4).attrs.type == nil, "button usable during bind mode")
key(BarraLibreAsignador, "ESCAPE")
check(not BarraLibreAsignador:IsShown() and not B(1).bindGlow.shown, "Esc did not close")
""")

scenario("auto-fill with consumables: potions first, hearthstone last, no junk", r"""
Bag({ { 4540, 10 }, { 2589, 20 }, { 6948, 1 }, { 118, 5 }, { 25, 1 }, { 1251, 8 }, { 2455, 3 } })
Slash("auto")
local s = BarraLibreDB.slots
check(s[1] and s[1].id == 118 and s[2].id == 2455, "potions not first")
check(s[3].id == 1251 and s[4].id == 4540, "bandage then food")
check(s[5].id == 6948, "hearthstone missing")
check(s[6] == nil, "junk or weapon added")
Slash("auto")
check(BarraLibreDB.slots[6] == nil, "duplicates added")
""")

scenario("spells and macros; a click with something on the cursor places it without using it", r"""
T.cursor = { "spell", 3, "spell", 2050 }
B(1).scripts.OnReceiveDrag(B(1))
check(B(1).attrs.type == "spell" and B(1).attrs.spell == 2050, "spell slot")
BarraLibreDB.slots[2] = { kind = "item", id = 118 }
Slash("auto") -- reapply actions
T.cursor = { "macro", 1 }
Hover(B(2), true)
check(B(2).attrs.type == nil, "hovering with something on the cursor should disable the button")
MouseClick(B(2))
check(#T.used == 0, "click with something on the cursor used the button")
check(BarraLibreDB.slots[2].kind == "macro" and T.cursor and T.cursor[2] == 118, "click did not place (and swap)")
Advance(0)
check(B(2).attrs.type == nil, "still holding the old item: button must stay disabled")
T.cursor = nil
Fire("CURSOR_CHANGED")
check(B(2).attrs.type == "macro" and B(2).attrs.macro == "Montura", "button not re-enabled after the cursor emptied")
MouseClick(B(2))
check(T.used[1] == "macro:Montura", "macro not run")
Hover(B(2), false)
T.cursor = { "mount", 1 }
B(3).scripts.OnReceiveDrag(B(3))
check(BarraLibreDB.slots[3] == nil and T.chat[#T.chat]:find("no se puede"), "mount accepted")
""")

scenario("drag off: free when unlocked, Shift when locked, never in combat", r"""
BarraLibreDB.slots[1] = { kind = "item", id = 118 }
Slash("bloquear")
check(BarraLibreDB.locked and not BarraLibreAgarradera1:IsShown(), "lock")
B(1).scripts.OnDragStart(B(1))
check(BarraLibreDB.slots[1] ~= nil, "removed without Shift while locked")
T.shift = true
B(1).scripts.OnDragStart(B(1))
T.shift = false
check(BarraLibreDB.slots[1] == nil and T.cursor and T.cursor[2] == 118, "Shift-drag did not pick up")
T.cursor = nil
BarraLibreDB.slots[2] = { kind = "item", id = 118 }
T.combat = true
T.shift = true
B(2).scripts.OnDragStart(B(2))
T.shift = false
T.combat = false
check(BarraLibreDB.slots[2] ~= nil, "removed in combat")
""")

scenario("moving a bar when combat starts never touches a protected frame in combat", r"""
local grip = BarraLibreAgarradera1
grip.scripts.OnDragStart(grip)
check(BarraLibreBarra1.isMoving, "bar did not start moving")
BarraLibreBarra1.px, BarraLibreBarra1.py = 33, 44
Fire("PLAYER_REGEN_DISABLED") -- antes del bloqueo de combate
T.combat = true
check(not BarraLibreBarra1.isMoving and BarraLibreDB.bars[1].x == 33, "bar not dropped and saved before combat")
grip.scripts.OnDragStop(grip)
grip.scripts.OnDragStart(grip)
check(not BarraLibreBarra1.isMoving, "bar moved in combat")
T.combat = false
""")

scenario("saved per character: slots, keys and layout come back", r"""
check(B(1).attrs.item == "item:118" and B(3).attrs.macro == "Montura", "slots not restored")
check(T.overrides["F1"] == "BarraLibreBoton1:LeftButton", "keys not restored")
check(Shown(1, 12) == 5, "count not restored")
check(T.overrides["F7"] == nil, "key on a hidden button bound")
check(BarraLibreBarra2:IsShown() and BarraLibreDB.bars[2].vertical and B(13).attrs.item == "item:2455", "bar 2 not restored")
check(T.overrides["F2"] == "BarraLibreBoton13:LeftButton", "bar 2 key not restored")
""", saved_lua='{ numBars = 2, slots = { [1] = { kind = "item", id = 118 }, [3] = { kind = "macro", name = "Montura" }, [13] = { kind = "item", id = 2455 } }, keys = { [1] = "F1", [7] = "F7", [13] = "F2" }, bars = { [1] = { count = 5 }, [2] = { vertical = true } } }')

scenario("layout commands, help, hide keeps keys working", r"""
Slash("botones 12"); Slash("filas 2"); Slash("escala 1.3")
local b1 = BarraLibreDB.bars[1]
check(b1.count == 12 and b1.lines == 2 and b1.scale == 1.3, "layout values")
local p = B(7).points[1]
check(p and p[4] == 0 and p[5] == -40, "second row should start at button 7")
Slash("tecla 12 F12")
check(T.overrides["F12"], "key on button 12")
Slash("ocultar")
check(not BarraLibreBarra1:IsShown() and T.overrides["F12"], "hide removed keys")
Slash("ocultar")
Slash("botones 99")
check(b1.count == 12, "count not clamped to 12")
Slash("quitar todo"); Slash("centrar"); Slash("")
check(table.concat(T.chat, "\n"):find("/barra teclas"), "help")
""")

scenario("several bars, horizontal and vertical", r"""
Slash("barras 3")
check(BarraLibreDB.numBars == 3 and BarraLibreBarra2:IsShown() and BarraLibreBarra3:IsShown(), "bars 2 and 3 not shown")
check(not BarraLibreBarra4:IsShown(), "bar 4 shown")
local p = B(14).points[1]
check(p[4] == 40 and p[5] == 0, "bar 2 not horizontal")
p = B(26).points[1]
check(p[4] == 0 and p[5] == -40, "bar 3 not vertical")
Slash("2 vertical")
p = B(14).points[1]
check(BarraLibreDB.bars[2].vertical and p[4] == 0 and p[5] == -40, "/barra 2 vertical")
Slash("2 botones 4"); Slash("2 columnas 2")
p = B(16).points[1]
check(p[4] == 40 and p[5] == -40, "vertical bar with 2 columns: button 4 at column 2 row 2")
check(not B(17):IsShown() and B(16):IsShown(), "bar 2 button count")
BarraLibreAgarradera3.scripts.OnClick(BarraLibreAgarradera3)
check(not BarraLibreDB.bars[3].vertical, "right click on the grip did not switch to horizontal")
Slash("2 tecla 1 F2")
check(T.overrides["F2"] == "BarraLibreBoton13:LeftButton", "key on bar 2")
Bag({ { 118, 4 }, { 1251, 8 }, { 4540, 10 }, { 2455, 2 } })
Slash("quitar todo")
for i = 1, 12 do BarraLibreDB.slots[i] = { kind = "item", id = 25 } end
Slash("1 botones 2")
Slash("auto")
check(BarraLibreDB.slots[13] and BarraLibreDB.slots[13].id == 118, "auto-fill did not continue on bar 2")
Slash("teclas")
local key = BarraLibreAsignador.scripts.OnKeyDown
Hover(B(26), true); key(BarraLibreAsignador, "G"); Hover(B(26), false)
check(T.overrides["G"] == "BarraLibreBoton26:LeftButton", "bind mode on bar 3")
key(BarraLibreAsignador, "ESCAPE")
Slash("barras 1")
check(not BarraLibreBarra2:IsShown() and T.overrides["F2"] == nil and T.overrides["G"] == nil, "fewer bars kept their keys")
check(BarraLibreDB.keys[13] == "F2", "key forgotten (should come back with the bar)")
Slash("4 vertical")
check(BarraLibreDB.numBars == 4 and BarraLibreBarra4:IsShown(), "naming bar 4 should turn it on")
Slash("9 vertical")
check(T.chat[#T.chat]:find("1 a 6"), "bar out of range")
T.combat = true
Slash("barras 2")
T.combat = false
check(BarraLibreDB.numBars == 4, "changed number of bars in combat")
""")

scenario("shaman class bar: one totem per element, picker, all totems, keys", r"""
check(BarraLibreBarra7:IsShown(), "class bar not shown")
check(C(1).attrs.type1 == "spell" and C(1).attrs.spell == 8160, "earth: highest known Strength of Earth, got " .. tostring(C(1).attrs.spell))
check(C(1).attrs.type == nil, "right click would also cast")
check(C(2).attrs.spell == 6364 and C(3).attrs.spell == 5675, "fire/water defaults")
check(not C(4):IsShown(), "air shown without air totems")
check(C(5):IsShown() and C(5).points[1][4] == 120, "all-totems button not placed right after water")
check(C(5).attrs.type1 == "macro" and C(5).attrs.macrotext == "/castsequence reset=combat/12 Hechizo 8160, Hechizo 6364, Hechizo 5675",
	"cast-all macro: " .. tostring(C(5).attrs.macrotext))
Hover(C(1), true)
MouseClick(C(1), "RightButton")
check(#T.used == 0, "right click cast something")
check(BarraLibreSelector:IsShown() and BarraLibreSelector.options[2]:IsShown() and not BarraLibreSelector.options[3]:IsShown(), "picker options")
BarraLibreSelector.options[2]:Click()
check(not BarraLibreSelector:IsShown(), "picker did not close")
check(C(1).attrs.spell == 8154 and BarraLibreDB.classChoice.tierra == "Stoneskin Totem", "choice not applied")
check(C(5).attrs.macrotext:find("Hechizo 8154"), "cast-all did not follow the choice")
MouseClick(C(1), "RightButton")
check(BarraLibreSelector:IsShown(), "picker did not reopen")
Hover(C(1), false)
BarraLibreSelector.scripts.OnUpdate(BarraLibreSelector, 2)
check(not BarraLibreSelector:IsShown(), "picker did not close when the mouse left")
Slash("clase tecla 1 F5")
check(T.overrides["F5"] == "BarraLibreBoton73:LeftButton", "class key")
PressKey("F5")
check(T.used[1] == "spell:8154", "key did not cast the chosen totem")
T.known[8512] = true
Fire("SPELLS_CHANGED")
check(C(4):IsShown() and C(4).attrs.spell == 8512 and C(5).attrs.macrotext:find("Hechizo 8512"), "new air totem not added")
Fire("PLAYER_REGEN_DISABLED")
T.combat = true
PressKey("F5")
MouseClick(C(2), "RightButton")
check(not BarraLibreSelector:IsShown() and T.chat[#T.chat]:find("fuera de combate"), "picker opened in combat")
T.combat = false
Slash("clase vertical")
check(BarraLibreDB.bars[7].vertical and C(2).points[1][5] == -40, "class bar vertical")
Slash("clase botones 3")
check(T.chat[#T.chat]:find("se arma sola"), "class bar accepted botones")
Slash("clase")
check(not BarraLibreBarra7:IsShown() and T.overrides["F5"] == nil, "hiding the class bar kept its key")
Slash("clase")
check(BarraLibreBarra7:IsShown() and T.overrides["F5"], "class bar did not come back with its key")
""", cls="SHAMAN", known=(8075, 8160, 8071, 8154, 3599, 6363, 6364, 5394, 6375, 5675))

scenario("hunter: the pet bar, only with a pet, autocast on right click", r"""
T.pet = {
	[1] = { "PET_ACTION_ATTACK", "PET_ATTACK_TEXTURE", true, false, false, false },
	[2] = { "PET_ACTION_FOLLOW", "PET_FOLLOW_TEXTURE", true, true, false, false },
	[4] = { "Mordedura", "Interface\\Icons\\Ability_Racial_Cannibalize", false, false, true, true },
	[10] = { "PET_MODE_DEFENSIVE", "PET_DEFENSIVE_TEXTURE", true, true, false, false },
}
Fire("UNIT_PET", "player")
Fire("PET_BAR_UPDATE")
Advance(0.3)
check(BarraLibreBarra7.driver == "[pet] show; hide", "pet bar not driven by the pet: " .. tostring(BarraLibreBarra7.driver))
check(Shown(73, 84) == 10, "pet bar should have 10 slots")
check(C(1).attrs.type1 == "pet" and C(1).attrs.action == 1, "attack slot")
check(C(1).icon.texture == PET_ATTACK_TEXTURE, "token icon: " .. tostring(C(1).icon.texture))
check(C(2).activeGlow.shown and C(10).activeGlow.shown and not C(1).activeGlow.shown, "active highlight")
check(C(4).attrs.type2 == "macro" and C(4).attrs.macrotext2 == "/petautocasttoggle Mordedura", "autocast on right click")
check(C(4).count.text:find("auto") and C(1).attrs.type2 == nil, "autocast mark")
Slash("clase tecla 1 F1")
PressKey("F1")
check(T.used[1] == "pet:1", "key did not command the pet")
MouseClick(C(4), "RightButton")
check(T.used[2] == "macrotext:/petautocasttoggle Mordedura", "right click did not toggle autocast")
check(not BarraLibreSelector:IsShown(), "totem picker opened on the pet bar")
Fire("PLAYER_REGEN_DISABLED")
T.combat = true
T.pet[5] = { "Gruñido", "icon", false, false, true, false }
Fire("PET_BAR_UPDATE")
PressKey("F1")
T.combat = false
Fire("PLAYER_REGEN_ENABLED")
check(C(5).attrs.macrotext2 == "/petautocasttoggle Gruñido", "new pet ability not set up after combat")
Slash("clase")
check(BarraLibreBarra7.driver == nil and not BarraLibreBarra7:IsShown(), "pet bar not hidden with /barra clase")
""", cls="HUNTER")

scenario("warrior: stances like the stance bar", r"""
T.forms = { { "icon-battle", true, true, 2457 }, { "icon-defensive", false, true, 71 } }
Fire("UPDATE_SHAPESHIFT_FORMS")
check(BarraLibreBarra7:IsShown() and C(1):IsShown() and C(2):IsShown() and not C(3):IsShown(), "two stances expected")
check(C(1).attrs.type1 == "spell" and C(2).attrs.spell == 71, "stance spells")
check(C(1).activeGlow.shown and not C(2).activeGlow.shown, "active stance highlight")
T.forms[3] = { "icon-berserker", false, true, 2458 }
Fire("UPDATE_SHAPESHIFT_FORMS")
check(C(3):IsShown() and C(3).attrs.spell == 2458, "new stance not added")
""", cls="WARRIOR")

scenario("mage: no class bar", r"""
check(not BarraLibreBarra7:IsShown(), "mage got a class bar")
Slash("clase tecla 1 F5")
check(T.overrides["F5"] == nil, "key bound on a missing class bar")
""", cls="MAGE", known=(1459,))

scenario("if the game blocks something, the chat says exactly what (once)", r"""
Fire("ADDON_ACTION_FORBIDDEN", "BarraLibre", "CastSpellByID()")
check(T.chat[#T.chat]:find("CastSpellByID"), "blocked function not reported")
local n = #T.chat
Fire("ADDON_ACTION_FORBIDDEN", "BarraLibre", "CastSpellByID()")
Fire("ADDON_ACTION_BLOCKED", "OtroAddon", "Algo()")
check(#T.chat == n, "repeated or foreign reports printed")
""")

root = ET.parse(ADDON / "Bindings.xml").getroot()
names = [b.get("name") for b in root.iter("Binding")]
ok = names[0] == "BARRALIBRE_TECLAS" and all(f"CLICK BarraLibreBoton{i}:LeftButton" in names for i in range(1, 85))
print(("OK   " if ok else "FAIL ") + "Bindings.xml")
if not ok:
    failures.append(("bindings", names[:3]))
print("\nall passed" if not failures else f"\n{len(failures)} problem(s)")
sys.exit(1 if failures else 0)

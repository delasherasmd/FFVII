-- Simulación mínima de la API de WoW para probar Barra Libre fuera del juego, con las reglas de
-- combate: lo protegido falla en combate y queda anotado en T.blocked.
T = { now = 0, timers = {}, frames = {}, chat = {}, combat = false, blocked = {}, overrides = {}, cursor = nil,
	bags = {}, used = {}, cooldowns = {}, tooltip = {} }

local function blocked(what)
	if T.combat then
		table.insert(T.blocked, what)
		error("ADDON_ACTION_BLOCKED: " .. what)
	end
end

function GetTime() return T.now end
function InCombatLockdown() return T.combat end
C_Timer = { After = function(s, f) table.insert(T.timers, { at = T.now + s, f = f }) end }
function Advance(seconds)
	T.now = T.now + (seconds or 0)
	local again = true
	while again do
		again = false
		for i, t in ipairs(T.timers) do
			if t.at <= T.now then table.remove(T.timers, i); t.f(); again = true; break end
		end
	end
end

local Region = {}
Region.__index = function(self, key)
	local v = rawget(Region, key)
	if v then return v end
	if type(key) == "string" and key:match("^%u") then return function() end end
end
local function NewRegion(kind, parent)
	return setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, attrs = {}, points = {} }, Region)
end
function Region:SetTexture(t) self.texture = t end
function Region:GetTexture() return self.texture end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:SetText(t) self.text = t end
function Region:GetText() return self.text end
function Region:SetDesaturated(v) self.desaturated = v end
function Region:SetVertexColor(r, g, b) self.color = { r, g, b } end
function Region:IsShown() return self.shown end
function Region:IsProtected() return self.protected == true end
function Region:IsMouseOver() return self.mouseOver == true end
function Region:Show()
	if self.protected then blocked("Show") end
	if not self.shown then self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
end
function Region:Hide()
	if self.protected then blocked("Hide") end
	if self.shown then self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
end
function Region:SetPoint(...)
	if self.protected then blocked("SetPoint") end
	table.insert(self.points, { ... })
end
function Region:ClearAllPoints() if self.protected then blocked("ClearAllPoints") end self.points = {} end
function Region:SetScript(k, f) self.scripts[k] = f end
function Region:GetScript(k) return self.scripts[k] end
function Region:CreateTexture() return NewRegion("Texture", self) end
function Region:CreateFontString() return NewRegion("FontString", self) end
function Region:GetNormalTexture() self.normal = self.normal or NewRegion("Texture", self) return self.normal end
function Region:SetAttribute(k, v)
	if self.protected then blocked("SetAttribute") end
	self.attrs[k] = v
end
function Region:GetAttribute(k) return self.attrs[k] end
function Region:RegisterForClicks(...) self.clicks = { ... } end
function Region:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
function Region:SetCooldown(start, duration) self.cd = { start, duration } end
function Region:Clear() self.cd = nil end
function Region:GetFrameLevel() return 1 end
function Region:SetScale(s) if self.protected then blocked("SetScale") end self.scale = s end
function Region:SetSize(w, h) if self.protected then blocked("SetSize") end self.w, self.h = w, h end
function Region:GetPoint() return "CENTER", nil, "CENTER", self.px or 10, self.py or 20 end
function Region:GetParent() return self.parent end
function Region:StartMoving() if self.protected then blocked("StartMoving") end self.isMoving = true end
function Region:StopMovingOrSizing() if self.protected then blocked("StopMovingOrSizing") end self.isMoving = false end
function Region:Click(button) if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end end

function CreateFrame(kind, name, parent, template)
	local f = NewRegion(kind, parent)
	f.name, f.template = name, template
	if template and template:find("SecureActionButtonTemplate") then f.protected = true end
	-- Un marco con hijos protegidos también lo es (moverlo en combate está prohibido).
	if f.protected and parent then parent.protected = true end
	table.insert(T.frames, f)
	if name then _G[name] = f end
	return f
end
UIParent = NewRegion("Frame")
UIParent.name = "UIParent"

function Fire(event, ...)
	for _, f in ipairs(T.frames) do
		if f.events and f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end

-- Teclas
function SetOverrideBindingClick(owner, priority, key, button, mouse)
	blocked("SetOverrideBindingClick")
	T.overrides[key] = button .. ":" .. mouse
end
function ClearOverrideBindings(owner) blocked("ClearOverrideBindings"); T.overrides = {} end
T.bindings = { ["1"] = "ACTIONBUTTON1", ["F"] = "" }
function GetBindingAction(key) return T.bindings[key] or "" end
function GetBindingKey() return nil end
BINDING_NAME_ACTIONBUTTON1 = "Botón de acción 1"

-- Lo que hace el juego con un botón seguro (SecureActionButton_OnClick con ActionButtonUseKeyDown = 1):
-- con una tecla actúa al apretar; con el mouse, al soltar. "type1" solo responde al izquierdo.
-- T.insecure registra si corrió código del addon dentro del clic (no debería).
local function SecureAction(button, mouse)
	local suffix = mouse == "LeftButton" and "1" or "2"
	local t = button.attrs["type" .. suffix] or button.attrs.type
	if t == "item" then table.insert(T.used, button.attrs.item)
	elseif t == "spell" then table.insert(T.used, "spell:" .. tostring(button.attrs.spell))
	elseif t == "pet" then table.insert(T.used, "pet:" .. tostring(button.attrs.action))
	elseif t == "macro" then
		table.insert(T.used, button.attrs.macro and ("macro:" .. tostring(button.attrs.macro))
			or ("macrotext:" .. tostring(button.attrs["macrotext" .. suffix] or button.attrs.macrotext)))
	end
end
local function ClickScripts(button, mouse, down)
	for _, name in ipairs({ "PreClick", "PostClick", "OnClick" }) do
		if button.scripts[name] then T.insecure = (T.insecure or 0) + 1; button.scripts[name](button, mouse, down) end
	end
end
function PressKey(key)
	local target = T.overrides[key]
	if not target then return end
	local button = _G[target:match("^(.-):")]
	ClickScripts(button, "LeftButton", true)
	SecureAction(button, "LeftButton")
	ClickScripts(button, "LeftButton", false)
end
function MouseClick(button, mouse)
	mouse = mouse or "LeftButton"
	ClickScripts(button, mouse, true)
	if button.scripts.OnMouseUp then button.scripts.OnMouseUp(button, mouse) end
	SecureAction(button, mouse)
	ClickScripts(button, mouse, false)
end
function Hover(button, on)
	button.mouseOver = on
	local f = button.scripts[on and "OnEnter" or "OnLeave"]
	if f then f(button) end
end

-- Cursor
function GetCursorInfo()
	local c = T.cursor
	if not c then return nil end
	return c[1], c[2], c[3], c[4]
end
function ClearCursor() T.cursor = nil end
function PickupItem(id) T.cursor = { "item", id } end
function PickupSpell(id) T.cursor = { "spell", 1, "spell", id } end
function PickupMacro(name) T.cursor = { "macro", name } end
T.macros = { ["Montura"] = 132226, [1] = "Montura" }
function GetMacroInfo(x)
	if type(x) == "number" then x = T.macros[x] end
	if T.macros[x] then return x, T.macros[x], "/cast X" end
end

-- Objetos y bolsas
T.items = {
	[118] = { name = "Poción de sanación menor", icon = 1, class = 0, sub = 1, spell = "Sanar", stack = 5 },
	[2455] = { name = "Poción de maná menor", icon = 2, class = 0, sub = 1, spell = "Maná", stack = 5 },
	[1251] = { name = "Venda de lino", icon = 3, class = 0, sub = 7, spell = "Primeros auxilios", stack = 20 },
	[4540] = { name = "Pan duro", icon = 4, class = 0, sub = 5, spell = "Comida", stack = 20 },
	[6948] = { name = "Piedra de hogar", icon = 5, class = 15, sub = 0, spell = "Hogar", stack = 1 },
	[2589] = { name = "Paño de lino", icon = 6, class = 7, sub = 5, spell = nil, stack = 20 },
	[25] = { name = "Espada corta", icon = 7, class = 2, sub = 7, spell = nil, stack = 1 },
}
C_Item = {}
function C_Item.GetItemCount(id) local n = 0 for _, b in pairs(T.bags) do for _, s in pairs(b) do if s.id == id then n = n + s.count end end end return n end
function C_Item.GetItemIconByID(id) return T.items[id] and T.items[id].icon or 134400 end
function C_Item.GetItemInfo(x)
	local id = type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)"))
	local it = T.items[id]
	if not it then return nil end
	return it.name, "link", 1, 1, 1, "", "", it.stack
end
function C_Item.GetItemInfoInstant(x)
	local id = tonumber(x)
	if not id then for k, it in pairs(T.items) do if it.name == x then id = k end end end
	local it = id and T.items[id]
	if not it then return nil end
	return id, "", "", "", it.icon, it.class, it.sub
end
function C_Item.GetItemSpell(id) return T.items[id] and T.items[id].spell end
function C_Item.IsUsableItem() return true end
C_Container = {}
function C_Container.GetContainerNumSlots(bag) return T.bags[bag] and 16 or 0 end
function C_Container.GetContainerItemID(bag, slot) local b = T.bags[bag] return b and b[slot] and b[slot].id end
function C_Container.GetItemCooldown(id) local c = T.cooldowns[id] if c then return c[1], c[2], 1 end return 0, 0, 1 end
C_Spell = { GetSpellTexture = function(id) return 1000 + id end, GetSpellName = function(id) return "Hechizo " .. id end,
	GetSpellCooldown = function() return { startTime = 0, duration = 0 } end, PickupSpell = PickupSpell }

-- Clase, libro de hechizos, posturas y mascota
T.class, T.known, T.forms, T.pet = "WARRIOR", {}, {}, {}
function UnitClass() return "Clase", T.class, 1 end
function IsPlayerSpell(id) return T.known[id] == true end
function IsSpellKnown(id) return T.known[id] == true end
function GetNumShapeshiftForms() return #T.forms end
function GetShapeshiftFormInfo(i) local f = T.forms[i] if f then return f[1], f[2], f[3], f[4] end end
function GetShapeshiftFormCooldown() return 0, 0, 1 end
function GetPetActionInfo(i) local a = T.pet[i] if a then return a[1], a[2], a[3], a[4], a[5], a[6] end end
function GetPetActionCooldown() return 0, 0, 1 end
function GetPetActionSlotUsable() return true end
PET_ATTACK_TEXTURE = "Interface\\Icons\\Ability_GhoulFrenzy"
function RegisterStateDriver(frame, attribute, condition) blocked("RegisterStateDriver"); frame.driver = condition end
function UnregisterStateDriver(frame) blocked("UnregisterStateDriver"); frame.driver = nil end
UISpecialFrames = {}
tinsert = table.insert

-- Varios
T.shift, T.ctrl, T.alt = false, false, false
function IsShiftKeyDown() return T.shift end
function IsControlKeyDown() return T.ctrl end
function IsAltKeyDown() return T.alt end
GameTooltip = NewRegion("GameTooltip")
function GameTooltip:SetOwner() T.tooltip = {} end
function GameTooltip:AddLine(t) table.insert(T.tooltip, t) end
function GameTooltip:SetItemByID(id) table.insert(T.tooltip, "item " .. id) end
function GameTooltip:SetSpellByID(id) table.insert(T.tooltip, "spell " .. id) end
function GameTooltip:SetPetAction(i) table.insert(T.tooltip, "pet " .. i) end
function GameTooltip:SetShapeshift(i) table.insert(T.tooltip, "stance " .. i) end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(T.chat, m) end }
SlashCmdList = {}
format = string.format
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
NUM_BAG_SLOTS = 4

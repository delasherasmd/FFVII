-- Barra Libre: barras propias para objetos, pociones, hechizos y macros que se
-- usan de vez en cuando, con teclas del teclado. Funciona aunque juegues con
-- mando (el modo mando del juego o ConsolePort): es independiente de las barras
-- de acción y de las asignaciones del mando.
-- Hasta 6 barras, cada una horizontal o vertical, y una barra de clase (tótems,
-- auras, aspectos...) que se arma sola con lo que tu personaje conoce.
-- WoW Classic Era (1.15) y WoW Forever (1.60).

local ADDON_NAME = ...
local PREFIX = "|cff66ddffBarra Libre:|r "
local MAX_BARS = 6       -- barras propias
local CLASS_BAR = 7      -- la barra de clase va después
local TOTAL_BARS = 7
local PER_BAR = 12
local MAX_BUTTONS = TOTAL_BARS * PER_BAR
local BUTTON_SIZE = 36
local GAP = 4
local HEARTHSTONE = 6948

BINDING_HEADER_BARRALIBRE = "Barra Libre"
BINDING_NAME_BARRALIBRE_TECLAS = "Asignar teclas a la Barra Libre"
for index = 1, MAX_BUTTONS do
	local bar, n = math.floor((index - 1) / PER_BAR) + 1, (index - 1) % PER_BAR + 1
	_G["BINDING_NAME_CLICK BarraLibreBoton" .. index .. ":LeftButton"] = bar == CLASS_BAR
		and format("Barra de clase, botón %d", n) or format("Barra %d, botón %d", bar, n)
end

-- Dónde aparece cada barra la primera vez.
local BAR_DEFAULTS = {
	{ vertical = false, point = "BOTTOM", x = 0, y = 200 },
	{ vertical = false, point = "BOTTOM", x = 0, y = 245 },
	{ vertical = true, point = "RIGHT", x = -60, y = 0 },
	{ vertical = true, point = "LEFT", x = 60, y = 0 },
	{ vertical = false, point = "BOTTOM", x = 0, y = 290 },
	{ vertical = false, point = "BOTTOM", x = 0, y = 335 },
	{ vertical = false, point = "BOTTOM", x = 0, y = 155 }, -- barra de clase
}

local DEFAULTS = {
	numBars = 1,       -- cuántas barras se usan
	locked = false,    -- con candado, para sacar algo hay que arrastrar con Mayús
	bars = {},         -- por barra: count, vertical, lines, scale, point, x, y, hidden
	slots = {},        -- [botón] = {kind = "item" | "spell" | "macro", id = número, name = nombre de macro}
	keys = {},         -- [botón] = "SHIFT-1"
	classBar = true,   -- mostrar la barra de clase
	classChoice = {},  -- [grupo] = lo elegido en ese grupo (nombre en inglés de la base)
}

local function BarDefaults(bar)
	local base = BAR_DEFAULTS[bar]
	return { count = (bar == 1 or bar == CLASS_BAR) and 10 or 6, vertical = base.vertical, lines = 1, scale = 1,
		point = base.point, relativePoint = base.point, x = base.x, y = base.y, hidden = false }
end

-- Funciones que cambian de nombre entre versiones del juego.
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local IsUsableItem = (C_Item and C_Item.IsUsableItem) or IsUsableItem
local GetContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetContainerItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID

local function ItemCooldown(itemId)
	if C_Container and C_Container.GetItemCooldown then
		return C_Container.GetItemCooldown(itemId)
	elseif GetItemCooldown then
		return GetItemCooldown(itemId)
	end
end

local function SpellTexture(spellId)
	if C_Spell and C_Spell.GetSpellTexture then
		return C_Spell.GetSpellTexture(spellId)
	end
	return GetSpellTexture and GetSpellTexture(spellId)
end

local function SpellName(spellId)
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(spellId)
	end
	return GetSpellInfo and (GetSpellInfo(spellId))
end

local function SpellCooldown(spellId)
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(spellId)
		if type(info) == "table" then
			return info.startTime, info.duration
		end
		return info
	end
	if GetSpellCooldown then
		return GetSpellCooldown(spellId)
	end
end

local db
local bars, grips, buttons = {}, {}, {}
local binder, bindHint
local pendingSetup = false -- algo cambió en combate: se aplica al salir
local binding = false      -- modo asignar teclas
local hovered              -- botón bajo el mouse en el modo asignar teclas

local function Print(message)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. message)
end

-- Botón n de la barra b <-> número de botón (1 a 72).
local function IndexOf(bar, n)
	return (bar - 1) * PER_BAR + n
end

local function BarOf(index)
	return math.floor((index - 1) / PER_BAR) + 1, (index - 1) % PER_BAR + 1
end

--------------------------------------------------------------------------------
-- Barra de clase: grupos de hechizos (o venenos) con uno elegido en cada uno
--------------------------------------------------------------------------------

local classGroups = {} -- [n] = {key, label, options = {{key, id}}, chosen, items, slot, all}

local function SpellKnown(spellId)
	return (IsPlayerSpell and IsPlayerSpell(spellId)) or (IsSpellKnown and IsSpellKnown(spellId)) or false
end

--- El rango más alto que conoce el personaje (los rangos vienen de menor a mayor).
local function BestRank(ids)
	for i = #ids, 1, -1 do
		if SpellKnown(ids[i]) then
			return ids[i]
		end
	end
end

--- El veneno de más nivel que tenés en las bolsas.
local function BestItem(ids)
	for i = #ids, 1, -1 do
		if (GetItemCount(ids[i]) or 0) > 0 then
			return ids[i]
		end
	end
end

--- Arma la barra de clase con lo que el personaje conoce ahora.
local function ScanClass()
	wipe(classGroups)
	local _, classFile = UnitClass("player")
	local data = BarraLibreClassSpells and BarraLibreClassSpells[classFile]
	if not data then
		return
	end
	for n, group in ipairs(data) do
		local options = {}
		for _, family in ipairs(group[3]) do
			local id = group.items and BestItem(family[2]) or BestRank(family[2])
			if id then
				options[#options + 1] = { key = family[1], id = id }
			end
		end
		local chosen = options[1]
		for _, option in ipairs(options) do
			if option.key == db.classChoice[group[1]] then
				chosen = option
			end
		end
		classGroups[n] = { key = group[1], label = group[2], options = options, chosen = chosen,
			items = group.items, slot = group.slot }
	end
	-- Chamán: un botón más que pone los tótems elegidos, uno por pulsación.
	if classFile == "SHAMAN" then
		local any = false
		for _, group in ipairs(classGroups) do
			if group.chosen then any = true end
		end
		classGroups[#classGroups + 1] = { key = "todos", label = "Todos los tótems", options = {}, all = true,
			chosen = any and { key = "todos" } or nil }
	end
end

local function ClassGroup(index)
	local bar, n = BarOf(index)
	return bar == CLASS_BAR and classGroups[n] or nil
end

--- ¿El botón está en uso? (su barra está entre las elegidas y él entre los botones de la barra)
local function IsActive(index)
	local bar, n = BarOf(index)
	if bar == CLASS_BAR then
		local group = classGroups[n]
		return db.classBar and group ~= nil and group.chosen ~= nil
	end
	return bar <= db.numBars and n <= db.bars[bar].count
end

local function ActiveIndexes()
	local list = {}
	for index = 1, MAX_BUTTONS do
		if IsActive(index) then
			list[#list + 1] = index
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- Teclas
--------------------------------------------------------------------------------

local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
	UNKNOWN = true, LMETA = true, RMETA = true }

--- Texto corto para la esquina del botón: "SHIFT-1" -> "s1".
local function ShortKey(key)
	if not key or key == "" then
		return ""
	end
	local text = key:upper()
	text = text:gsub("ALT%-", "a"):gsub("CTRL%-", "c"):gsub("SHIFT%-", "s")
	text = text:gsub("NUMPAD", "N"):gsub("MOUSEWHEELUP", "RA"):gsub("MOUSEWHEELDOWN", "RB")
	text = text:gsub("BUTTON", "M"):gsub("SPACE", "Esp"):gsub("PAGEUP", "PgA"):gsub("PAGEDOWN", "PgB")
	text = text:gsub("INSERT", "Ins"):gsub("DELETE", "Sup"):gsub("HOME", "Ini"):gsub("END", "Fin")
	text = text:gsub("PLUS", "+"):gsub("MINUS", "-"):gsub("MULTIPLY", "*"):gsub("DIVIDE", "/")
	return text
end

local function ButtonName(index)
	return "BarraLibreBoton" .. index
end

--- La tecla de un botón: la de la barra o la del menú de atajos del juego.
local function KeyFor(index)
	local key = db.keys[index]
	if key then
		return key
	end
	return GetBindingKey and GetBindingKey("CLICK " .. ButtonName(index) .. ":LeftButton") or nil
end

local function ApplyBindings()
	if InCombatLockdown() then
		pendingSetup = true
		return
	end
	ClearOverrideBindings(bars[1])
	for _, index in ipairs(ActiveIndexes()) do
		local key = db.keys[index]
		if key then
			SetOverrideBindingClick(bars[1], true, key, ButtonName(index), "LeftButton")
		end
	end
end

--------------------------------------------------------------------------------
-- Contenido de los botones
--------------------------------------------------------------------------------

--- Lo que hay en un botón: lo que pusiste, o lo elegido en su grupo de la barra de clase.
local function SlotFor(index)
	local group = ClassGroup(index)
	if not group then
		return db.slots[index]
	end
	if not group.chosen then
		return nil
	end
	if group.all then
		-- /castsequence con los tótems elegidos, con su nombre en tu idioma.
		local names, icon = {}, nil
		for _, other in ipairs(classGroups) do
			if other.chosen and not other.all then
				names[#names + 1] = SpellName(other.chosen.id)
				icon = icon or SpellTexture(other.chosen.id)
			end
		end
		return { kind = "macrotext", text = "/castsequence reset=combat/12 " .. table.concat(names, ", "),
			icon = icon, label = "todos" }
	elseif group.items then
		return { kind = "poison", id = group.chosen.id, slot = group.slot }
	end
	return { kind = "spell", id = group.chosen.id }
end

local function SlotIcon(slot)
	if not slot then
		return nil
	end
	if slot.kind == "item" or slot.kind == "poison" then
		return GetItemIcon(slot.id)
	elseif slot.kind == "spell" then
		return SpellTexture(slot.id)
	elseif slot.kind == "macro" then
		local _, icon = GetMacroInfo(slot.name)
		return icon
	elseif slot.kind == "macrotext" then
		return slot.icon
	end
end

--- Lo que hace el botón al usarlo (solo fuera de combate).
local function ApplyAction(button)
	local slot = SlotFor(button.index)
	button:SetAttribute("item", nil)
	button:SetAttribute("spell", nil)
	button:SetAttribute("macro", nil)
	button:SetAttribute("macrotext", nil)
	button:SetAttribute("type1", nil)
	if ClassGroup(button.index) then
		-- Barra de clase: solo el clic izquierdo (y la tecla) usan el botón; el derecho elige.
		button:SetAttribute("type", nil)
		if binding or not slot then
			return
		elseif slot.kind == "spell" then
			button:SetAttribute("type1", "spell")
			button:SetAttribute("spell", slot.id)
		elseif slot.kind == "poison" then
			button:SetAttribute("type1", "macro")
			button:SetAttribute("macrotext", format("/use item:%d\n/use %d", slot.id, slot.slot))
		elseif slot.kind == "macrotext" then
			button:SetAttribute("type1", "macro")
			button:SetAttribute("macrotext", slot.text)
		end
		return
	end
	if binding or not slot then
		button:SetAttribute("type", nil)
	elseif slot.kind == "item" then
		button:SetAttribute("type", "item")
		button:SetAttribute("item", "item:" .. slot.id)
	elseif slot.kind == "spell" then
		button:SetAttribute("type", "spell")
		button:SetAttribute("spell", slot.id)
	elseif slot.kind == "macro" then
		button:SetAttribute("type", "macro")
		button:SetAttribute("macro", slot.name)
	end
end

local function UpdateCooldown(button)
	local slot = SlotFor(button.index)
	local start, duration
	if slot and (slot.kind == "item" or slot.kind == "poison") then
		start, duration = ItemCooldown(slot.id)
	elseif slot and slot.kind == "spell" then
		start, duration = SpellCooldown(slot.id)
	end
	if start and duration and duration > 1.5 then
		button.cooldown:SetCooldown(start, duration)
	else
		button.cooldown:Clear()
	end
end

local function UpdateButton(button)
	local slot = SlotFor(button.index)
	local icon = SlotIcon(slot)
	button.icon:SetTexture(icon)
	button.icon:SetShown(icon ~= nil)
	button.icon:SetDesaturated(false)
	button.icon:SetVertexColor(1, 1, 1)
	button.count:SetText(slot and slot.label or "")
	if slot and (slot.kind == "item" or slot.kind == "poison") then
		local count = GetItemCount(slot.id) or 0
		local _, _, _, _, _, _, _, stack = GetItemInfo(slot.id)
		if count ~= 1 or (stack and stack > 1) then
			button.count:SetText(count)
		end
		if count == 0 then
			button.icon:SetDesaturated(true)
		elseif IsUsableItem and not IsUsableItem(slot.id) then
			button.icon:SetVertexColor(0.4, 0.4, 0.4)
		end
	end
	button.hotkey:SetText(ShortKey(KeyFor(button.index)))
	button.bindGlow:SetShown(binding)
	UpdateCooldown(button)
end

local function UpdateAll()
	for _, button in ipairs(buttons) do
		UpdateButton(button)
	end
end

local function UpdateCooldowns()
	for _, button in ipairs(buttons) do
		if button:IsShown() then
			UpdateCooldown(button)
		end
	end
end

--------------------------------------------------------------------------------
-- Poner y sacar cosas (arrastrar y soltar)
--------------------------------------------------------------------------------

local function Pickup(slot)
	if slot.kind == "item" then
		PickupItem(slot.id)
	elseif slot.kind == "spell" then
		if C_Spell and C_Spell.PickupSpell then
			C_Spell.PickupSpell(slot.id)
		else
			PickupSpell(slot.id)
		end
	elseif slot.kind == "macro" then
		PickupMacro(slot.name)
	end
end

--- Lo que hay en el cursor, como contenido de un botón (o nil y el motivo).
local function SlotFromCursor()
	local kind, a, b, c = GetCursorInfo()
	if kind == "item" then
		return { kind = "item", id = a }
	elseif kind == "spell" then
		local spellId = c or (b and tonumber(b)) or a
		if type(spellId) == "number" then
			return { kind = "spell", id = spellId }
		end
	elseif kind == "macro" then
		local name = GetMacroInfo(a)
		if name then
			return { kind = "macro", name = name }
		end
	elseif kind then
		return nil, "eso no se puede poner en la barra (solo objetos, hechizos y macros)"
	end
	return nil
end

local function SetupButtons()
	if InCombatLockdown() then
		pendingSetup = true
		return false
	end
	for _, button in ipairs(buttons) do
		ApplyAction(button)
	end
	ApplyBindings()
	UpdateAll()
	return true
end

--- Pone en el botón lo que hay en el cursor; lo que había queda en el cursor.
local function DropOnButton(button)
	if ClassGroup(button.index) or BarOf(button.index) == CLASS_BAR then
		return -- la barra de clase se arma sola
	end
	if InCombatLockdown() then
		Print("no se puede cambiar la barra en combate.")
		return
	end
	local slot, problem = SlotFromCursor()
	if not slot then
		if problem then
			Print(problem .. ".")
		end
		return
	end
	local old = db.slots[button.index]
	ClearCursor()
	db.slots[button.index] = slot
	ApplyAction(button)
	UpdateButton(button)
	if old then
		Pickup(old)
	end
end

--------------------------------------------------------------------------------
-- Botones
--------------------------------------------------------------------------------

local function ShowTooltip(button)
	local slot = SlotFor(button.index)
	local group = ClassGroup(button.index)
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	if group and group.all then
		GameTooltip:AddLine("Todos los tótems elegidos", 1, 1, 1)
		GameTooltip:AddLine("Cada pulsación pone el siguiente.", 0.8, 0.8, 0.8)
	elseif slot and (slot.kind == "item" or slot.kind == "poison") then
		GameTooltip:SetItemByID(slot.id)
	elseif slot and slot.kind == "spell" then
		GameTooltip:SetSpellByID(slot.id)
	elseif slot then
		GameTooltip:AddLine(slot.name .. " (macro)", 1, 1, 1)
	else
		GameTooltip:AddLine("Vacío", 1, 1, 1)
		GameTooltip:AddLine("Arrastrá acá un objeto, un hechizo o una macro.", 0.8, 0.8, 0.8)
	end
	local bar, n = BarOf(button.index)
	local key = KeyFor(button.index)
	local place = bar == CLASS_BAR and format("Barra de clase, botón %d", n) or format("Barra %d, botón %d", bar, n)
	GameTooltip:AddLine(format("%s. %s", place, key and ("Tecla: " .. key) or "Sin tecla: /barra teclas"), 0.4, 0.8, 1)
	if group then
		if not group.all then
			GameTooltip:AddLine("Clic derecho: elegir " .. group.label:lower(), 0.6, 0.6, 0.6)
		end
	elseif slot then
		GameTooltip:AddLine(db.locked and "Mayús+arrastrar: sacarlo de la barra" or "Arrastrar: sacarlo de la barra",
			0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Selector de la barra de clase (clic derecho)
--------------------------------------------------------------------------------

local picker

local function RefreshClassButtons()
	if InCombatLockdown() then
		pendingSetup = true
		return
	end
	for n = 1, PER_BAR do
		local button = buttons[IndexOf(CLASS_BAR, n)]
		ApplyAction(button)
		UpdateButton(button)
	end
end

local function CreatePicker()
	picker = CreateFrame("Frame", "BarraLibreSelector", UIParent)
	picker:SetFrameStrata("DIALOG")
	picker:SetClampedToScreen(true)
	local background = picker:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.75)
	picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	picker.title:SetPoint("TOPLEFT", 6, -5)
	picker.options = {}
	for i = 1, PER_BAR do
		local option = CreateFrame("Button", nil, picker)
		option:SetSize(BUTTON_SIZE, BUTTON_SIZE)
		option:SetPoint("TOPLEFT", 6 + (i - 1) * (BUTTON_SIZE + GAP), -20)
		option.icon = option:CreateTexture(nil, "ARTWORK")
		option.icon:SetAllPoints()
		option.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		option.mark = option:CreateTexture(nil, "OVERLAY")
		option.mark:SetPoint("TOPLEFT", -2, 2)
		option:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		option.mark:SetPoint("BOTTOMRIGHT", 2, -2)
		option.mark:SetColorTexture(1, 0.82, 0, 0.35)
		option:SetScript("OnClick", function(self)
			local group = picker.group
			db.classChoice[group.key] = self.option.key
			group.chosen = self.option
			picker:Hide()
			-- El botón de "todos" del chamán cambia con cada tótem elegido.
			RefreshClassButtons()
		end)
		option:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if picker.group.items then
				GameTooltip:SetItemByID(self.option.id)
			else
				GameTooltip:SetSpellByID(self.option.id)
			end
			GameTooltip:Show()
		end)
		option:SetScript("OnLeave", function() GameTooltip:Hide() end)
		picker.options[i] = option
	end
	picker:Hide()
	tinsert(UISpecialFrames, "BarraLibreSelector") -- se cierra con Esc
end

local function OpenPicker(button)
	local group = ClassGroup(button.index)
	if not group or group.all or #group.options == 0 then
		return
	end
	if InCombatLockdown() then
		Print("se elige fuera de combate.")
		return
	end
	if picker:IsShown() and picker.group == group then
		picker:Hide()
		return
	end
	picker.group = group
	picker.title:SetText(group.label)
	for i, option in ipairs(picker.options) do
		local data = group.options[i]
		if data then
			option.option = data
			option.icon:SetTexture(group.items and GetItemIcon(data.id) or SpellTexture(data.id))
			option.mark:SetShown(group.chosen == data)
			option:Show()
		else
			option:Hide()
		end
	end
	local count = #group.options
	picker:SetSize(12 + count * (BUTTON_SIZE + GAP) - GAP, BUTTON_SIZE + 26)
	picker:SetScale(db.bars[CLASS_BAR].scale)
	picker:ClearAllPoints()
	if db.bars[CLASS_BAR].vertical then
		picker:SetPoint("LEFT", button, "RIGHT", 6, 0)
	else
		picker:SetPoint("BOTTOM", button, "TOP", 0, 6)
	end
	picker:Show()
end

local function CreateButton(index)
	local bar = BarOf(index)
	local button = CreateFrame("Button", ButtonName(index), bars[bar], "SecureActionButtonTemplate")
	button.index = index
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	-- Con teclas el juego usa el botón al apretar; con el mouse, al soltar: se escuchan los dos.
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:RegisterForDrag("LeftButton")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
	background:SetTexCoord(0.2, 0.8, 0.2, 0.8)

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
	local normal = button:GetNormalTexture()
	normal:ClearAllPoints()
	normal:SetPoint("TOPLEFT", -15, 15)
	normal:SetPoint("BOTTOMRIGHT", 15, -15)
	button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints(button.icon)

	-- Textos por encima del reloj del tiempo de reutilización.
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(button.cooldown:GetFrameLevel() + 2)
	button.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)
	button.hotkey = overlay:CreateFontString(nil, "OVERLAY",
		_G.NumberFontNormalSmallGray and "NumberFontNormalSmallGray" or "GameFontHighlightSmall")
	button.hotkey:SetPoint("TOPRIGHT", -2, -3)
	button.hotkey:SetJustifyH("RIGHT")

	button.bindGlow = overlay:CreateTexture(nil, "OVERLAY")
	button.bindGlow:SetPoint("TOPLEFT", -2, 2)
	button.bindGlow:SetPoint("BOTTOMRIGHT", 2, -2)
	button.bindGlow:SetColorTexture(0.2, 1, 0.4, 0.25)
	button.bindGlow:Hide()

	-- Clic con algo en el cursor: se pone en el botón en vez de usarlo.
	button:SetScript("PreClick", function(self)
		if BarOf(self.index) == CLASS_BAR then
			return
		end
		if GetCursorInfo() and not InCombatLockdown() then
			self:SetAttribute("type", nil)
			self.dropping = true
		end
	end)
	button:SetScript("PostClick", function(self, mouseButton, down)
		if mouseButton == "RightButton" and not down and BarOf(self.index) == CLASS_BAR and not binding then
			OpenPicker(self)
			return
		end
		if self.dropping and not down then
			self.dropping = nil
			DropOnButton(self)
			ApplyAction(self)
		end
	end)
	button:SetScript("OnReceiveDrag", DropOnButton)
	button:SetScript("OnDragStart", function(self)
		if BarOf(self.index) == CLASS_BAR then
			return
		end
		local slot = db.slots[self.index]
		if not slot or binding or InCombatLockdown() then
			return
		end
		if db.locked and not IsShiftKeyDown() then
			return
		end
		db.slots[self.index] = nil
		ApplyAction(self)
		UpdateButton(self)
		Pickup(slot)
	end)
	button:SetScript("OnEnter", function(self)
		if binding then
			hovered = self.index
		end
		ShowTooltip(self)
	end)
	button:SetScript("OnLeave", function(self)
		if hovered == self.index then
			hovered = nil
		end
		GameTooltip:Hide()
	end)
	return button
end

--------------------------------------------------------------------------------
-- Barras
--------------------------------------------------------------------------------

local function LayoutBar(bar)
	local settings = db.bars[bar]
	local frame, grip = bars[bar], grips[bar]
	local count = settings.count
	-- Barra de clase: van seguidos solo los grupos que el personaje conoce.
	local order = {}
	for n = 1, PER_BAR do
		if bar ~= CLASS_BAR or IsActive(IndexOf(bar, n)) then
			order[#order + 1] = n
		end
	end
	if bar == CLASS_BAR then
		count = math.max(1, #order)
	end
	-- "lines": filas de una barra horizontal, o columnas de una vertical.
	local lines = math.max(1, math.min(settings.lines, count))
	local perLine = math.ceil(count / lines)
	local step = BUTTON_SIZE + GAP

	frame:SetScale(settings.scale)
	if settings.vertical then
		frame:SetSize(lines * step - GAP, perLine * step - GAP)
	else
		frame:SetSize(perLine * step - GAP, lines * step - GAP)
	end
	frame:ClearAllPoints()
	frame:SetPoint(settings.point, UIParent, settings.relativePoint, settings.x, settings.y)

	local position = {}
	for place, n in ipairs(order) do
		position[n] = place
	end
	for n = 1, PER_BAR do
		local button = buttons[IndexOf(bar, n)]
		button:ClearAllPoints()
		local place = position[n]
		if place and place <= count then
			local along, across = (place - 1) % perLine, math.floor((place - 1) / perLine)
			if settings.vertical then
				button:SetPoint("TOPLEFT", frame, "TOPLEFT", across * step, -along * step)
			else
				button:SetPoint("TOPLEFT", frame, "TOPLEFT", along * step, -across * step)
			end
			button:Show()
		else
			button:Hide()
		end
	end

	-- La agarradera va a la izquierda de una barra horizontal y arriba de una vertical.
	grip:ClearAllPoints()
	if settings.vertical then
		grip:SetSize(BUTTON_SIZE, 14)
		grip:SetPoint("BOTTOM", frame, "TOP", 0, 4)
	else
		grip:SetSize(14, BUTTON_SIZE)
		grip:SetPoint("RIGHT", frame, "LEFT", -4, 0)
	end
	grip:SetShown(not db.locked)

	local inUse
	if bar == CLASS_BAR then
		inUse = db.classBar and #order > 0
	else
		inUse = bar <= db.numBars
	end
	if inUse and not settings.hidden then
		frame:Show()
	else
		frame:Hide()
	end
end

local function Layout()
	if InCombatLockdown() then
		pendingSetup = true
		return
	end
	for bar = 1, TOTAL_BARS do
		LayoutBar(bar)
	end
end

local function SetOrientation(bar, vertical)
	db.bars[bar].vertical = vertical
	Layout()
end

local function CreateGrip(bar)
	local frame = bars[bar]
	local grip = CreateFrame("Button", "BarraLibreAgarradera" .. bar, frame)
	local texture = grip:CreateTexture(nil, "BACKGROUND")
	texture:SetAllPoints()
	texture:SetColorTexture(0.4, 0.8, 1, 0.35)
	local label = grip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	label:SetText(bar == CLASS_BAR and "C" or bar)
	grip:RegisterForDrag("LeftButton")
	grip:RegisterForClicks("RightButtonUp")
	grip:SetScript("OnDragStart", function()
		if not InCombatLockdown() then
			frame:StartMoving()
		end
	end)
	grip:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		local settings = db.bars[bar]
		local point, _, relativePoint, x, y = frame:GetPoint()
		settings.point, settings.relativePoint, settings.x, settings.y = point, relativePoint, x, y
	end)
	grip:SetScript("OnClick", function()
		if InCombatLockdown() then
			Print("no se puede cambiar la barra en combate.")
			return
		end
		SetOrientation(bar, not db.bars[bar].vertical)
	end)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(format("%s (%s)", bar == CLASS_BAR and "Barra de clase" or ("Barra Libre " .. bar),
			db.bars[bar].vertical and "vertical" or "horizontal"))
		GameTooltip:AddLine("Arrastrar: mover la barra.", 1, 1, 1)
		GameTooltip:AddLine("Clic derecho: horizontal o vertical.", 1, 1, 1)
		GameTooltip:AddLine("/barra bloquear fija las barras y oculta esto.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return grip
end

local function CreateBars()
	for bar = 1, TOTAL_BARS do
		local frame = CreateFrame("Frame", "BarraLibreBarra" .. bar, UIParent)
		frame:SetMovable(true)
		frame:SetClampedToScreen(true)
		bars[bar] = frame
	end
	for index = 1, MAX_BUTTONS do
		buttons[index] = CreateButton(index)
	end
	for bar = 1, TOTAL_BARS do
		grips[bar] = CreateGrip(bar)
	end
	CreatePicker()
end

--------------------------------------------------------------------------------
-- Modo asignar teclas
--------------------------------------------------------------------------------

local function StopBinding()
	if not binding then
		return
	end
	binding = false
	hovered = nil
	binder:Hide()
	bindHint:Hide()
	SetupButtons()
	Print("teclas guardadas.")
end

local function AssignKey(index, key)
	for other, existing in pairs(db.keys) do
		if existing == key and other ~= index then
			db.keys[other] = nil
		end
	end
	local previous = GetBindingAction and GetBindingAction(key) or ""
	if previous ~= "" and not previous:find("^CLICK BarraLibreBoton") then
		local bar, n = BarOf(index)
		Print(format("%s ya hacía \"%s\"; mientras esté la barra, usa el botón %d de la barra %d.", key,
			_G["BINDING_NAME_" .. previous] or previous, n, bar))
	end
	db.keys[index] = key
	ApplyBindings()
	UpdateAll()
end

local function OnBindKey(_, key)
	if key == "ESCAPE" then
		StopBinding()
		return
	end
	if MODIFIER_KEYS[key] then
		return
	end
	if not hovered then
		bindHint.text:SetText("Pasá el mouse por un botón de la barra y apretá la tecla.\n"
			.. "Supr o Retroceso: borrar la tecla.  Esc: terminar.")
		return
	end
	if key == "DELETE" or key == "BACKSPACE" then
		db.keys[hovered] = nil
		ApplyBindings()
		UpdateAll()
		return
	end
	local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
		.. (IsShiftKeyDown() and "SHIFT-" or "") .. key
	AssignKey(hovered, combo)
end

local function CreateBinder()
	binder = CreateFrame("Frame", "BarraLibreAsignador", UIParent)
	binder:SetAllPoints(UIParent)
	binder:SetFrameStrata("DIALOG")
	binder:EnableKeyboard(true)
	binder:SetScript("OnKeyDown", OnBindKey)
	binder:Hide()

	bindHint = CreateFrame("Frame", nil, UIParent)
	bindHint:SetSize(520, 60)
	bindHint:SetPoint("TOP", 0, -120)
	bindHint:SetFrameStrata("DIALOG")
	local background = bindHint:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.6)
	bindHint.text = bindHint:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	bindHint.text:SetPoint("CENTER")
	bindHint:Hide()
end

local function StartBinding()
	if InCombatLockdown() then
		Print("las teclas se asignan fuera de combate.")
		return
	end
	local changed = false
	for bar = 1, db.numBars do
		if db.bars[bar].hidden then
			db.bars[bar].hidden = false
			changed = true
		end
	end
	if changed then
		Layout()
	end
	binding = true
	bindHint.text:SetText("Asignar teclas: pasá el mouse por un botón y apretá una tecla\n"
		.. "(con Mayús, Ctrl o Alt si querés). Supr: borrar.  Esc: terminar.")
	bindHint:Show()
	binder:Show()
	SetupButtons() -- mientras tanto, los botones no se usan al hacer clic
end

local function ToggleBinding()
	if binding then
		StopBinding()
	else
		StartBinding()
	end
end
BarraLibre_ToggleBinding = ToggleBinding

--------------------------------------------------------------------------------
-- Rellenar con consumibles de las bolsas
--------------------------------------------------------------------------------

-- Orden: pociones, vendas, comida y bebida, elixires, frascos, pergaminos, el resto.
local CONSUMABLE_ORDER = { [1] = 1, [7] = 2, [5] = 3, [2] = 4, [3] = 5, [4] = 6, [6] = 7, [8] = 8, [0] = 9 }

local function BagItems()
	local seen, list = {}, {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local itemId = GetContainerItemID(bag, slot)
			if itemId and not seen[itemId] then
				seen[itemId] = true
				list[#list + 1] = itemId
			end
		end
	end
	return list
end

local function AutoFill()
	if InCombatLockdown() then
		Print("no se puede cambiar la barra en combate.")
		return
	end
	local onBar = {}
	for _, slot in pairs(db.slots) do
		if slot.kind == "item" then
			onBar[slot.id] = true
		end
	end
	local candidates = {}
	for order, itemId in ipairs(BagItems()) do
		if not onBar[itemId] then
			local _, _, _, _, _, classId, subClassId = GetItemInfoInstant(itemId)
			local usable = GetItemSpell(itemId) ~= nil
			if itemId == HEARTHSTONE then
				candidates[#candidates + 1] = { id = itemId, rank = 10, order = order }
			elseif classId == 0 and usable then
				candidates[#candidates + 1] = { id = itemId, rank = CONSUMABLE_ORDER[subClassId] or 9, order = order }
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.order < b.order
	end)
	local added = 0
	for _, index in ipairs(ActiveIndexes()) do
		if not db.slots[index] and candidates[1] then
			db.slots[index] = { kind = "item", id = table.remove(candidates, 1).id }
			added = added + 1
		end
	end
	SetupButtons()
	if added > 0 then
		Print(format("agregué %d %s de tus bolsas.", added, added == 1 and "objeto" or "objetos"))
	elseif #candidates > 0 then
		Print("las barras están llenas. Sumá botones (/barra botones <n>) o barras (/barra barras <n>).")
	else
		Print("no encontré pociones, comida ni otros consumibles en las bolsas.")
	end
end

--------------------------------------------------------------------------------
-- Comandos
--------------------------------------------------------------------------------

local function PrintHelp()
	Print("comandos (también /barralibre). Si empiezan con un número, son para esa barra: /barra 2 vertical")
	local lines = {
		"Arrastrá objetos, pociones, hechizos o macros a los botones.",
		"/barra barras <1-6>  -  cuántas barras usar",
		"/barra [barra] horizontal | vertical  -  orientación (también clic derecho en la agarradera)",
		"/barra [barra] botones <1-12>  -  cuántos botones tiene la barra",
		"/barra [barra] filas <n>  -  en cuántas filas (o columnas, si es vertical)",
		"/barra [barra] escala <0.5-2>  -  tamaño",
		"/barra [barra] ocultar  -  ocultar o mostrar (las teclas siguen andando)",
		"/barra [barra] centrar  -  volver a la posición de inicio",
		"/barra teclas  -  asignar teclas: pasá el mouse por un botón y apretá la tecla",
		"/barra [barra] tecla <botón> <tecla>  -  sin mouse: /barra tecla 1 SHIFT-1 (borrar: /barra tecla 1 borrar)",
		"/barra auto  -  llenar los botones vacíos con consumibles de las bolsas",
		"/barra [barra] poner <botón> <objeto>  -  nombre del objeto o Mayús+clic en él",
		"/barra [barra] quitar <botón | todo>  -  vaciar",
		"/barra bloquear  -  fijar las barras (para sacar algo: Mayús+arrastrar)",
		"/barra clase  -  mostrar u ocultar la barra de clase (tótems, auras, aspectos...)",
		"/barra clase vertical | escala 1.2 | tecla 1 F5 | centrar  -  lo mismo que las otras barras",
		"En la barra de clase: clic derecho en un botón para elegir qué usa.",
	}
	for _, line in ipairs(lines) do
		DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
	end
end

local function ItemFromText(text)
	local id = text:match("item:(%d+)") or text:match("^#?(%d+)$")
	if id then
		return tonumber(id)
	end
	local name = text:match("%[(.-)%]") or text
	return (GetItemInfoInstant(name))
end

local function NotInCombat()
	if InCombatLockdown() then
		Print("no se puede cambiar la barra en combate.")
		return false
	end
	return true
end

local function HandleSlash(input)
	local raw = strtrim(input or "")
	-- Un número al principio elige la barra: "/barra 2 vertical". "clase" es la barra de clase.
	local bar = 1
	local classText, afterClass = raw:match("^([Cc][Ll][Aa][Ss][Ee])%s*(.*)$")
	if classText then
		bar = CLASS_BAR
		raw = afterClass
		if raw == "" then
			if NotInCombat() then
				db.classBar = not db.classBar
				Layout()
				ApplyBindings()
				Print(db.classBar and "barra de clase visible." or "barra de clase oculta. /barra clase para verla.")
			end
			return
		end
	else
		local barText, afterBar = raw:match("^(%d+)%s+(.+)$")
		if barText then
			bar = tonumber(barText)
			raw = afterBar
			if bar == CLASS_BAR then
				bar = CLASS_BAR
			elseif bar < 1 or bar > MAX_BARS then
				Print(format("las barras van de 1 a %d (la de clase: /barra clase).", MAX_BARS))
				return
			end
		end
	end
	local settings = db.bars[bar]
	local command, rest = raw:match("^(%S*)%s*(.-)$")
	command = (command or ""):lower()
	local number = tonumber(rest)

	local keyButton, keyName = rest:match("^(%d+)%s+(%S+)$")
	if bar == CLASS_BAR and (command == "botones" or command == "poner" or command == "quitar"
		or command == "vaciar" or command == "limpiar") then
		Print("la barra de clase se arma sola con lo que conoce tu personaje. Clic derecho en un botón para elegir.")
		return
	end
	if (command == "tecla" or command == "teclas") and keyButton then
		-- Sin mouse (por ejemplo, con el mando): /barra tecla 3 SHIFT-1
		keyButton = tonumber(keyButton)
		local limit = bar == CLASS_BAR and #classGroups or settings.count
		if keyButton < 1 or keyButton > limit then
			Print(format("la barra %s tiene botones del 1 al %d.", bar == CLASS_BAR and "de clase" or bar, limit))
		elseif not NotInCombat() then
			return
		elseif keyName:lower() == "borrar" or keyName:lower() == "ninguna" then
			db.keys[IndexOf(bar, keyButton)] = nil
			ApplyBindings()
			UpdateAll()
			Print(format("barra %d, botón %d: sin tecla.", bar, keyButton))
		else
			local key = keyName:lower():gsub("^mayús%-", "shift-"):gsub("^mayus%-", "shift-"):upper()
			AssignKey(IndexOf(bar, keyButton), key)
			Print(format("barra %d, botón %d: %s.", bar, keyButton, key))
		end
	elseif command == "teclas" or command == "tecla" or command == "atajos" then
		ToggleBinding()
	elseif command == "auto" or command == "rellenar" then
		AutoFill()
	elseif command == "barras" then
		if number and NotInCombat() then
			db.numBars = math.max(1, math.min(MAX_BARS, math.floor(number)))
			Layout()
			ApplyBindings()
		end
		Print(format("%d %s.", db.numBars, db.numBars == 1 and "barra" or "barras"))
	elseif command == "vertical" or command == "horizontal" then
		if NotInCombat() then
			if bar > db.numBars then
				db.numBars = bar
			end
			SetOrientation(bar, command == "vertical")
			ApplyBindings()
			Print(format("barra %d %s.", bar, command))
		end
	elseif command == "poner" then
		local button, what = rest:match("^(%d+)%s+(.+)$")
		button = tonumber(button)
		local itemId = what and ItemFromText(what)
		if not button or button < 1 or button > settings.count then
			Print("ejemplo: /barra poner 3 Poción de sanación (o Mayús+clic en el objeto)")
		elseif not itemId then
			Print("no encontré ese objeto. Probá con Mayús+clic en el objeto de tus bolsas.")
		elseif NotInCombat() then
			db.slots[IndexOf(bar, button)] = { kind = "item", id = itemId }
			SetupButtons()
		end
	elseif command == "quitar" or command == "vaciar" or command == "limpiar" then
		if not NotInCombat() then
			return
		elseif rest == "todo" or rest == "todos" then
			for n = 1, PER_BAR do
				db.slots[IndexOf(bar, n)] = nil
			end
			SetupButtons()
		elseif number and db.slots[IndexOf(bar, number)] then
			db.slots[IndexOf(bar, number)] = nil
			SetupButtons()
		else
			Print("ejemplo: /barra quitar 3, o /barra quitar todo")
		end
	elseif command == "botones" then
		if number and NotInCombat() then
			settings.count = math.max(1, math.min(PER_BAR, math.floor(number)))
			Layout()
			ApplyBindings()
		end
		Print(format("barra %d: %d botones.", bar, settings.count))
	elseif command == "filas" or command == "columnas" or command == "lineas" or command == "líneas" then
		if number and number >= 1 and NotInCombat() then
			settings.lines = math.min(PER_BAR, math.floor(number))
			Layout()
		end
		Print(format("barra %d: %d %s.", bar, settings.lines, settings.vertical and "columnas" or "filas"))
	elseif command == "escala" or command == "tamaño" then
		if number and NotInCombat() then
			settings.scale = math.max(0.5, math.min(2, number))
			Layout()
		end
		Print(format("barra %d: escala %.2f.", bar, settings.scale))
	elseif command == "bloquear" or command == "candado" or command == "desbloquear" then
		if NotInCombat() then
			db.locked = not db.locked
			Layout()
			Print(db.locked and "barras fijas. Para sacar algo: Mayús+arrastrar."
				or "barras libres: movelas con la agarradera.")
		end
	elseif command == "ocultar" or command == "mostrar" then
		if NotInCombat() then
			settings.hidden = not settings.hidden
			Layout()
			Print(settings.hidden and format("barra %d oculta (las teclas siguen andando).", bar)
				or format("barra %d visible.", bar))
		end
	elseif command == "centrar" then
		if NotInCombat() then
			local base = BarDefaults(bar)
			settings.point, settings.relativePoint, settings.x, settings.y = base.point, base.relativePoint, base.x, base.y
			Layout()
		end
	else
		PrintHelp()
	end
end

SLASH_BARRALIBRE1 = "/barra"
SLASH_BARRALIBRE2 = "/barralibre"
SlashCmdList.BARRALIBRE = function(input)
	if not db then
		return
	end
	local ok, problem = pcall(HandleSlash, input)
	if not ok then
		Print("algo falló: " .. tostring(problem))
	end
end

--------------------------------------------------------------------------------
-- Eventos
--------------------------------------------------------------------------------

local function CopyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = {}
				CopyDefaults(target[key], value)
			else
				target[key] = value
			end
		end
	end
end

local function InitDB()
	BarraLibreDB = BarraLibreDB or {}
	db = BarraLibreDB
	CopyDefaults(db, DEFAULTS)
	for bar = 1, TOTAL_BARS do
		db.bars[bar] = db.bars[bar] or {}
		CopyDefaults(db.bars[bar], BarDefaults(bar))
	end
	db.numBars = math.max(1, math.min(MAX_BARS, db.numBars))
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "UPDATE_BINDINGS",
	"GET_ITEM_INFO_RECEIVED", "UPDATE_MACROS", "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_USABLE", "SPELLS_CHANGED",
	"LEARNED_SPELL_IN_TAB" }) do
	pcall(events.RegisterEvent, events, event)
end

local refreshQueued = false
local function QueueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	C_Timer.After(0.2, function()
		refreshQueued = false
		UpdateAll()
	end)
end

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		InitDB()
		CreateBars()
		CreateBinder()
		Layout()
		SetupButtons()
	elseif event == "PLAYER_LOGIN" then
		ScanClass()
		Layout()
		SetupButtons()
		if not next(db.slots) then
			Print("arrastrá pociones u objetos a la barra, o escribí /barra auto. /barra teclas para elegir las teclas,"
				.. " /barra barras <n> para tener más barras.")
		end
	elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
		-- Aprendiste algo (o un rango nuevo): la barra de clase se rearma.
		ScanClass()
		Layout()
		SetupButtons()
	elseif event == "PLAYER_REGEN_DISABLED" then
		if picker:IsShown() then
			picker:Hide()
		end
		if binding then
			-- El juego no deja asignar teclas en combate: se guarda lo hecho.
			StopBinding()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingSetup then
			pendingSetup = false
			ScanClass()
			Layout()
			SetupButtons()
		end
	elseif event == "BAG_UPDATE_DELAYED" and select(2, UnitClass("player")) == "ROGUE" then
		-- Venenos: lo que hay en las bolsas cambia la barra de clase.
		ScanClass()
		if InCombatLockdown() then
			pendingSetup = true
			QueueRefresh()
		else
			Layout()
			SetupButtons()
		end
	elseif event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
		UpdateCooldowns()
	elseif event == "UPDATE_MACROS" then
		if not InCombatLockdown() then
			SetupButtons()
		else
			QueueRefresh()
		end
	else
		QueueRefresh()
	end
end)

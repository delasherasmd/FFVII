-- Barra Libre: barras propias para objetos, pociones, hechizos y macros que se
-- usan de vez en cuando, con teclas del teclado. Funciona aunque juegues con
-- mando (el modo mando del juego o ConsolePort): es independiente de las barras
-- de acción y de las asignaciones del mando.
-- Hasta 6 barras, cada una horizontal o vertical.
-- WoW Classic Era (1.15) y WoW Forever (1.60).

local ADDON_NAME = ...
local PREFIX = "|cff66ddffBarra Libre:|r "
local MAX_BARS = 6
local PER_BAR = 12
local MAX_BUTTONS = MAX_BARS * PER_BAR
local BUTTON_SIZE = 36
local GAP = 4
local HEARTHSTONE = 6948

BINDING_HEADER_BARRALIBRE = "Barra Libre"
BINDING_NAME_BARRALIBRE_TECLAS = "Asignar teclas a la Barra Libre"
for index = 1, MAX_BUTTONS do
	local bar, n = math.floor((index - 1) / PER_BAR) + 1, (index - 1) % PER_BAR + 1
	_G["BINDING_NAME_CLICK BarraLibreBoton" .. index .. ":LeftButton"] = format("Barra %d, botón %d", bar, n)
end

-- Dónde aparece cada barra la primera vez.
local BAR_DEFAULTS = {
	{ vertical = false, point = "BOTTOM", x = 0, y = 200 },
	{ vertical = false, point = "BOTTOM", x = 0, y = 245 },
	{ vertical = true, point = "RIGHT", x = -60, y = 0 },
	{ vertical = true, point = "LEFT", x = 60, y = 0 },
	{ vertical = false, point = "BOTTOM", x = 0, y = 290 },
	{ vertical = false, point = "BOTTOM", x = 0, y = 335 },
}

local DEFAULTS = {
	numBars = 1,       -- cuántas barras se usan
	locked = false,    -- con candado, para sacar algo hay que arrastrar con Mayús
	bars = {},         -- por barra: count, vertical, lines, scale, point, x, y, hidden
	slots = {},        -- [botón] = {kind = "item" | "spell" | "macro", id = número, name = nombre de macro}
	keys = {},         -- [botón] = "SHIFT-1"
}

local function BarDefaults(bar)
	local base = BAR_DEFAULTS[bar]
	return { count = bar == 1 and 10 or 6, vertical = base.vertical, lines = 1, scale = 1,
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

--- ¿El botón está en uso? (su barra está entre las elegidas y él entre los botones de la barra)
local function IsActive(index)
	local bar, n = BarOf(index)
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

local function SlotIcon(slot)
	if not slot then
		return nil
	end
	if slot.kind == "item" then
		return GetItemIcon(slot.id)
	elseif slot.kind == "spell" then
		return SpellTexture(slot.id)
	elseif slot.kind == "macro" then
		local _, icon = GetMacroInfo(slot.name)
		return icon
	end
end

--- Lo que hace el botón al usarlo (solo fuera de combate).
local function ApplyAction(button)
	local slot = db.slots[button.index]
	button:SetAttribute("item", nil)
	button:SetAttribute("spell", nil)
	button:SetAttribute("macro", nil)
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
	local slot = db.slots[button.index]
	local start, duration
	if slot and slot.kind == "item" then
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
	local slot = db.slots[button.index]
	local icon = SlotIcon(slot)
	button.icon:SetTexture(icon)
	button.icon:SetShown(icon ~= nil)
	button.icon:SetDesaturated(false)
	button.icon:SetVertexColor(1, 1, 1)
	button.count:SetText("")
	if slot and slot.kind == "item" then
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
	local slot = db.slots[button.index]
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	if slot and slot.kind == "item" then
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
	GameTooltip:AddLine(format("Barra %d, botón %d. %s", bar, n,
		key and ("Tecla: " .. key) or "Sin tecla: /barra teclas"), 0.4, 0.8, 1)
	if slot then
		GameTooltip:AddLine(db.locked and "Mayús+arrastrar: sacarlo de la barra" or "Arrastrar: sacarlo de la barra",
			0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
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
		if GetCursorInfo() and not InCombatLockdown() then
			self:SetAttribute("type", nil)
			self.dropping = true
		end
	end)
	button:SetScript("PostClick", function(self, _, down)
		if self.dropping and not down then
			self.dropping = nil
			DropOnButton(self)
			ApplyAction(self)
		end
	end)
	button:SetScript("OnReceiveDrag", DropOnButton)
	button:SetScript("OnDragStart", function(self)
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

	for n = 1, PER_BAR do
		local button = buttons[IndexOf(bar, n)]
		button:ClearAllPoints()
		if n <= count then
			local along, across = (n - 1) % perLine, math.floor((n - 1) / perLine)
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

	if bar <= db.numBars and not settings.hidden then
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
	for bar = 1, MAX_BARS do
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
	label:SetText(bar)
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
		GameTooltip:AddLine(format("Barra Libre %d (%s)", bar, db.bars[bar].vertical and "vertical" or "horizontal"))
		GameTooltip:AddLine("Arrastrar: mover la barra.", 1, 1, 1)
		GameTooltip:AddLine("Clic derecho: horizontal o vertical.", 1, 1, 1)
		GameTooltip:AddLine("/barra bloquear fija las barras y oculta esto.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return grip
end

local function CreateBars()
	for bar = 1, MAX_BARS do
		local frame = CreateFrame("Frame", "BarraLibreBarra" .. bar, UIParent)
		frame:SetMovable(true)
		frame:SetClampedToScreen(true)
		bars[bar] = frame
	end
	for index = 1, MAX_BUTTONS do
		buttons[index] = CreateButton(index)
	end
	for bar = 1, MAX_BARS do
		grips[bar] = CreateGrip(bar)
	end
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
	-- Un número al principio elige la barra: "/barra 2 vertical".
	local barText, afterBar = raw:match("^(%d+)%s+(.+)$")
	local bar = 1
	if barText then
		bar = tonumber(barText)
		raw = afterBar
		if bar < 1 or bar > MAX_BARS then
			Print(format("las barras van de 1 a %d.", MAX_BARS))
			return
		end
	end
	local settings = db.bars[bar]
	local command, rest = raw:match("^(%S*)%s*(.-)$")
	command = (command or ""):lower()
	local number = tonumber(rest)

	local keyButton, keyName = rest:match("^(%d+)%s+(%S+)$")
	if (command == "tecla" or command == "teclas") and keyButton then
		-- Sin mouse (por ejemplo, con el mando): /barra tecla 3 SHIFT-1
		keyButton = tonumber(keyButton)
		if keyButton < 1 or keyButton > settings.count then
			Print(format("la barra %d tiene botones del 1 al %d.", bar, settings.count))
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
	for bar = 1, MAX_BARS do
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
	"GET_ITEM_INFO_RECEIVED", "UPDATE_MACROS", "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_USABLE" }) do
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
		SetupButtons()
		if not next(db.slots) then
			Print("arrastrá pociones u objetos a la barra, o escribí /barra auto. /barra teclas para elegir las teclas,"
				.. " /barra barras <n> para tener más barras.")
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if binding then
			-- El juego no deja asignar teclas en combate: se guarda lo hecho.
			StopBinding()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingSetup then
			pendingSetup = false
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

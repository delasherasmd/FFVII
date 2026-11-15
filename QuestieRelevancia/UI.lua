-- Ventana de Questie Relevancia.

local _, QR = ...

local ROWS = 14
local ROW_HEIGHT = 22
local WIDTH, HEIGHT = 760, 540
local LIST_TOP = -136

local function Icon(path, size)
	size = size or 16
	return format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", path, size, size)
end

local ICON_PATHS = {
	historia = "Interface\\Icons\\INV_Misc_Book_09",
	oro = "Interface\\Icons\\INV_Misc_Coin_01",
	equipo = "Interface\\Icons\\INV_Sword_04",
	mazmorra = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
}
local ICONS = {
	historia = Icon(ICON_PATHS.historia),
	xp = "|cff9d8cffXP|r",
	oro = Icon(ICON_PATHS.oro),
	equipo = Icon(ICON_PATHS.equipo),
	mazmorra = Icon(ICON_PATHS.mazmorra),
	relleno = "|cff808080relleno|r",
	entregar = "|TInterface\\AddOns\\Questie\\Icons\\complete.blp:16:16|t",
}
QR.ICONS = ICONS

local STATUS_ICONS = {
	available = "|TInterface\\AddOns\\Questie\\Icons\\available.blp:14:14|t",
	blocked = "|TInterface\\AddOns\\Questie\\Icons\\available_gray.blp:14:14|t",
	log = "|TInterface\\AddOns\\Questie\\Icons\\incomplete.blp:14:14|t",
	done = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t",
}
local STATUS_TEXT = {
	available = "Disponible", blocked = "Todavía no disponible", log = "En tu registro", done = "Ya la hiciste",
}

local function ClassIcon(classFile, size)
	local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
	if not coords then
		return "|cffffd100C|r"
	end
	size = size or 16
	return format("|TInterface\\WorldStateFrame\\Icons-Classes:%d:%d:0:0:256:256:%d:%d:%d:%d|t",
		size, size, coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
end

local DIFFICULTY_COLORS = {
	red = { 1, 0.1, 0.1 },
	orange = { 1, 0.5, 0.25 },
	yellow = { 1, 1, 0 },
	green = { 0.25, 0.75, 0.25 },
	grey = { 0.5, 0.5, 0.5 },
}

local SLOT_NAMES = {
	[1] = "Cabeza", [2] = "Cuello", [3] = "Hombros", [5] = "Pecho", [6] = "Cintura", [7] = "Piernas",
	[8] = "Pies", [9] = "Muñecas", [10] = "Manos", [11] = "Dedo", [12] = "Dedo", [13] = "Abalorio",
	[14] = "Abalorio", [15] = "Espalda", [16] = "Mano principal", [17] = "Mano secundaria", [18] = "A distancia",
}

local TABS = {
	{ key = "log", name = "Mis misiones" },
	{ key = "recomendadas", name = "Recomendadas" },
	{ key = "resto", name = "El resto" },
	{ key = "nivel", name = "Por nivel" },
	{ key = "mazmorra", name = "Mazmorra" },
	{ key = "equipo", name = "Equipo" },
}

local CATEGORY_FILTERS = {
	{ key = "todas", label = "Todas" },
	{ key = "historia", label = "Historia" },
	{ key = "xp", label = "XP" },
	{ key = "oro", label = "Oro" },
	{ key = "equipo", label = "Equipo" },
	{ key = "mazmorra", label = "Mazmorra" },
	{ key = "clase", label = "Clase" },
	{ key = "relleno", label = "Relleno" },
}

local DUNGEON_FILTERS = {
	{ key = "mio", label = "Para mi nivel" },
	{ key = "todas", label = "Todas" },
}

local GEAR_FILTERS = {
	{ key = "todas", label = "Todas las ranuras" },
	{ key = "mejorar", label = "Para mejorar" },
	{ key = "aldia", label = "Al día" },
}

local DESCRIPTIONS = {
	log = "Las misiones que tomaste, de la más conveniente a la menos. Las listas para entregar van primero.",
	recomendadas = "Para tomar ahora: de tu zona, de tu facción y de un nivel adecuado. Las de clase, siempre.",
	resto = "Las demás misiones disponibles, de otras zonas o niveles.",
}

local EMPTY_TEXT = {
	log = "No tenés misiones en el registro.",
	recomendadas = "No hay misiones recomendadas para tu zona y nivel. Mirá en \"El resto\".",
	resto = "No hay más misiones disponibles según Questie.",
	nivel = "No hay misiones en este rango con estos filtros.",
	mazmorra = "No hay mazmorras con misiones para tu nivel. Probá con \"Todas\".",
	equipo = "No hay ranuras con este filtro.",
}

--------------------------------------------------------------------------------
-- Utilidades compartidas
--------------------------------------------------------------------------------

function QR.ScoreColor(score)
	if score >= 80 then return 0.1, 1, 0.1 end
	if score >= 60 then return 0.6, 1, 0.2 end
	if score >= 40 then return 1, 0.85, 0.1 end
	if score >= 20 then return 1, 0.55, 0.2 end
	return 0.6, 0.6, 0.6
end

function QR.Money(copper)
	copper = math.floor(copper or 0)
	local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if gold > 0 then parts[#parts + 1] = "|cffffd700" .. gold .. "o|r" end
	if silver > 0 then parts[#parts + 1] = "|cffc7c7cf" .. silver .. "p|r" end
	if rest > 0 or #parts == 0 then parts[#parts + 1] = "|cffeda55f" .. rest .. "c|r" end
	return table.concat(parts, " ")
end

--- Íconos de las categorías de una misión. size: 16 en la ventana, 12 en el seguimiento.
function QR.TagIcons(result, size)
	size = size or 16
	local function I(key)
		return ICON_PATHS[key] and Icon(ICON_PATHS[key], size) or ICONS[key]
	end
	local icons = {}
	if result.complete == 1 then
		icons[#icons + 1] = format("|TInterface\\AddOns\\Questie\\Icons\\complete.blp:%d:%d|t", size, size)
	end
	if result.tags.historia then icons[#icons + 1] = I("historia") end
	if result.tags.xp then icons[#icons + 1] = ICONS.xp end
	if result.tags.oro then icons[#icons + 1] = I("oro") end
	if result.tags.equipo then icons[#icons + 1] = I("equipo") end
	if result.tags.mazmorra then icons[#icons + 1] = I("mazmorra") end
	if result.tags.clase then icons[#icons + 1] = ClassIcon(QR.context and QR.context.classFile, size) end
	if result.tags.relleno and #icons == 0 and size >= 16 then icons[#icons + 1] = ICONS.relleno end
	return table.concat(icons, " ")
end

--- Ficha de una misión: por qué tiene ese puntaje y cómo sigue la cadena.
function QR.QuestTooltip(owner, result)
	local D = QR.Data
	local color = DIFFICULTY_COLORS[result.difficulty]
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(result.name, color[1], color[2], color[3])
	GameTooltip:AddLine(format("Puntaje: %d/100", result.score), QR.ScoreColor(result.score))
	local zoneName = D.ZoneName(result.zone)
	local levelDiff = result.level - (QR.context and QR.context.level or result.level)
	GameTooltip:AddLine(format("Nivel %d (requiere %d, %s%d respecto de tu nivel)%s", result.level, result.requiredLevel,
		levelDiff >= 0 and "+" or "", levelDiff, zoneName ~= "" and (" - " .. zoneName) or ""), 1, 1, 1)
	if result.complete == 1 then
		GameTooltip:AddLine("Lista para entregar", 0.2, 1, 0.2)
	elseif result.complete == -1 then
		GameTooltip:AddLine("Fallida", 1, 0.2, 0.2)
	elseif result.status and STATUS_TEXT[result.status] then
		GameTooltip:AddLine(STATUS_TEXT[result.status], 0.8, 0.8, 0.8)
	end

	GameTooltip:AddLine(" ")
	local parts = result.parts
	if parts.xp > 0 then
		GameTooltip:AddDoubleLine(ICONS.xp .. " Experiencia", format("%d XP", result.xp), 1, 1, 1, 1, 1, 1)
	end
	if result.chainTotal > 1 then
		GameTooltip:AddDoubleLine(ICONS.historia .. " Historia", format("paso %d de %d", result.step, result.chainTotal),
			1, 1, 1, 1, 1, 1)
	end
	if parts.cadena > 0 then
		GameTooltip:AddDoubleLine("    Lo que sigue en la cadena", format("%d%%", parts.cadena * 100 + 0.5), 1, 1, 1, 1, 1, 1)
	end
	if parts.equipo > 0 then
		local slot = SLOT_NAMES[result.gearSlot] or "equipo"
		local gain = result.gearGain and format("+%d niveles", result.gearGain) or "ranura vacía"
		GameTooltip:AddDoubleLine(ICONS.equipo .. " Mejora tu equipo", format("%s (%s)", gain, slot), 1, 1, 1, 1, 1, 1)
	end
	if result.money > 0 or result.sell > 0 then
		local text = result.money > 0 and QR.Money(result.money) or ""
		if result.sell > 0 then
			text = text .. (text ~= "" and " + " or "") .. QR.Money(result.sell) .. " al vender"
		end
		GameTooltip:AddDoubleLine(ICONS.oro .. " Oro", text, 1, 1, 1, 1, 1, 1)
	end
	if parts.clase > 0 then
		GameTooltip:AddLine(ClassIcon(QR.context and QR.context.classFile) .. " Misión de clase", 1, 1, 1)
	end
	if parts.mazmorra > 0 then
		GameTooltip:AddLine(ICONS.mazmorra .. " Mazmorra o banda", 1, 1, 1)
	end
	if result.tags.relleno then
		GameTooltip:AddLine("Relleno: misión suelta, sin cadena", 0.6, 0.6, 0.6)
	end

	local steps = QR.Index.NextSteps(result.id, 4, D.IsEligible)
	if #steps > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Sigue con:", 1, 0.82, 0)
		for _, questId in ipairs(steps) do
			GameTooltip:AddLine("  " .. D.QuestName(questId), 0.9, 0.9, 0.9)
		end
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(result.inLog and "Clic: abrir en el registro de misiones" or "Clic: ver la zona en el mapa",
		0.5, 0.8, 1)
	GameTooltip:AddLine("Clic derecho: catálogo de todo lo que da la cadena", 0.5, 0.8, 1)
	GameTooltip:Show()
end

local function ItemText(itemId, itemLevel, size)
	if not itemId then
		return "|cff808080(vacía)|r"
	end
	local D = QR.Data
	local fileId = D.ItemIcon(itemId)
	local icon = fileId and format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t ", fileId, size, size) or ""
	local quality = D.ItemQuality(itemId)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	local name = D.ItemName(itemId)
	if color and color.hex then
		name = color.hex .. name .. "|r"
	end
	return format("%s%s%s", icon, name, itemLevel and format(" |cffaaaaaa(%d)|r", itemLevel) or "")
end

local function GearTooltip(owner, row)
	local D = QR.Data
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(row.name, 1, 0.82, 0)
	if row.notApplicable then
		GameTooltip:AddLine("No aplica: llevás un arma a dos manos.", 0.8, 0.8, 0.8)
		GameTooltip:Show()
		return
	end
	GameTooltip:AddLine("Llevás: " .. ItemText(row.item and row.item.itemId, row.have, 14), 1, 1, 1)
	if row.ideal then
		GameTooltip:AddLine("Ideal de misión: " .. ItemText(row.ideal.itemId, row.ideal.itemLevel, 14), 1, 1, 1)
		if row.unknown then
			GameTooltip:AddLine("Todavía no cargó el nivel de lo que llevás.", 0.8, 0.8, 0.8)
		elseif row.gain and row.gain > 0 then
			GameTooltip:AddLine(format("Te faltan %d niveles de objeto", row.gain), 1, 0.5, 0.2)
		else
			GameTooltip:AddLine("Al día", 0.3, 1, 0.3)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Lo da:", 1, 0.82, 0)
		for i = 1, math.min(3, #row.quests) do
			local questId = row.quests[i]
			local zone = D.ZoneName(D.QuestZone(questId))
			GameTooltip:AddDoubleLine(format("[%d] %s", D.Quest(questId, "questLevel") or 0, D.QuestName(questId)),
				zone, 1, 1, 1, 0.7, 0.7, 0.7)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Clic: ver la zona en el mapa. Clic derecho: catálogo de la cadena.", 0.5, 0.8, 1)
	else
		GameTooltip:AddLine("No hay premios de misión para esta ranura a tu nivel.", 0.8, 0.8, 0.8)
	end
	GameTooltip:Show()
end

local function DungeonTooltip(owner, entry)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(entry.name, 1, 0.82, 0)
	GameTooltip:AddLine(format("Misiones de nivel %d a %d", entry.minLevel, entry.maxLevel), 1, 1, 1)
	GameTooltip:AddLine(format("Hechas: %d de %d", entry.done, entry.total), 1, 1, 1)
	if entry.forYou then
		GameTooltip:AddLine("Buena para tu nivel", 0.3, 1, 0.3)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Clic: preparar la mazmorra (misiones en orden)", 0.5, 0.8, 1)
	GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Filas
--------------------------------------------------------------------------------

local function CreateRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 20, LIST_TOP - (index - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT", -42, 0)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	row.score = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.score:SetPoint("LEFT", 0, 0)
	row.score:SetWidth(44)
	row.score:SetJustifyH("RIGHT")

	row.icons = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.icons:SetPoint("LEFT", row.score, "RIGHT", 10, 0)
	row.icons:SetWidth(126)
	row.icons:SetJustifyH("LEFT")

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("LEFT", row.icons, "RIGHT", 6, 0)
	row.name:SetWidth(290)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.zone:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
	row.zone:SetWidth(150)
	row.zone:SetJustifyH("LEFT")
	row.zone:SetWordWrap(false)

	row.chain = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.chain:SetPoint("RIGHT", 0, 0)
	row.chain:SetWidth(50)
	row.chain:SetJustifyH("RIGHT")

	row:SetScript("OnEnter", function(self)
		if self.result then
			QR.QuestTooltip(self, self.result)
		elseif self.gearRow then
			GearTooltip(self, self.gearRow)
		elseif self.dungeon then
			DungeonTooltip(self, self.dungeon)
		end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnClick", function(self, mouseButton)
		if self.result then
			if mouseButton == "RightButton" then
				QR.ShowCatalog(self.result.id)
			else
				QR.Data.ShowQuest(self.result)
			end
		elseif self.gearRow and self.gearRow.quests then
			local questId = self.gearRow.quests[1]
			if mouseButton == "RightButton" then
				QR.ShowCatalog(questId)
			else
				QR.Data.ShowQuest({ id = questId, name = QR.Data.QuestName(questId), zone = QR.Data.QuestZone(questId) })
			end
		elseif self.dungeon then
			QR.selectedDungeon = self.dungeon.dungeon
			parent:Update()
		end
	end)
	return row
end

local function ClearRow(row)
	row.result, row.gearRow, row.dungeon = nil, nil, nil
	row.score:SetText("")
	row.icons:SetText("")
	row.name:SetText("")
	row.zone:SetText("")
	row.chain:SetText("")
	row.name:SetTextColor(1, 0.82, 0)
end

local function SetQuestRow(row, result, showStatus)
	row.result = result
	row.score:SetText(result.score)
	row.score:SetTextColor(QR.ScoreColor(result.score))
	local icons = QR.TagIcons(result)
	if showStatus and result.status and STATUS_ICONS[result.status] then
		icons = STATUS_ICONS[result.status] .. " " .. icons
	end
	row.icons:SetText(icons)
	local color = DIFFICULTY_COLORS[result.difficulty]
	local prefix = result.role == "preparar" and "|cffaaaaaaPreparar:|r " or ""
	row.name:SetText(format("%s[%d] %s", prefix, result.level, result.name))
	row.name:SetTextColor(color[1], color[2], color[3])
	row.zone:SetText(QR.Data.ZoneName(result.zone))
	row.chain:SetText(result.chainTotal > 1 and format("%d/%d", result.step, result.chainTotal) or "")
end

local function SetHeaderRow(row, entry)
	row.name:SetText(entry.text)
	row.name:SetTextColor(1, 0.82, 0)
	row.score:SetText("")
end

local function SetDungeonRow(row, entry)
	row.dungeon = entry
	row.score:SetText(format("%d-%d", entry.minLevel, entry.maxLevel))
	row.score:SetTextColor(1, 1, 1)
	row.icons:SetText(ICONS.mazmorra .. (entry.forYou and " |cff20ff20para vos|r" or ""))
	row.name:SetText(entry.name)
	if entry.forYou then
		row.name:SetTextColor(0.3, 1, 0.3)
	else
		row.name:SetTextColor(0.9, 0.9, 0.9)
	end
	row.zone:SetText(QR.Data.ZoneName(entry.dungeon.parentZone))
	row.chain:SetText(format("%d/%d", entry.done, entry.total))
end

local function SetGearRow(row, gearRow)
	row.gearRow = gearRow
	if gearRow.notApplicable then
		row.score:SetText("|cff808080-|r")
	elseif gearRow.unknown then
		row.score:SetText("|cff808080?|r")
	elseif gearRow.gain and gearRow.gain > 0 then
		row.score:SetText(format("|cffff8040+%d|r", gearRow.gain))
	elseif gearRow.ideal then
		row.score:SetText("|cff20ff20ok|r")
	else
		row.score:SetText("")
	end
	local have = gearRow.item and QR.Data.ItemIcon(gearRow.item.itemId)
	local ideal = gearRow.ideal and QR.Data.ItemIcon(gearRow.ideal.itemId)
	row.icons:SetText(format("%s %s %s", have and Icon(have, 18) or "", ideal and "|cffaaaaaa>|r" or "",
		ideal and Icon(ideal, 18) or ""))
	row.name:SetText(gearRow.name .. ": " .. ItemText(gearRow.item and gearRow.item.itemId, gearRow.have, 14))
	row.name:SetTextColor(1, 1, 1)
	if gearRow.notApplicable then
		row.zone:SetText("|cff808080no aplica (dos manos)|r")
	elseif gearRow.ideal then
		row.zone:SetText(ItemText(gearRow.ideal.itemId, gearRow.ideal.itemLevel, 14))
	else
		row.zone:SetText("|cff808080sin premio de misión|r")
	end
end

--------------------------------------------------------------------------------
-- Ventana
--------------------------------------------------------------------------------

local function SmallButton(parent, width, text)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	button:GetFontString():SetFontObject("GameFontNormalSmall")
	return button
end

function QR.CreateWindow()
	local frame = CreateFrame("Frame", "QuestieRelevanciaFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	frame:Hide()
	tinsert(UISpecialFrames, "QuestieRelevanciaFrame") -- se cierra con Esc

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -18)
	title:SetText("Questie Relevancia")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local db = QR.DB()

	local function ResetScroll()
		FauxScrollFrame_SetOffset(frame.scroll, 0)
		frame.scroll:SetVerticalScroll(0)
	end

	-- Pestañas
	frame.tabs = {}
	for i, tab in ipairs(TABS) do
		local button = SmallButton(frame, 116, tab.name)
		button:SetHeight(24)
		button:SetPoint("TOPLEFT", 20 + (i - 1) * 120, -42)
		button:SetScript("OnClick", function()
			db.tab = tab.key
			ResetScroll()
			frame:Update()
		end)
		button.key = tab.key
		button.label = tab.name
		frame.tabs[i] = button
	end

	-- Fila de filtros: cambia según la pestaña.
	frame.filters = {}
	for i = 1, 8 do
		local button = SmallButton(frame, 84, "")
		button:SetPoint("TOPLEFT", 20 + (i - 1) * 86, -70)
		button:SetScript("OnClick", function(self)
			if self.onClick then
				self.onClick()
				ResetScroll()
				frame:Update()
			end
		end)
		frame.filters[i] = button
	end

	-- Segunda fila: interruptores de Por nivel, botón Volver o el veredicto del equipo.
	frame.subtext = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.subtext:SetPoint("TOPLEFT", 22, -100)
	frame.subtext:SetPoint("RIGHT", -24, 0)
	frame.subtext:SetJustifyH("LEFT")
	frame.subtext:SetWordWrap(false)

	frame.toggles = {}
	for i, toggle in ipairs({ { key = "hechas", label = "Hechas" }, { key = "bloqueadas", label = "Bloqueadas" },
		{ key = "relleno", label = "Relleno" } }) do
		local button = SmallButton(frame, 110, "")
		button:SetPoint("TOPLEFT", 20 + (i - 1) * 114, -96)
		button:SetScript("OnClick", function()
			db.levelFlags[toggle.key] = not db.levelFlags[toggle.key]
			ResetScroll()
			frame:Update()
		end)
		button.key = toggle.key
		button.label = toggle.label
		frame.toggles[i] = button
	end

	frame.back = SmallButton(frame, 90, "< Volver")
	frame.back:SetPoint("TOPLEFT", 20, -96)
	frame.back:SetScript("OnClick", function()
		QR.selectedDungeon = nil
		ResetScroll()
		frame:Update()
	end)

	-- Encabezados
	frame.headers = {}
	local function Header(x, anchorRight)
		local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		if anchorRight then
			header:SetPoint("TOPRIGHT", x, -122)
		else
			header:SetPoint("TOPLEFT", x, -122)
		end
		frame.headers[#frame.headers + 1] = header
		return header
	end
	Header(22); Header(76); Header(208); Header(504); Header(-44, true)

	-- Lista
	frame.rows = {}
	for i = 1, ROWS do
		frame.rows[i] = CreateRow(frame, i)
	end

	local scroll = CreateFrame("ScrollFrame", "QuestieRelevanciaScroll", frame, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 20, LIST_TOP)
	scroll:SetPoint("BOTTOMRIGHT", -40, HEIGHT + LIST_TOP - ROWS * ROW_HEIGHT)
	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() frame:Update() end)
	end)
	frame.scroll = scroll

	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("TOP", 0, -200)
	frame.empty:SetWidth(WIDTH - 80)

	local legend = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	legend:SetPoint("BOTTOMLEFT", 22, 44)
	legend:SetText(format("%s historia   %s experiencia   %s oro   %s equipo   %s mazmorra   %s clase   %s para entregar",
		ICONS.historia, ICONS.xp, ICONS.oro, ICONS.equipo, ICONS.mazmorra,
		ClassIcon(select(2, UnitClass("player"))), ICONS.entregar))

	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.status:SetPoint("BOTTOMLEFT", 22, 20)
	frame.status:SetWidth(250)
	frame.status:SetJustifyH("LEFT")
	frame.status:SetWordWrap(false)

	-- Botones de abajo: perfil y barra lateral de Questie.
	local preset = SmallButton(frame, 170, "")
	preset:SetPoint("BOTTOMRIGHT", -24, 16)
	preset:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	preset:SetScript("OnClick", function(_, mouseButton)
		local current = 1
		for i, p in ipairs(QR.PRESETS) do
			if p.key == db.preset then current = i end
		end
		local step = mouseButton == "RightButton" and -1 or 1
		db.preset = QR.PRESETS[(current - 1 + step) % #QR.PRESETS + 1].key
		wipe(db.custom)
		QR.Recalculate(true)
		frame:Update()
	end)
	preset:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Perfil: qué se prioriza")
		GameTooltip:AddLine("Clic: siguiente perfil. Clic derecho: anterior.", 1, 1, 1)
		GameTooltip:AddLine("Ajuste fino con /qr peso <criterio> <0 a 2>", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	preset:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.preset = preset

	local sortButton = SmallButton(frame, 130, "")
	sortButton:SetPoint("RIGHT", preset, "LEFT", -6, 0)
	sortButton:SetScript("OnClick", function() QR.ToggleTrackerSort() end)
	sortButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Ordenar el seguimiento de Questie por relevancia")
		GameTooltip:AddLine("Si Questie agrupa por zona, ordena adentro de cada zona.", 1, 1, 1)
		GameTooltip:Show()
	end)
	sortButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.sortButton = sortButton

	local trackerButton = SmallButton(frame, 150, "")
	trackerButton:SetPoint("RIGHT", sortButton, "LEFT", -6, 0)
	trackerButton:SetScript("OnClick", function() QR.ToggleTrackerBadges() end)
	trackerButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Puntaje e íconos en la barra lateral de Questie")
		GameTooltip:AddLine("Delante de cada misión que seguís: el puntaje, sus íconos", 1, 1, 1)
		GameTooltip:AddLine("y cuántos niveles de objeto mejora tu equipo.", 1, 1, 1)
		GameTooltip:Show()
	end)
	trackerButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.trackerButton = trackerButton

	-- Mientras se calcula algo en segundo plano, se refresca solo.
	local elapsed = 0
	frame:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta
		if elapsed < 0.25 then return end
		elapsed = 0
		if QR.Index.building or self.loading then
			self:Update()
		end
	end)

	function frame:Toggle()
		if self:IsShown() then self:Hide() else self:Show() end
	end

	local function SetupFilters(defs, current, onSelect)
		for i, button in ipairs(frame.filters) do
			local def = defs[i]
			if def then
				button:SetText(def.text or def.label)
				button.onClick = function() onSelect(def.key) end
				if def.key == current then button:LockHighlight() else button:UnlockHighlight() end
				button:Show()
			else
				button:Hide()
			end
		end
	end

	local categoryDefs
	local function CategoryDefs()
		if categoryDefs then return categoryDefs end
		categoryDefs = {}
		for _, filter in ipairs(CATEGORY_FILTERS) do
			local text = filter.label
			if filter.key == "clase" then
				text = ClassIcon(select(2, UnitClass("player")), 14) .. " " .. filter.label
			elseif filter.key == "xp" then
				text = ICONS.xp
			elseif ICON_PATHS[filter.key] then
				text = Icon(ICON_PATHS[filter.key], 14) .. " " .. filter.label
			end
			categoryDefs[#categoryDefs + 1] = { key = filter.key, text = text }
		end
		return categoryDefs
	end

	local function LevelDefs()
		local defs = {}
		for _, range in ipairs(QR.Views.LEVEL_RANGES) do
			defs[#defs + 1] = { key = range.key, text = range.label or range.key }
		end
		return defs
	end

	function frame:Update()
		local tab = db.tab
		self.preset:SetText("Perfil: " .. QR.GetPreset(db.preset).name .. (next(db.custom) and " *" or ""))
		self.trackerButton:SetText("Puntaje en Questie: " .. (db.tracker and "sí" or "no"))
		self.sortButton:SetText("Ordenar Questie: " .. (db.sortTracker and "sí" or "no"))

		local results = QR.results
		for _, button in ipairs(self.tabs) do
			local count = results[button.key] and #results[button.key]
			button:SetText(count and format("%s (%d)", button.label, count) or button.label)
			if button.key == tab then button:LockHighlight() else button:UnlockHighlight() end
		end

		for _, button in ipairs(self.toggles) do button:Hide() end
		self.back:Hide()
		self.subtext:ClearAllPoints()
		self.subtext:SetPoint("TOPLEFT", 22, -100)
		self.subtext:SetPoint("RIGHT", -24, 0)
		self.subtext:SetText("")
		self.loading = false

		local headers = { "Puntaje", "Por qué", "Misión", "Zona", "Cadena" }
		local entries, empty = {}, EMPTY_TEXT[tab]
		local index = QR.Index

		if index.building or not index.ready then
			SetupFilters({}, nil, function() end)
			empty = format("Analizando la base de datos de Questie... %d%%", index.progress * 100)
			entries = {}
		elseif tab == "log" or tab == "recomendadas" or tab == "resto" then
			SetupFilters(CategoryDefs(), db.filter, function(key) db.filter = key end)
			self.subtext:SetText(DESCRIPTIONS[tab])
			for _, result in ipairs(results[tab] or {}) do
				if db.filter == "todas" or result.tags[db.filter] then
					entries[#entries + 1] = { kind = "quest", result = result }
				end
			end
			if db.filter ~= "todas" and #entries == 0 then empty = "No hay misiones con este filtro." end
		elseif tab == "nivel" then
			SetupFilters(LevelDefs(), db.levelRange, function(key) db.levelRange = key end)
			for _, button in ipairs(self.toggles) do
				button:SetText(button.label .. ": " .. (db.levelFlags[button.key] and "sí" or "no"))
				button:Show()
			end
			self.subtext:ClearAllPoints()
			self.subtext:SetPoint("TOPLEFT", 366, -100)
			self.subtext:SetPoint("RIGHT", -24, 0)
			local view = QR.LevelView()
			if view then
				self.subtext:SetText(format("%d misiones, de menor a mayor nivel", view.count))
				for _, item in ipairs(view.list) do
					entries[#entries + 1] = item.header and { kind = "header", entry = item }
						or { kind = "quest", result = item, status = true }
				end
			else
				self.loading = true
				empty = "Calculando..."
			end
		elseif tab == "mazmorra" then
			local view = QR.DungeonView()
			if view.plan then
				SetupFilters({}, nil, function() end)
				self.back:Show()
				self.subtext:ClearAllPoints()
				self.subtext:SetPoint("TOPLEFT", 120, -100)
				self.subtext:SetPoint("RIGHT", -24, 0)
				self.subtext:SetText(format("|cffffd100%s|r: primero lo que se prepara afuera, después lo de adentro",
					QR.selectedDungeon.name))
				for _, result in ipairs(view.plan) do
					entries[#entries + 1] = { kind = "quest", result = result, status = true }
				end
				empty = "Ya hiciste todas las misiones de esta mazmorra, o no hay para tu personaje."
			else
				SetupFilters(DUNGEON_FILTERS, db.dungeonMode, function(key) db.dungeonMode = key end)
				self.subtext:SetText("Elegí una mazmorra para ver sus misiones en orden.")
				headers = { "Niveles", "", "Mazmorra", "Zona", "Hechas" }
				for _, entry in ipairs(view.dungeons) do
					entries[#entries + 1] = { kind = "dungeon", entry = entry }
				end
			end
		elseif tab == "equipo" then
			SetupFilters(GEAR_FILTERS, db.gearFilter, function(key) db.gearFilter = key end)
			local view = QR.GearView()
			local top = {}
			for _, row in ipairs(view.top) do
				top[#top + 1] = format("%s +%d", row.name, row.gain)
			end
			self.subtext:SetText(format("|cffffd100%s|r%s%s", view.verdict,
				view.percent and format(" (%d%% del ideal de misiones)", view.percent) or "",
				#top > 0 and ("   Mejoras más grandes: " .. table.concat(top, ", ")) or ""))
			headers = { "Falta", "", "Lo que llevás", "Ideal de misión", "" }
			for _, row in ipairs(view.rows) do
				local upToDate = row.ideal and not row.unknown and (row.gain or 0) == 0
				local needs = (row.gain or 0) > 0
				if db.gearFilter == "todas" or (db.gearFilter == "mejorar" and needs)
					or (db.gearFilter == "aldia" and upToDate) then
					entries[#entries + 1] = { kind = "gear", gearRow = row }
				end
			end
		end

		for i, header in ipairs(self.headers) do
			header:SetText(headers[i] or "")
		end

		FauxScrollFrame_Update(self.scroll, #entries, ROWS, ROW_HEIGHT)
		local offset = FauxScrollFrame_GetOffset(self.scroll)
		for i = 1, ROWS do
			local row, entry = self.rows[i], entries[offset + i]
			ClearRow(row)
			if entry then
				if entry.kind == "quest" then
					SetQuestRow(row, entry.result, entry.status)
				elseif entry.kind == "header" then
					SetHeaderRow(row, entry.entry)
				elseif entry.kind == "dungeon" then
					SetDungeonRow(row, entry.entry)
				elseif entry.kind == "gear" then
					SetGearRow(row, entry.gearRow)
				end
				row:Show()
			else
				row:Hide()
			end
		end

		if #entries == 0 then
			self.empty:SetText(empty or "")
			self.empty:Show()
		else
			self.empty:Hide()
		end

		local ctx = QR.context
		if ctx then
			local zone = QR.Data.ZoneName(ctx.zone)
			self.status:SetText(format("Nivel %d%s", ctx.level, zone ~= "" and ("  -  " .. zone) or ""))
		else
			self.status:SetText("")
		end
	end

	frame:SetScript("OnShow", function(self)
		self:Update()
	end)

	return frame
end

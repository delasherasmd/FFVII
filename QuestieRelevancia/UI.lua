-- Ventana de Questie Relevancia.

local _, QR = ...

local ROWS = 14
local ROW_HEIGHT = 22
local WIDTH, HEIGHT = 800, 540
local LIST_TOP = -136
local ICON_SIZE = 20 -- íconos de las misiones en la ventana

local function Icon(path, size)
	size = size or ICON_SIZE
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
	entregar = "|TInterface\\AddOns\\Questie\\Icons\\complete.blp:20:20|t",
}
QR.ICONS = ICONS

local STATUS_ICONS = {
	available = "|TInterface\\AddOns\\Questie\\Icons\\available.blp:18:18|t",
	blocked = "|TInterface\\AddOns\\Questie\\Icons\\available_gray.blp:18:18|t",
	log = "|TInterface\\AddOns\\Questie\\Icons\\incomplete.blp:18:18|t",
	done = "|TInterface\\RaidFrame\\ReadyCheck-Ready:18:18|t",
}
local STATUS_TEXT = {
	available = "Disponible", blocked = "Todavía no disponible", log = "En tu registro", done = "Ya la hiciste",
}

local function ClassIcon(classFile, size)
	local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
	if not coords then
		return "|cffffd100C|r"
	end
	size = size or ICON_SIZE
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
	{ key = "estadisticas", name = "Estadísticas" },
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

--- Íconos de las categorías de una misión: de 20 en la ventana; en el seguimiento
--- de Questie (compact) siguen su tamaño de letra y no llevan el texto "relleno".
function QR.TagIcons(result, size, compact)
	size = size or ICON_SIZE
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
	if result.tags.relleno and #icons == 0 and not compact then icons[#icons + 1] = ICONS.relleno end
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
	GameTooltip:AddLine("Llevás: " .. ItemText(row.item and row.item.itemId, row.have, 16), 1, 1, 1)
	if row.ideal then
		GameTooltip:AddLine("Ideal de misión: " .. ItemText(row.ideal.itemId, row.ideal.itemLevel, 16), 1, 1, 1)
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

	row.icons = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.icons:SetPoint("LEFT", row.score, "RIGHT", 10, 0)
	row.icons:SetWidth(150)
	row.icons:SetJustifyH("LEFT")

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("LEFT", row.icons, "RIGHT", 6, 0)
	row.name:SetWidth(266)
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
		if self.stat then
			QR.StatsTooltip(self, self.stat)
		elseif self.result then
			QR.QuestTooltip(self, self.result)
		elseif self.gearRow then
			GearTooltip(self, self.gearRow)
		elseif self.dungeon then
			DungeonTooltip(self, self.dungeon)
		end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnClick", function(self, mouseButton)
		if self.stat then
			QR.StatsClick(self.stat, mouseButton)
		elseif self.result then
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
	row.result, row.gearRow, row.dungeon, row.stat = nil, nil, nil, nil
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
	row.icons:SetText(format("%s %s %s", have and Icon(have, 20) or "", ideal and "|cffaaaaaa>|r" or "",
		ideal and Icon(ideal, 20) or ""))
	row.name:SetText(gearRow.name .. ": " .. ItemText(gearRow.item and gearRow.item.itemId, gearRow.have, 16))
	row.name:SetTextColor(1, 1, 1)
	if gearRow.notApplicable then
		row.zone:SetText("|cff808080no aplica (dos manos)|r")
	elseif gearRow.ideal then
		row.zone:SetText(ItemText(gearRow.ideal.itemId, gearRow.ideal.itemLevel, 16))
	else
		row.zone:SetText("|cff808080sin premio de misión|r")
	end
end

--------------------------------------------------------------------------------
-- Pestaña Estadísticas
--------------------------------------------------------------------------------

local SOURCE_ICONS = {
	quest = "Interface\\GossipFrame\\AvailableQuestIcon",
	vendor = "Interface\\GossipFrame\\VendorGossipIcon",
	drop = ICON_PATHS.mazmorra,
	craft = "Interface\\Icons\\Trade_BlackSmithing",
	world = ICON_PATHS.oro,
	chest = "Interface\\Icons\\INV_Box_02",
	container = "Interface\\Icons\\INV_Misc_Bag_10",
}
local CRAFT_ICONS = {
	[164] = "Interface\\Icons\\Trade_BlackSmithing", [165] = "Interface\\Icons\\Trade_LeatherWorking",
	[197] = "Interface\\Icons\\Trade_Tailoring", [202] = "Interface\\Icons\\Trade_Engineering",
	[171] = "Interface\\Icons\\Trade_Alchemy", [333] = "Interface\\Icons\\Trade_Engraving",
}

local function PercentColor(percent)
	if percent >= 100 then return "|cff20ff20" end
	if percent >= 80 then return "|cffa0ff40" end
	if percent >= 60 then return "|cffffd100" end
	return "|cffff6040"
end

local function SourceIcon(source)
	local path = source.kind == "craft" and CRAFT_ICONS[source.skill] or SOURCE_ICONS[source.kind]
	return path and Icon(path, 18) or ""
end

local function RequestItem(itemId)
	if itemId and C_Item and C_Item.RequestLoadItemDataByID and not (C_Item.GetItemInfo and C_Item.GetItemInfo(itemId)) then
		pcall(C_Item.RequestLoadItemDataByID, itemId)
	end
end

local function SetMustHaveRow(row, entry, totalAverage)
	local candidate = entry.candidate
	local item = candidate.item
	RequestItem(item.id)
	local percent = totalAverage > 0 and candidate.gain / totalAverage * 100 or 0
	row.score:SetText(format("|cff20ff20+%d%%|r", math.max(1, math.floor(percent + 0.5))))
	local icon = QR.Data.ItemIcon(item.id)
	local source = candidate.sources[1]
	row.icons:SetText(format("%s %s", icon and Icon(icon, 20) or "", SourceIcon(source)))
	row.name:SetText(ItemText(item.id, nil, 16) .. (candidate.owned and " |cff20ff20(lo tenés)|r" or "")
		.. (candidate.estimated and " |cffaaaaaa~|r" or ""))
	row.name:SetTextColor(1, 1, 1)
	local text, place = QR.Stats.SourceText(source, item)
	row.zone:SetText(place ~= "" and format("%s |cffaaaaaa- %s|r", text, place) or text)
	row.chain:SetText(SLOT_NAMES[candidate.slot] or "")
end

local function SetSlotRow(row, entry)
	local slotRow = entry.slot
	local itemId = slotRow.entry and slotRow.entry.itemId
	RequestItem(itemId)
	if slotRow.best then RequestItem(slotRow.best.id) end
	if slotRow.average and slotRow.average > 0 then
		local percent = math.floor(slotRow.have / slotRow.average * 100 + 0.5)
		row.score:SetText(PercentColor(percent) .. percent .. "%|r")
	else
		row.score:SetText("|cff808080-|r")
	end
	local have = itemId and QR.Data.ItemIcon(itemId)
	local best = slotRow.best and QR.Data.ItemIcon(slotRow.best.id)
	row.icons:SetText(format("%s %s %s", have and Icon(have, 20) or "", best and "|cffaaaaaa>|r" or "",
		best and Icon(best, 20) or ""))
	row.name:SetText(slotRow.name .. ": " .. ItemText(itemId, nil, 16))
	row.name:SetTextColor(1, 1, 1)
	if slotRow.best and (slotRow.bestPower or 0) > slotRow.have + 0.5 then
		row.zone:SetText("Lo mejor: " .. ItemText(slotRow.best.id, nil, 16))
	elseif slotRow.best then
		row.zone:SetText("|cff20ff20Ya tenés lo mejor para tu nivel|r")
	else
		row.zone:SetText("")
	end
end

local function SetKeyStatRow(row, entry)
	local stat = entry.key
	local S = QR.Stats
	local percent = stat.average > 0 and math.floor(stat.have / stat.average * 100 + 0.5) or nil
	row.score:SetText(percent and (PercentColor(percent) .. percent .. "%|r") or "")
	row.name:SetText(S.STAT_NAMES[stat.key] or stat.key)
	row.name:SetTextColor(1, 0.82, 0)
	local function Number(value)
		if stat.key == "D" then return format("%.1f", value / 10) end
		return format(value >= 10 and "%d" or "%.1f", value)
	end
	row.zone:SetText(format("tu equipo %s  |cffaaaaaamedia %s|r", Number(stat.have), Number(stat.average)))
end

function QR.StatsTooltip(owner, entry)
	local S, D = QR.Stats, QR.Data
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if entry.kind == "must" then
		local candidate = entry.candidate
		local ok = GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, candidate.item.id)
		if not ok then
			GameTooltip:AddLine(D.ItemName(candidate.item.id), 1, 1, 1)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(format("Mejora %s: +%.0f puntos de poder", SLOT_NAMES[candidate.slot] or "la ranura",
			candidate.gain), 0.2, 1, 0.2)
		if candidate.estimated then
			GameTooltip:AddLine("Tiene sufijo al azar: se calcula con el mejor para tu rama.", 0.7, 0.7, 0.7)
		end
		if candidate.owned then
			GameTooltip:AddLine("Ya lo tenés en las bolsas o el banco.", 0.2, 1, 0.2)
		end
		GameTooltip:AddLine("Cómo conseguirlo:", 1, 0.82, 0)
		for i = 1, math.min(3, #candidate.sources) do
			local text, place = S.SourceText(candidate.sources[i], candidate.item)
			GameTooltip:AddDoubleLine(text, place, 1, 1, 1, 0.7, 0.7, 0.7)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Clic: ver en el mapa. Mayús+clic: enlazarlo en el chat.", 0.5, 0.8, 1)
	elseif entry.kind == "slot" then
		local slotRow = entry.slot
		GameTooltip:AddLine(slotRow.name, 1, 0.82, 0)
		GameTooltip:AddLine("Llevás: " .. ItemText(slotRow.entry and slotRow.entry.itemId, nil, 16), 1, 1, 1)
		GameTooltip:AddDoubleLine("Poder de lo tuyo", format("%.0f", slotRow.have), 1, 1, 1, 1, 1, 1)
		if slotRow.average then
			GameTooltip:AddDoubleLine("Media de tu nivel (verdes y azules)", format("%.0f", slotRow.average), 1, 1, 1, 1, 1, 1)
		end
		if slotRow.best then
			GameTooltip:AddDoubleLine("Lo mejor hasta tu nivel", format("%.0f", slotRow.bestPower or 0), 1, 1, 1, 1, 1, 1)
			GameTooltip:AddLine("  " .. ItemText(slotRow.best.id, nil, 16), 1, 1, 1)
			local sources = S.UsableSources(slotRow.best, QR.StatsView().ctx)
			if sources[1] then
				local text, place = S.SourceText(sources[1], slotRow.best)
				GameTooltip:AddDoubleLine("  " .. text, place, 0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
			end
		end
		if slotRow.bestRaid then
			GameTooltip:AddDoubleLine("Con bandas", format("%.0f", slotRow.bestRaidPower or 0), 1, 1, 1, 1, 1, 1)
			GameTooltip:AddLine("  " .. ItemText(slotRow.bestRaid.id, nil, 16), 1, 1, 1)
		end
		if slotRow.slot == 13 or slotRow.slot == 14 then
			GameTooltip:AddLine("Los efectos de uso de los abalorios no se cuentan.", 0.7, 0.7, 0.7)
		end
		if slotRow.entry and slotRow.entry.fromGame then
			GameTooltip:AddLine("Objeto que no está en la base: se usan los datos del juego.", 0.7, 0.7, 0.7)
		end
	elseif entry.kind == "key" then
		local name = QR.Stats.STAT_NAMES[entry.key.key] or entry.key.key
		GameTooltip:AddLine(name, 1, 0.82, 0)
		GameTooltip:AddLine("Lo que suma tu equipo, comparado con lo que suma un equipo", 1, 1, 1)
		GameTooltip:AddLine("medio de tu nivel (sin contar tus atributos base ni talentos).", 1, 1, 1)
	end
	GameTooltip:Show()
end

function QR.StatsClick(entry, mouseButton)
	if entry.kind ~= "must" then
		return
	end
	local candidate = entry.candidate
	if IsModifiedClick and IsModifiedClick("CHATLINK") then
		local link = select(2, (C_Item and C_Item.GetItemInfo or GetItemInfo)(candidate.item.id))
		if link and ChatEdit_InsertLink then
			ChatEdit_InsertLink(link)
		end
		return
	end
	local source = candidate.sources[1]
	if source.kind == "quest" then
		QR.Data.ShowQuest({ id = source.id, name = QR.Data.QuestName(source.id), zone = QR.Data.QuestZone(source.id) })
	else
		local zone = QR.Stats.SourceZone(source)
		if zone then
			QR.Data.ShowQuest({ id = 0, name = QR.Data.ItemName(candidate.item.id), zone = zone })
		end
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
		local button = SmallButton(frame, 106, tab.name)
		button:SetHeight(24)
		button:SetPoint("TOPLEFT", 20 + (i - 1) * 109, -42)
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
	Header(22); Header(76); Header(232); Header(504); Header(-44, true)

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
			button:SetWidth(84)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", 20 + (i - 1) * 86, -70)
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

	-- Pestaña Estadísticas: botones de rama (3) y de rol, y la lista.
	function frame:StatsEntries()
		local S = QR.Stats
		local view = QR.StatsView()
		for _, button in ipairs(self.filters) do button:Hide() end
		if view.error then
			return {}, "No se pudo evaluar el equipo: " .. view.error
		end
		local ctx, report = view.ctx, view.report
		local classFile = ctx.classFile
		local spec = ctx.spec
		local trees = S.TREES[classFile]
		for i = 1, 3 do
			local button = self.filters[i]
			button:SetWidth(138)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", 20 + (i - 1) * 141, -70)
			button:SetText(format("%s %d", spec.names[i] or trees[i].name, spec.points[i] or 0))
			button.onClick = function()
				db.statsTree = i
				if not (trees[i][db.statsRole or ""]) then
					db.statsRole = nil
				end
			end
			if ctx.tree == i then button:LockHighlight() else button:UnlockHighlight() end
			button:Show()
		end
		local roles = S.ClassRoles(classFile)
		for j, role in ipairs(roles) do
			local button = self.filters[3 + j]
			button:SetWidth(80)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", 20 + 3 * 141 + 6 + (j - 1) * 82, -70)
			button:SetText(S.ROLE_NAMES[role])
			button.onClick = function() db.statsRole = role end
			if ctx.role == role then button:LockHighlight() else button:UnlockHighlight() end
			button:Show()
		end
		if db.statsTree or db.statsRole then
			local button = self.filters[8]
			button:SetWidth(64)
			button:ClearAllPoints()
			button:SetPoint("TOPRIGHT", -24, -70)
			button:SetText("Auto")
			button.onClick = function() db.statsTree, db.statsRole = nil, nil end
			button:UnlockHighlight()
			button:Show()
		end

		local totals = report.totals
		local percent = totals.average > 0 and math.floor(totals.have / totals.average * 100 + 0.5) or nil
		local ceiling = totals.best > 0 and math.floor(totals.have / totals.best * 100 + 0.5) or nil
		local detected
		if spec.none then
			detected = "sin talentos todavía"
		else
			detected = format("rama detectada: %s%s", spec.names[spec.index] or trees[spec.index].name,
				spec.hybrid and " (híbrida)" or "")
		end
		local summary = {}
		if report.unknown > 0 and totals.have == 0 then
			percent, ceiling = nil, nil
			summary[#summary + 1] = "|cffffd100Todavía no cargaron los datos de tu equipo.|r"
		elseif report.unknown > 0 then
			summary[#summary + 1] = format("|cffaaaaaa%d objetos sin datos todavía|r", report.unknown)
		end
		if percent then
			summary[#summary + 1] = format("Tu equipo: %s%d%%|r de la media de tu nivel", PercentColor(percent), percent)
		end
		if ceiling then
			summary[#summary + 1] = format("%d%% de lo mejor que podés conseguir", ceiling)
		end
		if ctx.level >= 60 and totals.raid > totals.best then
			summary[#summary + 1] = format("%d%% con bandas", math.floor(totals.have / totals.raid * 100 + 0.5))
		end
		self.subtext:SetText(format("%s  |cffaaaaaa(%s)|r", table.concat(summary, "  -  "), detected))

		local entries = {}
		entries[#entries + 1] = { kind = "header",
			entry = { text = "Infaltables: lo que más suma, primero lo más fácil de conseguir" } }
		for _, candidate in ipairs(report.mustHave) do
			entries[#entries + 1] = { kind = "must", candidate = candidate, totalAverage = totals.average }
		end
		if #report.mustHave == 0 then
			entries[#entries + 1] = { kind = "header", entry = { text = "|cffaaaaaaNo encontré mejoras a tu alcance.|r" } }
		end
		entries[#entries + 1] = { kind = "header", entry = { text = "Por ranura: lo tuyo comparado con la media de tu nivel" } }
		for _, slotRow in ipairs(report.slots) do
			if not slotRow.skip then
				entries[#entries + 1] = { kind = "slot", slot = slotRow }
			end
		end
		local profileName = S.TREES[classFile][ctx.tree].name .. ", " .. S.ROLE_NAMES[ctx.role]:lower()
		entries[#entries + 1] = { kind = "header", entry = { text = "Estadísticas clave (" .. profileName .. ")" } }
		for _, key in ipairs(report.keyStats) do
			entries[#entries + 1] = { kind = "key", key = key }
		end
		return entries, nil
	end

	local categoryDefs
	local function CategoryDefs()
		if categoryDefs then return categoryDefs end
		categoryDefs = {}
		for _, filter in ipairs(CATEGORY_FILTERS) do
			local text = filter.label
			if filter.key == "clase" then
				text = ClassIcon(select(2, UnitClass("player")), 16) .. " " .. filter.label
			elseif filter.key == "xp" then
				text = ICONS.xp
			elseif ICON_PATHS[filter.key] then
				text = Icon(ICON_PATHS[filter.key], 16) .. " " .. filter.label
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

		if tab == "estadisticas" then
			headers = { "Mejora", "", "Objeto", "Cómo conseguirlo / detalle", "Ranura" }
			entries, empty = self:StatsEntries()
		elseif index.building or not index.ready then
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
				elseif entry.kind == "must" then
					row.stat = entry
					SetMustHaveRow(row, entry, entry.totalAverage)
				elseif entry.kind == "slot" then
					row.stat = entry
					SetSlotRow(row, entry)
				elseif entry.kind == "key" then
					row.stat = entry
					SetKeyStatRow(row, entry)
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

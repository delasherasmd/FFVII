-- Ventana de Questie Relevancia.

local _, QR = ...

local ROWS = 15
local ROW_HEIGHT = 22
local WIDTH, HEIGHT = 720, 500

local function Icon(path, size)
	size = size or 16
	return format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", path, size, size)
end

local ICONS = {
	historia = Icon("Interface\\Icons\\INV_Misc_Book_09"),
	xp = "|cff9d8cffXP|r",
	oro = Icon("Interface\\Icons\\INV_Misc_Coin_01"),
	equipo = Icon("Interface\\Icons\\INV_Sword_04"),
	mazmorra = Icon("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"),
	relleno = "|cff808080relleno|r",
	entregar = "|TInterface\\AddOns\\Questie\\Icons\\complete.blp:16:16|t",
}
QR.ICONS = ICONS

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
}

local FILTERS = {
	{ key = "todas", label = "Todas" },
	{ key = "historia", label = "Historia" },
	{ key = "xp", label = "XP" },
	{ key = "oro", label = "Oro" },
	{ key = "equipo", label = "Equipo" },
	{ key = "mazmorra", label = "Mazmorra" },
	{ key = "clase", label = "Clase" },
	{ key = "relleno", label = "Relleno" },
}

local EMPTY_TEXT = {
	log = "No tenés misiones en el registro.",
	recomendadas = "No hay misiones recomendadas para tu zona y nivel. Mirá en \"El resto\".",
	resto = "No hay más misiones disponibles según Questie.",
}

local function ScoreColor(score)
	if score >= 80 then return 0.1, 1, 0.1 end
	if score >= 60 then return 0.6, 1, 0.2 end
	if score >= 40 then return 1, 0.85, 0.1 end
	if score >= 20 then return 1, 0.55, 0.2 end
	return 0.6, 0.6, 0.6
end

local function Money(copper)
	copper = math.floor(copper or 0)
	local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if gold > 0 then parts[#parts + 1] = "|cffffd700" .. gold .. "o|r" end
	if silver > 0 then parts[#parts + 1] = "|cffc7c7cf" .. silver .. "p|r" end
	if rest > 0 or #parts == 0 then parts[#parts + 1] = "|cffeda55f" .. rest .. "c|r" end
	return table.concat(parts, " ")
end

local function TagIcons(result)
	local icons = {}
	if result.complete == 1 then icons[#icons + 1] = ICONS.entregar end
	if result.tags.historia then icons[#icons + 1] = ICONS.historia end
	if result.tags.xp then icons[#icons + 1] = ICONS.xp end
	if result.tags.oro then icons[#icons + 1] = ICONS.oro end
	if result.tags.equipo then icons[#icons + 1] = ICONS.equipo end
	if result.tags.mazmorra then icons[#icons + 1] = ICONS.mazmorra end
	if result.tags.clase then icons[#icons + 1] = ClassIcon(QR.context and QR.context.classFile) end
	if result.tags.relleno and #icons == 0 then icons[#icons + 1] = ICONS.relleno end
	return table.concat(icons, " ")
end

local function ShowTooltip(row)
	local result = row.result
	if not result then
		return
	end
	local D = QR.Data
	local color = DIFFICULTY_COLORS[result.difficulty]
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(result.name, color[1], color[2], color[3])
	GameTooltip:AddLine(format("Puntaje: %d/100", result.score), ScoreColor(result.score))
	local zoneName = D.ZoneName(result.zone)
	GameTooltip:AddLine(format("Nivel %d (requiere %d)%s", result.level, result.requiredLevel,
		zoneName ~= "" and (" - " .. zoneName) or ""), 1, 1, 1)
	if result.complete == 1 then
		GameTooltip:AddLine("Lista para entregar", 0.2, 1, 0.2)
	elseif result.complete == -1 then
		GameTooltip:AddLine("Fallida", 1, 0.2, 0.2)
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
		local gain = result.gearGain and format("+%d niveles", result.gearGain) or "hueco vacío"
		GameTooltip:AddDoubleLine(ICONS.equipo .. " Mejora de equipo", format("%s (%s)", gain, slot), 1, 1, 1, 1, 1, 1)
	end
	if result.money > 0 or result.sell > 0 then
		local text = result.money > 0 and Money(result.money) or ""
		if result.sell > 0 then
			text = text .. (text ~= "" and " + " or "") .. Money(result.sell) .. " al vender"
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
	GameTooltip:Show()
end

local function CreateRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 20, -114 - (index - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT", -42, 0)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

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
	row.name:SetWidth(270)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.zone:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
	row.zone:SetWidth(140)
	row.zone:SetJustifyH("LEFT")
	row.zone:SetWordWrap(false)

	row.chain = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.chain:SetPoint("RIGHT", 0, 0)
	row.chain:SetWidth(50)
	row.chain:SetJustifyH("RIGHT")

	row:SetScript("OnEnter", ShowTooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnClick", function(self)
		if self.result then
			QR.Data.ShowQuest(self.result)
		end
	end)
	return row
end

local function SetRow(row, result)
	row.result = result
	if not result then
		row:Hide()
		return
	end
	row.score:SetText(result.score)
	row.score:SetTextColor(ScoreColor(result.score))
	row.icons:SetText(TagIcons(result))
	local color = DIFFICULTY_COLORS[result.difficulty]
	row.name:SetText(format("[%d] %s", result.level, result.name))
	row.name:SetTextColor(color[1], color[2], color[3])
	row.zone:SetText(QR.Data.ZoneName(result.zone))
	row.chain:SetText(result.chainTotal > 1 and format("%d/%d", result.step, result.chainTotal) or "")
	row:Show()
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

	-- Pestañas
	frame.tabs = {}
	for i, tab in ipairs(TABS) do
		local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		button:SetSize(150, 24)
		button:SetPoint("TOPLEFT", 20 + (i - 1) * 154, -42)
		button:SetScript("OnClick", function()
			db.tab = tab.key
			FauxScrollFrame_SetOffset(frame.scroll, 0)
			frame:Update()
		end)
		button.key = tab.key
		button.label = tab.name
		frame.tabs[i] = button
	end

	-- Perfil
	local preset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	preset:SetSize(190, 24)
	preset:SetPoint("TOPRIGHT", -24, -42)
	preset:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	preset:SetScript("OnClick", function(_, mouseButton)
		local current = 1
		for i, p in ipairs(QR.PRESETS) do
			if p.key == db.preset then current = i end
		end
		local step = mouseButton == "RightButton" and -1 or 1
		local nextIndex = (current - 1 + step) % #QR.PRESETS + 1
		db.preset = QR.PRESETS[nextIndex].key
		wipe(db.custom)
		frame:UpdatePreset()
		QR.Recalculate()
		frame:Update()
	end)
	preset:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Perfil: qué se prioriza")
		GameTooltip:AddLine("Clic: siguiente perfil. Clic derecho: anterior.", 1, 1, 1)
		GameTooltip:AddLine("Ajuste fino con /qr peso <criterio> <0 a 2>", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	preset:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.preset = preset

	-- Filtros por categoría
	frame.filters = {}
	for i, filter in ipairs(FILTERS) do
		local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		button:SetSize(82, 22)
		button:SetPoint("TOPLEFT", 20 + (i - 1) * 84, -72)
		local text = filter.label
		if filter.key == "clase" then
			text = ClassIcon(select(2, UnitClass("player")), 14) .. " " .. filter.label
		elseif filter.key == "xp" then
			text = ICONS.xp
		elseif filter.key ~= "relleno" and ICONS[filter.key] then
			text = ICONS[filter.key]:gsub(":16:16:", ":14:14:") .. " " .. filter.label
		end
		button:SetText(text)
		button:GetFontString():SetFontObject("GameFontNormalSmall")
		button:SetScript("OnClick", function()
			db.filter = filter.key
			FauxScrollFrame_SetOffset(frame.scroll, 0)
			frame:Update()
		end)
		button.key = filter.key
		frame.filters[i] = button
	end

	-- Encabezados
	local function Header(text, x)
		local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		header:SetPoint("TOPLEFT", x, -100)
		header:SetText(text)
		return header
	end
	Header("Puntaje", 22)
	Header("Por qué", 76)
	Header("Misión", 208)
	Header("Zona", 484)
	local chainHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	chainHeader:SetPoint("TOPRIGHT", -44, -100)
	chainHeader:SetText("Cadena")

	-- Lista
	frame.rows = {}
	for i = 1, ROWS do
		frame.rows[i] = CreateRow(frame, i)
	end

	local scroll = CreateFrame("ScrollFrame", "QuestieRelevanciaScroll", frame, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 20, -114)
	scroll:SetPoint("BOTTOMRIGHT", -40, HEIGHT - 114 - ROWS * ROW_HEIGHT)
	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() frame:Update() end)
	end)
	frame.scroll = scroll

	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("TOP", 0, -170)
	frame.empty:SetWidth(WIDTH - 80)

	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.status:SetPoint("BOTTOMLEFT", 22, 36)
	frame.status:SetJustifyH("LEFT")

	local legend = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	legend:SetPoint("BOTTOMLEFT", 22, 18)
	legend:SetText(format("%s historia   %s experiencia   %s oro   %s equipo   %s mazmorra   %s clase   %s para entregar",
		ICONS.historia, ICONS.xp, ICONS.oro, ICONS.equipo, ICONS.mazmorra,
		ClassIcon(select(2, UnitClass("player"))), ICONS.entregar))

	-- Mientras se arma el índice, muestra el avance.
	local elapsed = 0
	frame:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta
		if elapsed < 0.25 then return end
		elapsed = 0
		if QR.Index.building then
			self:Update()
		end
	end)

	function frame:Toggle()
		if self:IsShown() then self:Hide() else self:Show() end
	end

	function frame:UpdatePreset()
		self.preset:SetText("Perfil: " .. QR.GetPreset(db.preset).name .. (next(db.custom) and " *" or ""))
	end

	function frame:Update()
		self:UpdatePreset()
		local results = QR.results
		for _, button in ipairs(self.tabs) do
			local count = #(results[button.key] or {})
			button:SetText(format("%s (%d)", button.label, count))
			if button.key == db.tab then button:LockHighlight() else button:UnlockHighlight() end
		end
		for _, button in ipairs(self.filters) do
			if button.key == db.filter then button:LockHighlight() else button:UnlockHighlight() end
		end

		local list = {}
		for _, result in ipairs(results[db.tab] or {}) do
			if db.filter == "todas" or result.tags[db.filter] then
				list[#list + 1] = result
			end
		end

		FauxScrollFrame_Update(self.scroll, #list, ROWS, ROW_HEIGHT)
		local offset = FauxScrollFrame_GetOffset(self.scroll)
		for i = 1, ROWS do
			SetRow(self.rows[i], list[offset + i])
		end

		local index = QR.Index
		if index.building or not index.ready then
			self.empty:SetText(format("Analizando la base de datos de Questie... %d%%", index.progress * 100))
			self.empty:Show()
		elseif index.error then
			self.empty:SetText("No pude leer la base de datos de Questie.")
			self.empty:Show()
		elseif #list == 0 then
			self.empty:SetText(db.filter == "todas" and EMPTY_TEXT[db.tab] or "No hay misiones con este filtro.")
			self.empty:Show()
		else
			self.empty:Hide()
		end

		local ctx = QR.context
		if ctx then
			local zone = QR.Data.ZoneName(ctx.zone)
			self.status:SetText(format("Nivel %d%s   -   %d misiones en esta lista",
				ctx.level, zone ~= "" and ("   -   " .. zone) or "", #list))
		else
			self.status:SetText("")
		end
	end

	frame:SetScript("OnShow", function(self)
		self:Update()
	end)

	return frame
end

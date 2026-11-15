-- Catálogo de la cadena: todo lo que se obtiene en la pila de misiones seguidas.

local _, QR = ...

local ROWS = 12
local ROW_HEIGHT = 24
local WIDTH, HEIGHT = 600, 470

local STATUS_ICONS = {
	done = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t",
	log = "|TInterface\\AddOns\\Questie\\Icons\\incomplete.blp:14:14|t",
	todo = "|TInterface\\AddOns\\Questie\\Icons\\available.blp:14:14|t",
}

local function ItemIcons(step, limit)
	local icons = {}
	for i, item in ipairs(step.items) do
		if i > limit then
			icons[#icons + 1] = "|cffaaaaaa+" .. (#step.items - limit) .. "|r"
			break
		end
		local fileId = QR.Data.ItemIcon(item.itemId)
		if fileId then
			icons[#icons + 1] = format("|T%s:18:18:0:0:64:64:5:59:5:59|t", fileId)
		end
	end
	return table.concat(icons, "")
end

local function ShowStepTooltip(row)
	local step = row.step
	if not step then
		return
	end
	local D = QR.Data
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(format("Paso %d: %s", step.index, step.name), 1, 0.82, 0)
	GameTooltip:AddLine(format("Nivel %d", step.level), 1, 1, 1)
	if step.done then
		GameTooltip:AddLine("Ya la hiciste", 0.3, 1, 0.3)
	elseif step.inLog then
		GameTooltip:AddLine("En tu registro de misiones", 1, 1, 0.3)
	end
	if step.xp and step.xp > 0 then
		GameTooltip:AddDoubleLine("Experiencia", format("%d XP", step.xp), 1, 1, 1, 1, 1, 1)
	end
	if #step.items > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Recompensas:", 1, 0.82, 0)
		for _, item in ipairs(step.items) do
			local quality = D.ItemQuality(item.itemId)
			local r, g, b = 1, 1, 1
			if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
				local color = ITEM_QUALITY_COLORS[quality]
				r, g, b = color.r, color.g, color.b
			end
			local fileId = D.ItemIcon(item.itemId)
			local icon = fileId and format("|T%s:14:14|t ", fileId) or ""
			GameTooltip:AddDoubleLine(icon .. D.ItemName(item.itemId),
				item.upgrade and "|cff20ff20mejora tu equipo|r" or "", r, g, b, 1, 1, 1)
		end
	end
	if #step.rep > 0 then
		GameTooltip:AddLine(" ")
		for _, rep in ipairs(step.rep) do
			GameTooltip:AddDoubleLine("Reputación: " .. D.FactionName(rep.factionId), format("%+d", rep.value),
				1, 1, 1, 0.4, 0.8, 1)
		end
	end
	GameTooltip:Show()
end

function QR.CreateCatalog()
	local frame = CreateFrame("Frame", "QuestieRelevanciaCatalog", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER", 40, -20)
	frame:SetFrameStrata("DIALOG")
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
	tinsert(UISpecialFrames, "QuestieRelevanciaCatalog")

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOP", 0, -18)
	frame.title:SetWidth(WIDTH - 80)
	frame.title:SetWordWrap(false)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.subtitle:SetPoint("TOP", 0, -40)

	frame.rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 20, -60 - (i - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", -42, 0)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.status:SetPoint("LEFT", 0, 0)
		row.status:SetWidth(22)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.name:SetPoint("LEFT", row.status, "RIGHT", 4, 0)
		row.name:SetWidth(250)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.xp = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.xp:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
		row.xp:SetWidth(70)
		row.xp:SetJustifyH("RIGHT")
		row.items = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.items:SetPoint("LEFT", row.xp, "RIGHT", 10, 0)
		row.items:SetPoint("RIGHT", 0, 0)
		row.items:SetJustifyH("LEFT")
		row:SetScript("OnEnter", ShowStepTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		frame.rows[i] = row
	end

	local scroll = CreateFrame("ScrollFrame", "QuestieRelevanciaCatalogScroll", frame, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 20, -60)
	scroll:SetPoint("BOTTOMRIGHT", -40, HEIGHT - 60 - ROWS * ROW_HEIGHT)
	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() frame:Update() end)
	end)
	frame.scroll = scroll

	frame.totals = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.totals:SetPoint("BOTTOMLEFT", 22, 22)
	frame.totals:SetPoint("BOTTOMRIGHT", -22, 22)
	frame.totals:SetJustifyH("LEFT")
	frame.totals:SetJustifyV("BOTTOM")

	function frame:Show_(catalog)
		self.catalog = catalog
		FauxScrollFrame_SetOffset(self.scroll, math.max(0, catalog.position - 3))
		self:Show()
		self:Update()
	end

	function frame:Update()
		local catalog = self.catalog
		if not catalog then
			return
		end
		local steps = catalog.steps
		self.title:SetText("Cadena: " .. (steps[1] and steps[1].name or ""))
		self.subtitle:SetText(format("%d pasos - estás en el paso %d", #steps, catalog.position))

		FauxScrollFrame_Update(self.scroll, #steps, ROWS, ROW_HEIGHT)
		local offset = FauxScrollFrame_GetOffset(self.scroll)
		for i = 1, ROWS do
			local row, step = self.rows[i], steps[offset + i]
			row.step = step
			if step then
				row.status:SetText(step.done and STATUS_ICONS.done or step.inLog and STATUS_ICONS.log or STATUS_ICONS.todo)
				row.name:SetText(format("%d. [%d] %s", step.index, step.level, step.name))
				if step.current then
					row.name:SetTextColor(0.3, 1, 0.3)
				elseif step.done then
					row.name:SetTextColor(0.55, 0.55, 0.55)
				else
					row.name:SetTextColor(1, 0.82, 0)
				end
				row.xp:SetText(step.xp and step.xp > 0 and format("%d XP", step.xp) or "")
				local text = ItemIcons(step, 6)
				for _, rep in ipairs(step.rep) do
					if rep.value > 0 then
						text = text .. format("  |cff66ccff+%d rep|r", rep.value)
						break
					end
				end
				row.items:SetText(text)
				row:Show()
			else
				row:Hide()
			end
		end

		local t = catalog.totals
		local function Plural(n, one, many) return n .. " " .. (n == 1 and one or many) end
		local lines = {}
		if t.remaining == 0 then
			lines[#lines + 1] = "|cff20ff20Ya hiciste toda esta cadena.|r"
		else
			lines[#lines + 1] = format("|cffffd100Lo que falta (%s):|r %d XP  -  %s%s", Plural(t.remaining, "paso", "pasos"),
				t.xp, Plural(t.items, "objeto", "objetos"),
				t.upgrades > 0 and format(" (|cff20ff20%s tu equipo|r)",
					Plural(t.upgrades, "mejora", "mejoran")) or "")
		end
		if t.sell > 0 then
			lines[#lines + 1] = "Si vendés los objetos: " .. QR.Money(t.sell)
		end
		local reps = {}
		for _, factionId in ipairs(t.repOrder) do
			reps[#reps + 1] = format("%+d %s", t.rep[factionId], QR.Data.FactionName(factionId))
		end
		if #reps > 0 then
			lines[#lines + 1] = "Reputación: " .. table.concat(reps, ", ")
		end
		self.totals:SetText(table.concat(lines, "\n"))
	end

	return frame
end

--- Abre el catálogo de la cadena de una misión.
function QR.ShowCatalog(questId)
	if not QR.Index.ready or not QR.context then
		return
	end
	QR.catalogFrame = QR.catalogFrame or QR.CreateCatalog()
	local catalog = QR.Views.ChainCatalog(QR.context, questId, QR.Data.LogQuests())
	QR.catalogFrame:Show_(catalog)
end

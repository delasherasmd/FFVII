-- Botón en el minimapa: clic abre la ventana, se arrastra alrededor del minimapa.

local _, QR = ...

local cos, sin, rad, deg, atan2 = math.cos, math.sin, math.rad, math.deg, math.atan2
local modern = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE -- Forever usa el cliente moderno

local function UpdatePosition(button, angle)
	local radians = rad(angle or 210)
	local x = cos(radians) * (Minimap:GetWidth() / 2 + 5)
	local y = sin(radians) * (Minimap:GetHeight() / 2 + 5)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function QR.CreateMinimapButton()
	local db = QR.DB()
	local button = CreateFrame("Button", "QuestieRelevanciaMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
	border:SetPoint("TOPLEFT")
	if modern then
		background:SetSize(24, 24)
		background:SetPoint("CENTER")
		icon:SetSize(18, 18)
		icon:SetPoint("CENTER")
		border:SetSize(50, 50)
	else
		background:SetSize(20, 20)
		background:SetPoint("TOPLEFT", 7, -5)
		icon:SetSize(17, 17)
		icon:SetPoint("TOPLEFT", 7, -6)
		border:SetSize(53, 53)
	end

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			QR.ToggleTrackerBadges()
		else
			QR.Toggle()
		end
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Questie Relevancia")
		GameTooltip:AddLine("Clic: abrir la ventana", 1, 1, 1)
		GameTooltip:AddLine("Clic derecho: puntaje en el seguimiento de Questie", 1, 1, 1)
		GameTooltip:AddLine("Arrastrá para moverlo", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			db.minimap.angle = deg(atan2(py / scale - my, px / scale - mx)) % 360
			UpdatePosition(self, db.minimap.angle)
		end)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	UpdatePosition(button, db.minimap.angle)
	if db.minimap.hide then
		button:Hide()
	end
	return button
end

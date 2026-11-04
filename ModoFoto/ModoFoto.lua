-- Modo Foto: capturas de pantalla limpias, sin interfaz.
-- Funciona en WoW Classic Era (1.15) y WoW Forever (1.60).

local ADDON_NAME = ...
local PREFIX = "|cff33ccffModo Foto:|r "
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

BINDING_HEADER_MODOFOTO = "Modo Foto"
BINDING_NAME_MODOFOTO_TOGGLE = "Entrar o salir del modo foto"
BINDING_NAME_MODOFOTO_SHOT = "Foto limpia ahora"
BINDING_NAME_MODOFOTO_TIMER = "Foto limpia con temporizador"

local DEFAULTS = {
	ocultarNombres = true, -- nombres, placas y bocadillos sobre los personajes
	segundos = 3,          -- duración del temporizador
}

-- Estas opciones dibujan texto sobre el mundo, no en la interfaz, así que
-- ocultar la interfaz no alcanza: se apagan mientras dura la foto.
local WORLD_TEXT_CVARS = {
	"UnitNameOwn",
	"UnitNameNPC",
	"UnitNameHostleNPC",
	"UnitNameInteractiveNPC",
	"UnitNameFriendlySpecialNPCName",
	"UnitNameNonCombatCreatureName",
	"UnitNameFriendlyPlayerName",
	"UnitNameEnemyPlayerName",
	"UnitNameFriendlyMinionName",
	"UnitNameEnemyMinionName",
	"nameplateShowEnemies",
	"nameplateShowFriends",
	"chatBubbles",
	"chatBubblesParty",
}

local GetCVarValue = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCVarValue = (C_CVar and C_CVar.SetCVar) or SetCVar

local db
local active = false             -- la interfaz está oculta por este addon
local exitAfterShot = false      -- volver a mostrar la interfaz cuando termine la captura
local shotPending = false        -- se pidió una captura y todavía no terminó
local shotId = 0                 -- distingue capturas para los avisos atrasados
local restoreAfterCombat = false -- hay opciones que no se pueden cambiar en combate
local countdownTicker

local function Print(message)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. message)
end

local function PlayTick()
	if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
end

--------------------------------------------------------------------------------
-- Aviso en pantalla
--------------------------------------------------------------------------------

-- Sin padre, para que se vea aunque la interfaz esté oculta. Se oculta
-- al empezar cada captura, igual que el aviso de Blizzard.
local overlay = CreateFrame("Frame", "ModoFotoOverlay")
overlay:SetFrameStrata("FULLSCREEN_DIALOG")
overlay:SetSize(1000, 200)
overlay:SetPoint("CENTER", WorldFrame, "CENTER", 0, 150)
overlay:Hide()

local overlayText = overlay:CreateFontString(nil, "OVERLAY")
overlayText:SetPoint("CENTER")
overlayText:SetTextColor(1, 0.82, 0)

overlay:SetScript("OnUpdate", function(self)
	if self.hideAt and GetTime() >= self.hideAt then
		self:Hide()
	end
end)

local function ShowOverlay(text, size, seconds)
	overlayText:SetFont(FONT, size, "OUTLINE")
	overlayText:SetText(text)
	overlay.hideAt = seconds and (GetTime() + seconds) or nil
	overlay:Show()
end

--------------------------------------------------------------------------------
-- Nombres, placas y bocadillos
--------------------------------------------------------------------------------

local function HideWorldText()
	if not db.ocultarNombres or db.pendientes then
		return
	end

	local original = {}
	for _, name in ipairs(WORLD_TEXT_CVARS) do
		local value = GetCVarValue(name)
		if value ~= nil and value ~= "0" then
			original[name] = value
			SetCVarValue(name, "0")
		end
	end

	-- Queda guardado en disco: si el juego se cierra en modo foto,
	-- se restaura al volver a entrar.
	db.pendientes = original
end

local function RestoreWorldText()
	if not db.pendientes then
		return
	end
	if InCombatLockdown() then
		restoreAfterCombat = true
		return
	end

	for name, value in pairs(db.pendientes) do
		SetCVarValue(name, value)
	end
	db.pendientes = nil
end

--------------------------------------------------------------------------------
-- Entrar y salir
--------------------------------------------------------------------------------

local function CancelCountdown()
	if countdownTicker then
		countdownTicker:Cancel()
		countdownTicker = nil
	end
end

local function Enter()
	if active then
		return true
	end
	if InCombatLockdown() then
		Print("no se puede usar en combate.")
		return false
	end

	active = true
	HideWorldText()
	SetUIVisibility(false)
	return true
end

local function Exit()
	CancelCountdown()
	shotPending = false
	exitAfterShot = false
	overlay:Hide()

	if not active then
		return
	end
	active = false
	RestoreWorldText()

	-- Lo mismo que hace Blizzard al apretar Esc con la interfaz oculta.
	if not UIParent:IsShown() and not InCombatLockdown() then
		UIParent:Show()
		SetUIVisibility(true)
	end
end

--------------------------------------------------------------------------------
-- Capturas
--------------------------------------------------------------------------------

local function FinishShot()
	shotPending = false
	if exitAfterShot then
		Exit()
	end
end

local function TakeShot()
	shotId = shotId + 1
	local id = shotId
	shotPending = true
	overlay:Hide()

	-- Un instante para que el juego dibuje al menos un cuadro sin interfaz.
	C_Timer.After(0.15, function()
		if shotPending and id == shotId then
			Screenshot()
		end
	end)

	-- Por si el juego no avisa que terminó la captura.
	C_Timer.After(5, function()
		if shotPending and id == shotId then
			FinishShot()
		end
	end)
end

local function Toggle()
	if active then
		Exit()
	elseif Enter() then
		ShowOverlay("Modo foto: Impr Pant para capturar, Esc para salir", 24, 3)
	end
end

local function ShotNow()
	if shotPending or countdownTicker then
		return
	end

	local wasActive = active
	if Enter() then
		exitAfterShot = not wasActive
		TakeShot()
	end
end

local function ShotWithTimer(seconds)
	if shotPending or countdownTicker then
		return
	end

	seconds = math.floor(tonumber(seconds) or db.segundos)
	seconds = math.max(1, math.min(60, seconds))

	local wasActive = active
	if not Enter() then
		return
	end
	exitAfterShot = not wasActive

	local remaining = seconds
	ShowOverlay(tostring(remaining), 72)
	PlayTick()

	countdownTicker = C_Timer.NewTicker(1, function()
		remaining = remaining - 1
		if remaining > 0 then
			ShowOverlay(tostring(remaining), 72)
			PlayTick()
		else
			countdownTicker = nil
			TakeShot()
		end
	end, seconds)
end

local function BestQuality()
	if GetCVarValue("screenshotFormat") ~= nil then
		SetCVarValue("screenshotFormat", "png")
	end
	if GetCVarValue("screenshotQuality") ~= nil then
		SetCVarValue("screenshotQuality", "10")
	end
	Print(format("formato de captura: %s, calidad: %s.",
		tostring(GetCVarValue("screenshotFormat")),
		tostring(GetCVarValue("screenshotQuality"))))
end

-- Para los atajos de teclado (Bindings.xml).
ModoFoto_Toggle = Toggle
ModoFoto_ShotNow = ShotNow
ModoFoto_ShotWithTimer = ShotWithTimer

--------------------------------------------------------------------------------
-- Comandos
--------------------------------------------------------------------------------

local function PrintHelp()
	Print("comandos:")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto  -  entra o sale del modo foto (Impr Pant captura, Esc sale)")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto ya  -  una foto limpia ahora mismo")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto timer [segundos]  -  cuenta regresiva y foto limpia")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto tiempo <segundos>  -  cambia la duración del temporizador")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto nombres  -  ocultar o no nombres, placas y bocadillos")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto calidad  -  capturas en PNG con la máxima calidad")
	DEFAULT_CHAT_FRAME:AddMessage("  Atajos: Opciones > Atajos de teclado > AddOns > Modo Foto")
end

SLASH_MODOFOTO1 = "/foto"
SLASH_MODOFOTO2 = "/modofoto"
SlashCmdList.MODOFOTO = function(input)
	local command, argument = strsplit(" ", strtrim(input or ""):lower(), 2)

	if command == "" then
		Toggle()
	elseif command == "ya" or command == "ahora" then
		ShotNow()
	elseif command == "timer" or command == "temporizador" then
		ShotWithTimer(argument)
	elseif command == "tiempo" then
		local seconds = tonumber(argument)
		if seconds then
			db.segundos = math.max(1, math.min(60, math.floor(seconds)))
			Print(format("temporizador de %d segundos.", db.segundos))
		else
			Print(format("el temporizador está en %d segundos. Ejemplo: /foto tiempo 5", db.segundos))
		end
	elseif command == "nombres" then
		db.ocultarNombres = not db.ocultarNombres
		Print(db.ocultarNombres and "se ocultan nombres, placas y bocadillos."
			or "nombres, placas y bocadillos quedan visibles.")
	elseif command == "calidad" then
		BestQuality()
	else
		PrintHelp()
	end
end

--------------------------------------------------------------------------------
-- Eventos
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("SCREENSHOT_STARTED")
events:RegisterEvent("SCREENSHOT_SUCCEEDED")
events:RegisterEvent("SCREENSHOT_FAILED")

events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		self:UnregisterEvent("ADDON_LOADED")

		ModoFotoDB = ModoFotoDB or {}
		db = ModoFotoDB
		for key, value in pairs(DEFAULTS) do
			if db[key] == nil then
				db[key] = value
			end
		end

		-- El juego se cerró en modo foto la última vez.
		RestoreWorldText()

		-- Esc, Alt+Z o cualquier otra cosa que vuelva a mostrar la interfaz.
		UIParent:HookScript("OnShow", function()
			if active then
				Exit()
			end
		end)
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Último momento antes del bloqueo de combate: devolver la interfaz.
		if active or countdownTicker then
			Exit()
			Print("cancelado: entraste en combate.")
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if restoreAfterCombat then
			restoreAfterCombat = false
			RestoreWorldText()
		end
	elseif event == "PLAYER_LOGOUT" then
		if not InCombatLockdown() then
			RestoreWorldText()
		end
	elseif event == "SCREENSHOT_STARTED" then
		overlay:Hide()
	elseif event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
		if shotPending then
			FinishShot()
		end
	end
end)

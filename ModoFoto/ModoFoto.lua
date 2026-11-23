-- Modo Foto: capturas de pantalla limpias, sin interfaz.
-- Funciona en WoW Classic Era (1.15) y WoW Forever (1.60).

local ADDON_NAME = ...
local PREFIX = "|cff33ccffModo Foto:|r "
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

BINDING_HEADER_MODOFOTO = "Modo Foto"
BINDING_NAME_MODOFOTO_TOGGLE = "Entrar o salir del modo foto"
BINDING_NAME_MODOFOTO_SHOT = "Foto limpia ahora"
BINDING_NAME_MODOFOTO_TIMER = "Foto limpia con temporizador"
BINDING_NAME_MODOFOTO_CAM_LEFT = "Correr la cámara a la izquierda"
BINDING_NAME_MODOFOTO_CAM_RIGHT = "Correr la cámara a la derecha"
BINDING_NAME_MODOFOTO_CAM_CENTER = "Centrar la cámara"

local DEFAULTS = {
	ocultarNombres = true, -- nombres, placas y bocadillos sobre los personajes
	segundos = 3,          -- duración del temporizador
	boton = { point = "TOPRIGHT", x = -230, y = -20, oculto = false },
	-- desplazamiento: cuánto se corre la cámara a un costado (0 = personaje centrado).
	-- alejar: permitir alejar la cámara más que el máximo normal durante la foto.
	camara = { desplazamiento = 0, alejar = true },
}

local CAMERA_STEP = 0.5
local CAMERA_LIMIT = 3
local CAMERA_SETTLE = 0.8 -- segundos que tarda la cámara en terminar de moverse

-- Estas opciones dibujan sobre el mundo, no en la interfaz, así que ocultar la
-- interfaz no alcanza: se apagan mientras dura la foto. Las que no existen en
-- una versión del juego se saltean solas.
local WORLD_TEXT_CVARS = {
	-- Nombres de personajes y PNJ
	"UnitNameOwn", "UnitNameNPC", "UnitNameHostleNPC", "UnitNameInteractiveNPC",
	"UnitNameFriendlySpecialNPCName", "UnitNameNonCombatCreatureName",
	"UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName",
	"UnitNameFriendlyMinionName", "UnitNameEnemyMinionName",
	"UnitNameFriendlyPetName", "UnitNameEnemyPetName",
	"UnitNameFriendlyGuardianName", "UnitNameEnemyGuardianName",
	"UnitNameFriendlyTotemName", "UnitNameEnemyTotemName",
	"UnitNamePlayerGuild", "UnitNamePlayerPVPTitle", "UnitNameGuildTitle",
	-- Placas de vida
	"nameplateShowAll", "nameplateShowEnemies", "nameplateShowFriends",
	"nameplateShowFriendlyNPCs", "nameplateShowEnemyMinions", "nameplateShowEnemyMinus",
	"nameplateShowFriendlyMinions", "nameplateShowSelf",
	-- Íconos sobre lo que se puede seleccionar o usar (cliente de Forever)
	"SoftTargetIconGameObject", "SoftTargetIconInteract", "SoftTargetIconFriend", "SoftTargetIconEnemy",
	-- Bocadillos de chat y números de combate
	"chatBubbles", "chatBubblesParty",
	"floatingCombatTextCombatDamage", "floatingCombatTextCombatHealing",
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

-- Cuenta cuadros dibujados, para sacar la foto apenas la interfaz desaparece.
local driver = CreateFrame("Frame")

local function AfterFrames(count, callback)
	local frames = 0
	driver:SetScript("OnUpdate", function(self)
		frames = frames + 1
		if frames >= count then
			self:SetScript("OnUpdate", nil)
			callback()
		end
	end)
end

--------------------------------------------------------------------------------
-- Opciones del juego: nombres, placas, bocadillos y cámara
--------------------------------------------------------------------------------

--- Cambia una opción del juego guardando su valor original. Queda guardado en
--- disco: si el juego se cierra en modo foto, se restaura al volver a entrar.
--- Devuelve false si la opción no existe en esta versión del juego.
local function SaveAndSet(name, value)
	local current = GetCVarValue(name)
	if current == nil then
		return false
	end
	value = tostring(value)
	if current ~= value then
		db.pendientes = db.pendientes or {}
		if db.pendientes[name] == nil then
			db.pendientes[name] = current
		end
		SetCVarValue(name, value)
	end
	return true
end

local function HideWorldText()
	if not db.ocultarNombres then
		return
	end
	for _, name in ipairs(WORLD_TEXT_CVARS) do
		local value = GetCVarValue(name)
		if value ~= nil and value ~= "0" then
			SaveAndSet(name, "0")
		end
	end
end

local function RestoreSettings()
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
-- Cámara
--------------------------------------------------------------------------------

-- La cámara no se puede despegar del personaje, pero sí correr a un costado
-- (la cámara "por encima del hombro") y alejar más que el máximo normal.
local cameraSettleAt = 0

local function CameraText()
	local offset = db.camara.desplazamiento or 0
	if offset == 0 then
		return "centrada"
	end
	return format("%s %.1f", offset < 0 and "a la izquierda" or "a la derecha", math.abs(offset))
end

local function CameraAvailable()
	return GetCVarValue("test_cameraOverShoulder") ~= nil
end

local function ApplyCameraOffset(offset)
	if not CameraAvailable() then
		return false
	end
	local current = tonumber(GetCVarValue("test_cameraOverShoulder")) or 0
	if offset ~= 0 then
		-- La opción "mantener al personaje centrado" anula el desplazamiento.
		SaveAndSet("CameraKeepCharacterCentered", "0")
	end
	SaveAndSet("test_cameraOverShoulder", offset)
	if math.abs(current - offset) > 0.01 then
		cameraSettleAt = GetTime() + CAMERA_SETTLE
	end
	return true
end

local function ApplyCamera()
	local settings = db.camara
	if (settings.desplazamiento or 0) ~= 0 then
		ApplyCameraOffset(settings.desplazamiento)
	end
	if settings.alejar and GetCVarValue("cameraDistanceMaxZoomFactor") ~= nil then
		-- Se prueba de mayor a menor: cada versión del juego tiene su propio tope.
		local original = tonumber(GetCVarValue("cameraDistanceMaxZoomFactor")) or 0
		for _, factor in ipairs({ 4, 3.4, 2.6, 2 }) do
			if factor <= original then
				break
			end
			SaveAndSet("cameraDistanceMaxZoomFactor", factor)
			if (tonumber(GetCVarValue("cameraDistanceMaxZoomFactor")) or 0) >= factor - 0.01 then
				break
			end
		end
	end
end

--- Corre la cámara: delta en pasos, o nil para centrar.
local function MoveCamera(delta)
	if not CameraAvailable() then
		Print("esta versión del juego no permite correr la cámara.")
		return
	end
	local offset = delta and (db.camara.desplazamiento or 0) + delta or 0
	offset = math.max(-CAMERA_LIMIT, math.min(CAMERA_LIMIT, offset))
	db.camara.desplazamiento = offset
	if active then
		ApplyCameraOffset(offset)
		-- Con la interfaz oculta el chat no se ve: aviso breve en pantalla.
		-- Se borra solo al sacar la foto.
		ShowOverlay("Cámara " .. CameraText(), 22, 1.2)
	else
		Print("cámara " .. CameraText() .. " para el modo foto.")
	end
end

--------------------------------------------------------------------------------
-- Ventanas de otros addons que no dependen de la interfaz de Blizzard
--------------------------------------------------------------------------------

-- Algunos addons cuelgan sus ventanas fuera de la interfaz (sin padre o del
-- mundo), y por eso no desaparecen con Alt+Z. Se ocultan mientras dura la foto
-- y después se vuelven a mostrar. Las ventanas protegidas o prohibidas no se
-- tocan, para no interferir con el juego.
local hiddenFrames = {}
local ownFrames = { [overlay] = true, [driver] = true }

local function HideIfLoose(frame)
	if frame.IsForbidden and frame:IsForbidden() then
		return
	end
	if ownFrames[frame] or frame == WorldFrame or frame == UIParent then
		return
	end
	local parent = frame:GetParent()
	if parent ~= nil and parent ~= WorldFrame then
		return
	end
	if frame:IsProtected() or not frame:IsShown() then
		return
	end
	-- Solo lo que se ve: muchos addons usan marcos invisibles, de tamaño cero,
	-- para su lógica, y ocultarlos los pausaría.
	if (frame:GetWidth() or 0) < 1 or (frame:GetHeight() or 0) < 1 or (frame:GetAlpha() or 1) <= 0 then
		return
	end
	frame:Hide()
	hiddenFrames[#hiddenFrames + 1] = frame
end

local function HideLooseFrames()
	if not EnumerateFrames then
		return
	end
	local frame = EnumerateFrames()
	while frame do
		pcall(HideIfLoose, frame)
		frame = EnumerateFrames(frame)
	end
end

local function RestoreLooseFrames()
	for _, frame in ipairs(hiddenFrames) do
		pcall(frame.Show, frame)
	end
	wipe(hiddenFrames)
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
	ApplyCamera()
	SetUIVisibility(false)
	HideLooseFrames()
	return true
end

local function Exit()
	CancelCountdown()
	driver:SetScript("OnUpdate", nil)
	shotPending = false
	exitAfterShot = false
	overlay:Hide()

	if not active then
		return
	end
	active = false
	RestoreSettings()
	RestoreLooseFrames()

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

	-- Si la cámara se está corriendo, se espera a que termine; después, tres
	-- cuadros: lo justo para que el juego ya dibuje sin interfaz.
	local function shoot()
		AfterFrames(3, function()
			if shotPending and id == shotId then
				Screenshot()
			end
		end)
	end
	local wait = math.max(0, cameraSettleAt - GetTime())
	if wait > 0 then
		C_Timer.After(wait, shoot)
	else
		shoot()
	end

	-- Por si el juego no avisa que terminó la captura.
	C_Timer.After(5 + wait, function()
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
ModoFoto_CameraLeft = function() MoveCamera(-CAMERA_STEP) end
ModoFoto_CameraRight = function() MoveCamera(CAMERA_STEP) end
ModoFoto_CameraCenter = function() MoveCamera(nil) end

--------------------------------------------------------------------------------
-- Botón en pantalla
--------------------------------------------------------------------------------

-- Cuelga de la interfaz, así desaparece solo durante la foto.
local function CreateButton()
	local button = CreateFrame("Button", "ModoFotoButton", UIParent)
	button:SetSize(36, 36)
	button:SetFrameStrata("MEDIUM")
	button:SetClampedToScreen(true)
	button:SetMovable(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	local position = db.boton
	button:SetPoint(position.point, UIParent, position.point, position.x, position.y)

	button:SetScript("OnClick", function(_, mouseButton)
		GameTooltip:Hide()
		if IsControlKeyDown() then
			Toggle()
		elseif mouseButton == "RightButton" then
			ShotWithTimer()
		else
			ShotNow()
		end
	end)
	button:SetScript("OnDragStart", function(self)
		if IsShiftKeyDown() then
			self:StartMoving()
		end
	end)
	button:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		db.boton.point, db.boton.x, db.boton.y = point, x, y
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:AddLine("Modo Foto")
		GameTooltip:AddLine("Clic: foto limpia, sin nada de interfaz", 1, 1, 1)
		GameTooltip:AddLine(format("Clic derecho: foto con cuenta regresiva (%d s)", db.segundos), 1, 1, 1)
		GameTooltip:AddLine("Ctrl+clic: entrar o salir del modo foto", 1, 1, 1)
		GameTooltip:AddLine("Cámara: " .. CameraText() .. " (/foto camara)", 0.7, 0.9, 1)
		GameTooltip:AddLine("Mayús+arrastrar: mover el botón", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	if position.oculto then
		button:Hide()
	end
	return button
end

--------------------------------------------------------------------------------
-- Comandos
--------------------------------------------------------------------------------

local button

local function PrintHelp()
	Print("comandos:")
	DEFAULT_CHAT_FRAME:AddMessage("  Botón con un catalejo en pantalla: clic saca una foto limpia")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto  -  entra o sale del modo foto (Impr Pant captura, Esc sale)")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto ya  -  una foto limpia ahora mismo")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto timer [segundos]  -  cuenta regresiva y foto limpia")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto tiempo <segundos>  -  cambia la duración del temporizador")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto nombres  -  ocultar o no nombres, placas y bocadillos")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto boton  -  muestra u oculta el botón")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto camara izquierda | derecha | centro | <número de -3 a 3>  -  cámara corrida a un costado")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto lejos  -  permitir o no alejar la cámara más que lo normal")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto calidad  -  capturas en PNG con la máxima calidad")
	DEFAULT_CHAT_FRAME:AddMessage("  Atajos (foto, temporizador, correr la cámara): Opciones > Atajos de teclado > AddOns > Modo Foto")
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
	elseif command == "boton" or command == "botón" then
		db.boton.oculto = not db.boton.oculto
		if button then
			if db.boton.oculto then button:Hide() else button:Show() end
		end
		Print(db.boton.oculto and "botón oculto. Volvé a mostrarlo con /foto boton." or "botón visible.")
	elseif command == "camara" or command == "cámara" then
		local current = db.camara.desplazamiento or 0
		local target = ({ izquierda = -1.5, derecha = 1.5, centro = 0, centrar = 0 })[argument or ""]
			or tonumber(argument)
		if not CameraAvailable() then
			Print("esta versión del juego no permite correr la cámara.")
		elseif target then
			MoveCamera(target - current)
		else
			Print("cámara " .. CameraText() .. " para el modo foto. Ejemplos: /foto camara izquierda, /foto camara 2")
		end
	elseif command == "lejos" then
		db.camara.alejar = not db.camara.alejar
		Print(db.camara.alejar and "en modo foto vas a poder alejar la cámara más que lo normal."
			or "en modo foto la cámara se aleja lo normal.")
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
ownFrames[events] = true
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("SCREENSHOT_STARTED")
events:RegisterEvent("SCREENSHOT_SUCCEEDED")
events:RegisterEvent("SCREENSHOT_FAILED")

local function CopyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = {}
				CopyDefaults(target[key], value)
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" then
			CopyDefaults(target[key], value)
		end
	end
end

events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		self:UnregisterEvent("ADDON_LOADED")

		ModoFotoDB = ModoFotoDB or {}
		db = ModoFotoDB
		CopyDefaults(db, DEFAULTS)

		-- El juego se cerró en modo foto la última vez.
		RestoreSettings()

		button = CreateButton()

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
			RestoreSettings()
		end
	elseif event == "PLAYER_LOGOUT" then
		if not InCombatLockdown() then
			RestoreSettings()
		end
	elseif event == "SCREENSHOT_STARTED" then
		overlay:Hide()
	elseif event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
		if shotPending then
			FinishShot()
		end
	end
end)

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
	aviso = true,          -- mensaje en el chat al entrar al juego
	segundos = 3,          -- duración del temporizador
	boton = { point = "TOPRIGHT", x = -230, y = -20, oculto = false },
	-- desplazamiento: cuánto se corre la cámara a un costado (0 = personaje centrado).
	-- alejar: permitir alejar la cámara más que el máximo normal durante la foto.
	camara = { desplazamiento = 0, alejar = true },
	-- Control de cámara en pantalla durante el modo foto.
	joystick = { oculto = false, invertir = false, point = "RIGHT", relativePoint = "RIGHT", x = -40, y = -40 },
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

--------------------------------------------------------------------------------
-- Control de cámara en pantalla (joystick)
--------------------------------------------------------------------------------

-- Sin padre, para que se vea con la interfaz oculta. Aparece solo en el modo
-- foto (y durante la cuenta regresiva) y se oculta antes de cada captura, así
-- nunca sale en la foto.
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local STICK_SIZE = 120
local KNOB_SIZE = 44
local STICK_RANGE = (STICK_SIZE - KNOB_SIZE) / 2 -- recorrido de la palanca
local DEAD_ZONE = 0.15
local SHIFT_SPEED = 2.5 -- desplazamiento por segundo con la palanca a fondo
local TILT_SPEED = 0.6  -- inclinación con la palanca a fondo
local TURN_SPEED = 0.25 -- giro de los botones
local GOLD = { 1, 0.82, 0 }

local pad
local MoveCamera -- más abajo
local motion = { tilt = nil, tiltSpeed = 0, turn = nil }

local function CallIfExists(name, ...)
	local func = _G[name]
	if type(func) == "function" then
		func(...)
	end
end

local function StopTilt()
	if motion.tilt then
		CallIfExists("MoveViewUpStop")
		CallIfExists("MoveViewDownStop")
		motion.tilt, motion.tiltSpeed = nil, 0
	end
end

--- amount de -1 a 1: positivo sube la cámara.
local function Tilt(amount)
	if db.joystick.invertir then
		amount = -amount
	end
	if math.abs(amount) < DEAD_ZONE then
		StopTilt()
		return
	end
	local direction = amount > 0 and "Up" or "Down"
	local speed = math.floor(math.abs(amount) * TILT_SPEED * 20 + 0.5) / 20
	if direction ~= motion.tilt or speed ~= motion.tiltSpeed then
		StopTilt()
		CallIfExists("MoveView" .. direction .. "Start", speed)
		motion.tilt, motion.tiltSpeed = direction, speed
	end
end

local function StopTurn()
	if motion.turn then
		CallIfExists("MoveView" .. motion.turn .. "Stop")
		motion.turn = nil
	end
end

local function Turn(direction)
	StopTurn()
	CallIfExists("MoveView" .. direction .. "Start", TURN_SPEED)
	motion.turn = direction
end

local function PadStatus(text)
	if pad then
		pad.status:SetText(text or ("Cámara " .. CameraText()))
	end
end

local function ShiftBy(delta)
	if not CameraAvailable() then
		return
	end
	local offset = (db.camara.desplazamiento or 0) + delta
	offset = math.max(-CAMERA_LIMIT, math.min(CAMERA_LIMIT, offset))
	db.camara.desplazamiento = offset
	-- No hace falta tocar la opción en cada cuadro.
	if math.abs(offset - (pad.applied or 0)) >= 0.05 or math.abs(offset) == CAMERA_LIMIT then
		ApplyCameraOffset(offset)
		pad.applied = offset
	end
	PadStatus()
end

local function CenterKnob()
	pad.knob:ClearAllPoints()
	pad.knob:SetPoint("CENTER", pad.stick, "CENTER", 0, 0)
end

local function ReleaseStick()
	if not pad or not pad.dragging then
		return
	end
	pad.dragging = false
	CenterKnob()
	StopTilt()
	if CameraAvailable() then
		ApplyCameraOffset(db.camara.desplazamiento or 0)
		pad.applied = db.camara.desplazamiento
	end
	PadStatus()
end

local function StopAllMotion()
	ReleaseStick()
	StopTilt()
	StopTurn()
end

local function UpdateStick(_, elapsed)
	if not pad.dragging then
		if motion.turn and IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
			StopTurn()
		end
		return
	end
	if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
		ReleaseStick()
		return
	end
	local scale = pad.stick:GetEffectiveScale()
	local x, y = GetCursorPosition()
	local cx, cy = pad.stick:GetCenter()
	local dx, dy = x / scale - cx, y / scale - cy
	local distance = math.sqrt(dx * dx + dy * dy)
	if distance > STICK_RANGE then
		dx, dy = dx * STICK_RANGE / distance, dy * STICK_RANGE / distance
	end
	pad.knob:ClearAllPoints()
	pad.knob:SetPoint("CENTER", pad.stick, "CENTER", dx, dy)

	local horizontal, vertical = dx / STICK_RANGE, dy / STICK_RANGE
	if math.abs(horizontal) >= DEAD_ZONE then
		ShiftBy(horizontal * SHIFT_SPEED * (elapsed or 0))
	end
	Tilt(vertical)
end

local function Zoom(_, delta)
	CallIfExists(delta > 0 and "CameraZoomIn" or "CameraZoomOut", 1)
end

--- Fondo con esquinas redondeadas que se estira a cualquier tamaño.
local function RoundedBackground(frame)
	local corner = 12
	local edge = corner / 32
	local function Piece(left, right, top, bottom)
		local texture = frame:CreateTexture(nil, "BACKGROUND")
		texture:SetTexture(MEDIA .. "panel.tga")
		texture:SetTexCoord(left, right, top, bottom)
		return texture
	end
	for _, corners in ipairs({ { "TOPLEFT", 0, edge, 0, edge }, { "TOPRIGHT", 1 - edge, 1, 0, edge },
		{ "BOTTOMLEFT", 0, edge, 1 - edge, 1 }, { "BOTTOMRIGHT", 1 - edge, 1, 1 - edge, 1 } }) do
		local texture = Piece(corners[2], corners[3], corners[4], corners[5])
		texture:SetSize(corner, corner)
		texture:SetPoint(corners[1])
	end
	local top = Piece(edge, 1 - edge, 0, edge)
	top:SetPoint("TOPLEFT", corner, 0)
	top:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -corner, -corner)
	local bottom = Piece(edge, 1 - edge, 1 - edge, 1)
	bottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", corner, corner)
	bottom:SetPoint("BOTTOMRIGHT", -corner, 0)
	local middle = Piece(0, 1, edge, 1 - edge)
	middle:SetPoint("TOPLEFT", 0, -corner)
	middle:SetPoint("BOTTOMRIGHT", 0, corner)
end

local function MakeButton(parent, size, glyph, hint, flip)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)
	if glyph ~= "close" then
		local background = button:CreateTexture(nil, "BACKGROUND")
		background:SetAllPoints()
		background:SetTexture(MEDIA .. "button.tga")
	end
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("CENTER")
	icon:SetSize(size * 0.72, size * 0.72)
	icon:SetTexture(MEDIA .. glyph .. ".tga")
	if flip then
		icon:SetTexCoord(1, 0, 0, 1)
	end
	button.icon = icon
	button:SetScript("OnEnter", function()
		icon:SetVertexColor(unpack(GOLD))
		PadStatus(hint)
	end)
	button:SetScript("OnLeave", function()
		icon:SetVertexColor(1, 1, 1)
		PadStatus()
	end)
	return button
end

local function SavePadPosition()
	local point, _, relativePoint, x, y = pad:GetPoint()
	local settings = db.joystick
	settings.point, settings.relativePoint, settings.x, settings.y = point, relativePoint or point, x, y
end

local function CreatePad()
	local frame = CreateFrame("Frame", "ModoFotoJoystick")
	frame:SetSize(168, 236)
	frame:SetFrameStrata("FULLSCREEN")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:RegisterForDrag("LeftButton")
	frame:Hide()
	pad = frame
	RoundedBackground(frame)

	local function StartMoving()
		if IsShiftKeyDown() then
			frame:StartMoving()
		end
	end
	local function StopMoving()
		frame:StopMovingOrSizing()
		SavePadPosition()
	end
	frame:SetScript("OnDragStart", StartMoving)
	frame:SetScript("OnDragStop", StopMoving)
	frame:SetScript("OnMouseWheel", Zoom)
	frame:SetScript("OnUpdate", UpdateStick)
	frame:SetScript("OnHide", StopAllMotion)

	local title = frame:CreateFontString(nil, "OVERLAY")
	title:SetFont(FONT, 12, "OUTLINE")
	title:SetTextColor(unpack(GOLD))
	title:SetPoint("TOPLEFT", 12, -9)
	title:SetText("Cámara")

	local close = MakeButton(frame, 18, "close", "Salir del modo foto")
	close:SetPoint("TOPRIGHT", -7, -6)
	close:SetScript("OnClick", function() ModoFoto_Toggle() end)
	frame.close1 = close

	-- La palanca: a los costados corre la cámara, arriba y abajo la inclina.
	local stick = CreateFrame("Frame", nil, frame)
	stick:SetSize(STICK_SIZE, STICK_SIZE)
	stick:SetPoint("TOP", 0, -28)
	stick:EnableMouse(true)
	stick:EnableMouseWheel(true)
	stick:RegisterForDrag("LeftButton")
	stick:SetScript("OnDragStart", StartMoving)
	stick:SetScript("OnDragStop", StopMoving)
	stick:SetScript("OnMouseWheel", Zoom)
	local base = stick:CreateTexture(nil, "BORDER")
	base:SetAllPoints()
	base:SetTexture(MEDIA .. "base.tga")
	local knob = stick:CreateTexture(nil, "ARTWORK")
	knob:SetSize(KNOB_SIZE, KNOB_SIZE)
	knob:SetTexture(MEDIA .. "knob.tga")
	frame.stick, frame.knob = stick, knob
	CenterKnob()
	stick:SetScript("OnMouseDown", function(_, mouseButton)
		if mouseButton == "LeftButton" and not IsShiftKeyDown() then
			frame.dragging = true
			frame.applied = db.camara.desplazamiento or 0
		end
	end)
	stick:SetScript("OnMouseUp", ReleaseStick)
	stick:SetScript("OnEnter", function()
		PadStatus("Correr e inclinar la cámara")
	end)
	stick:SetScript("OnLeave", function()
		if not frame.dragging then
			PadStatus()
		end
	end)

	-- Botones: girar, centrar, foto, girar.
	local buttons = {
		{ "rotate", "Girar (mantené apretado)", false, "Left" },
		{ "center", "Centrar al personaje", false },
		{ "shot", "Sacar la foto", false },
		{ "rotate", "Girar (mantené apretado)", true, "Right" },
	}
	for index, info in ipairs(buttons) do
		local button = MakeButton(frame, 30, info[1], info[2], info[3])
		button:SetPoint("TOP", frame, "TOP", -54 + (index - 1) * 36, -156)
		if info[4] then
			button:SetScript("OnMouseDown", function() Turn(info[4]) end)
			button:SetScript("OnMouseUp", StopTurn)
		elseif info[1] == "center" then
			button:SetScript("OnClick", function() MoveCamera(nil) end)
		else
			button.icon:SetVertexColor(unpack(GOLD))
			button:SetScript("OnLeave", function() PadStatus() end)
			button:SetScript("OnClick", function() ModoFoto_ShotNow() end)
		end
		frame[info[1] .. index] = button
	end

	local status = frame:CreateFontString(nil, "OVERLAY")
	status:SetFont(FONT, 10, "OUTLINE")
	status:SetPoint("TOP", 0, -191)
	status:SetWidth(156)
	status:SetTextColor(1, 1, 1)
	frame.status = status

	local hint = frame:CreateFontString(nil, "OVERLAY")
	hint:SetFont(FONT, 9, "OUTLINE")
	hint:SetPoint("TOP", 0, -207)
	hint:SetTextColor(0.75, 0.75, 0.75)
	hint:SetText("Rueda: acercar o alejar\nMayús+arrastrar: mover")

	return frame
end

local function ShowPad()
	if not active or db.joystick.oculto then
		return
	end
	if not pad then
		CreatePad()
	end
	-- Mismo tamaño que la interfaz, aunque no cuelgue de ella.
	pad:SetScale(UIParent:GetEffectiveScale())
	local settings = db.joystick
	pad:ClearAllPoints()
	pad:SetPoint(settings.point, WorldFrame, settings.relativePoint, settings.x, settings.y)
	PadStatus()
	pad:Show()
end

local function HidePad()
	if pad then
		pad:Hide()
	end
end

--- Corre la cámara: delta en pasos, o nil para centrar.
function MoveCamera(delta)
	if not CameraAvailable() then
		Print("esta versión del juego no permite correr la cámara.")
		return
	end
	local offset = delta and (db.camara.desplazamiento or 0) + delta or 0
	offset = math.max(-CAMERA_LIMIT, math.min(CAMERA_LIMIT, offset))
	db.camara.desplazamiento = offset
	if active then
		ApplyCameraOffset(offset)
		if pad and pad:IsShown() then
			PadStatus()
		else
			-- Con la interfaz oculta el chat no se ve: aviso breve en pantalla.
			-- Se borra solo al sacar la foto.
			ShowOverlay("Cámara " .. CameraText(), 22, 1.2)
		end
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
-- Impr Pant en el modo foto
--------------------------------------------------------------------------------

-- En el modo foto, la tecla de captura del juego pasa por el addon: así se
-- ocultan el control de cámara y los avisos antes de sacar la foto.
local keyOwner = CreateFrame("Frame")
ownFrames[keyOwner] = true
local keysCaptured = false
local releaseKeysAfterCombat = false

local function CaptureScreenshotKeys()
	if keysCaptured or not (SetOverrideBinding and GetBindingKey) then
		return
	end
	for _, key in ipairs({ GetBindingKey("SCREENSHOT") }) do
		SetOverrideBinding(keyOwner, true, key, "MODOFOTO_SHOT")
	end
	keysCaptured = true
end

local function ReleaseScreenshotKeys()
	if not keysCaptured then
		return
	end
	if InCombatLockdown() then
		releaseKeysAfterCombat = true
		return
	end
	ClearOverrideBindings(keyOwner)
	keysCaptured = false
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

local Exit

local function Enter()
	if active then
		return true
	end
	if InCombatLockdown() then
		Print("no se puede usar en combate.")
		return false
	end

	active = true
	local ok, problem = pcall(function()
		HideWorldText()
		ApplyCamera()
		SetUIVisibility(false)
		HideLooseFrames()
		CaptureScreenshotKeys()
	end)
	if not ok then
		Exit() -- deja todo como estaba
		Print("no pude entrar al modo foto: " .. tostring(problem))
		return false
	end
	return true
end

function Exit()
	CancelCountdown()
	driver:SetScript("OnUpdate", nil)
	shotPending = false
	exitAfterShot = false
	overlay:Hide()
	HidePad()

	if not active then
		return
	end
	active = false
	ReleaseScreenshotKeys()
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
	else
		ShowPad()
	end
end

local function TakeShot()
	shotId = shotId + 1
	local id = shotId
	shotPending = true
	overlay:Hide()
	HidePad()

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
		local stuck = UIParent:IsShown() -- marcado como activo, pero la interfaz está a la vista
		Exit()
		if not stuck then
			return
		end
	end
	if Enter() then
		ShowPad()
		ShowOverlay("Modo foto: Impr Pant o el botón de la cámara para la foto, Esc para salir", 24, 3)
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
	ShowPad() -- para acomodar la cámara durante la cuenta regresiva

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
ModoFoto_ToggleJoystick = function()
	db.joystick.oculto = not db.joystick.oculto
	if db.joystick.oculto then HidePad() else ShowPad() end
	Print(db.joystick.oculto and "control de cámara oculto. Volvé a mostrarlo con /foto joystick."
		or "en el modo foto aparece el control de cámara.")
end

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
	DEFAULT_CHAT_FRAME:AddMessage("  /foto joystick  -  muestra u oculta el control de cámara del modo foto")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto joystick invertir  -  invierte arriba y abajo de la palanca")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto calidad  -  capturas en PNG con la máxima calidad")
	DEFAULT_CHAT_FRAME:AddMessage("  /foto aviso  -  mostrar o no el aviso al entrar al juego")
	DEFAULT_CHAT_FRAME:AddMessage("  Atajos (foto, temporizador, correr la cámara): Opciones > Atajos de teclado > AddOns > Modo Foto")
end

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

local function InitDB()
	ModoFotoDB = ModoFotoDB or {}
	db = ModoFotoDB
	CopyDefaults(db, DEFAULTS)
end

--- Otro addon que también usa /foto (el juego elige uno solo).
local function OtherSlashOwner()
	for key, value in pairs(_G) do
		if type(key) == "string" and type(value) == "string" and value:lower() == "/foto"
			and key:find("^SLASH_") and not key:find("^SLASH_MODOFOTO") then
			return key:match("^SLASH_(.-)%d*$")
		end
	end
end

local HandleSlash

SLASH_MODOFOTO1 = "/foto"
SLASH_MODOFOTO2 = "/modofoto"
SLASH_MODOFOTO3 = "/fotos"
SlashCmdList.MODOFOTO = function(input)
	if not db then
		InitDB() -- por si la carga del addon no llegó a terminar
	end
	-- El juego oculta los errores de los addons: si algo falla, que se vea en el chat.
	local ok, problem = pcall(HandleSlash, input)
	if not ok then
		Print("algo falló: " .. tostring(problem))
	end
end

function HandleSlash(input)
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
	elseif command == "joystick" or command == "control" then
		if argument == "invertir" then
			db.joystick.invertir = not db.joystick.invertir
			Print(db.joystick.invertir and "palanca invertida: arriba baja la cámara." or "palanca normal: arriba sube la cámara.")
		else
			ModoFoto_ToggleJoystick()
		end
	elseif command == "lejos" then
		db.camara.alejar = not db.camara.alejar
		Print(db.camara.alejar and "en modo foto vas a poder alejar la cámara más que lo normal."
			or "en modo foto la cámara se aleja lo normal.")
	elseif command == "aviso" then
		db.aviso = not db.aviso
		Print(db.aviso and "vas a ver el aviso al entrar al juego." or "sin aviso al entrar al juego.")
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

events:RegisterEvent("PLAYER_LOGIN")

events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		self:UnregisterEvent("ADDON_LOADED")

		InitDB()

		-- El juego se cerró en modo foto la última vez.
		RestoreSettings()

		button = CreateButton()

		-- Esc, Alt+Z o cualquier otra cosa que vuelva a mostrar la interfaz.
		UIParent:HookScript("OnShow", function()
			if active then
				Exit()
			end
		end)
	elseif event == "PLAYER_LOGIN" then
		local other = OtherSlashOwner()
		if other then
			Print(format("listo. Otro addon (%s) también usa /foto: usá /modofoto o /fotos.", other))
		elseif db and db.aviso then
			Print("listo. Escribí /foto para entrar al modo foto (o Ctrl+clic en el catalejo). /foto ayuda para más.")
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Último momento antes del bloqueo de combate: devolver la interfaz.
		if active or countdownTicker then
			Exit()
			Print("cancelado: entraste en combate.")
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if releaseKeysAfterCombat then
			releaseKeysAfterCombat = false
			ReleaseScreenshotKeys()
		end
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
		HidePad()
	elseif event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
		if shotPending then
			FinishShot()
		elseif active and not countdownTicker then
			ShowPad()
		end
	end
end)

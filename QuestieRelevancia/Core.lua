-- Questie Relevancia: ordena las misiones por relevancia y prioridad.

local ADDON_NAME, QR = ...

QR.PREFIX = "|cffffd100Questie Relevancia:|r "

BINDING_HEADER_QUESTIERELEVANCIA = "Questie Relevancia"
BINDING_NAME_QUESTIERELEVANCIA_TOGGLE = "Mostrar u ocultar la ventana"

-- Pesos de cada criterio, de 0 (no importa) a 2 (lo más importante).
QR.PRESETS = {
	{ key = "equilibrado", name = "Equilibrado",
		weights = { xp = 1.0, historia = 0.8, cadena = 0.8, equipo = 0.9, oro = 0.4, clase = 1.0, mazmorra = 0.5 } },
	{ key = "rapido", name = "Subir rápido",
		weights = { xp = 1.5, historia = 0.3, cadena = 0.6, equipo = 0.5, oro = 0.2, clase = 0.8, mazmorra = 0.3 } },
	{ key = "equipo", name = "Equipo",
		weights = { xp = 0.7, historia = 0.4, cadena = 0.6, equipo = 1.5, oro = 0.3, clase = 0.9, mazmorra = 0.9 } },
	{ key = "historia", name = "Historia",
		weights = { xp = 0.6, historia = 1.5, cadena = 1.3, equipo = 0.5, oro = 0.2, clase = 0.9, mazmorra = 0.5 } },
	{ key = "oro", name = "Oro",
		weights = { xp = 0.6, historia = 0.3, cadena = 0.5, equipo = 0.6, oro = 1.5, clase = 0.6, mazmorra = 0.4 } },
}

local DEFAULTS = {
	preset = "equilibrado",
	custom = {},      -- pesos cambiados a mano con /qr peso
	tab = "log",
	filter = "todas",
	tracker = true,   -- puntaje e íconos en el seguimiento de Questie
	sortTracker = true, -- ordenar el seguimiento de Questie por relevancia
	minimap = { angle = 210, hide = false },
	levelRange = "mio",
	levelFlags = { hechas = false, bloqueadas = true, relleno = true },
	dungeonMode = "mio",
	gearFilter = "todas",
}

local db
QR.results = { log = {}, recomendadas = {}, resto = {} }
QR.version = 0

function QR.Print(message)
	DEFAULT_CHAT_FRAME:AddMessage(QR.PREFIX .. message)
end

function QR.GetPreset(key)
	for _, preset in ipairs(QR.PRESETS) do
		if preset.key == key then
			return preset
		end
	end
	return QR.PRESETS[1]
end

function QR.Weights()
	local weights = {}
	for name, value in pairs(QR.GetPreset(db.preset).weights) do
		weights[name] = db.custom[name] or value
	end
	return weights
end

function QR.DB()
	return db
end

--------------------------------------------------------------------------------
-- Cálculo
--------------------------------------------------------------------------------

local evalCache = {}

--- Puntúa una misión con el contexto actual, guardando el resultado hasta el
--- próximo cálculo. Una misión con datos raros no frena al resto.
function QR.Evaluate(questId, inLog)
	local key = (inLog and "L" or "A") .. questId
	local cached = evalCache[key]
	if cached ~= nil then
		return cached or nil
	end
	local ok, result = pcall(QR.Scoring.Evaluate, questId, QR.context, inLog)
	if not ok then
		if not QR.lastError then
			QR.lastError = result
			QR.Print("no pude evaluar la misión " .. questId .. ": " .. tostring(result))
		end
		result = nil
	end
	evalCache[key] = result or false
	return result
end

local function Evaluate(set, inLog, exclude)
	local list = {}
	for questId in pairs(set) do
		if not (exclude and exclude[questId]) then
			list[#list + 1] = QR.Evaluate(questId, inLog)
		end
	end
	return list
end

--- Recalcula los puntajes. Sin full, solo las misiones del registro (para el
--- seguimiento de Questie); con full, también las disponibles.
function QR.Recalculate(full)
	local D, S = QR.Data, QR.Scoring
	if not QR.Index.ready then
		return false
	end

	QR.version = QR.version + 1
	evalCache = {}
	QR.viewCache = {}
	QR.context = S.NewContext(D, QR.Weights())

	local log = D.LogQuests()
	local available = D.AvailableQuests()
	local tagQuests = {}
	for questId in pairs(log) do tagQuests[questId] = true end
	for questId in pairs(available) do tagQuests[questId] = true end
	D.tagQuests = tagQuests
	QR.logSet, QR.availableSet = log, available

	local logResults = S.Sort(Evaluate(log, true))
	local recommended, rest = {}, {}
	if full then
		for _, result in ipairs(Evaluate(available, false, log)) do
			if S.IsRecommended(result) then
				recommended[#recommended + 1] = result
			else
				rest[#rest + 1] = result
			end
		end
	end
	QR.results = { log = logResults, recomendadas = S.Sort(recommended), resto = S.Sort(rest) }

	if QR.Tracker.SetResults(logResults) and (db.tracker or db.sortTracker) then
		QR.Tracker.Refresh()
	end
	return true
end

--------------------------------------------------------------------------------
-- Datos de cada pestaña
--------------------------------------------------------------------------------

QR.viewCache = {}
local levelJob

local function LevelKey()
	local flags = db.levelFlags
	return format("%s:%s%s%s", db.levelRange, flags.hechas and 1 or 0, flags.bloqueadas and 1 or 0,
		flags.relleno and 1 or 0)
end

local levelCache = {} -- key -> {version, view}; sobrevive a los recálculos

--- La lista de la pestaña Por nivel. Se calcula en segundo plano: mientras
--- tanto devuelve la versión anterior (o nil la primera vez).
function QR.LevelView()
	local key = LevelKey()
	local cached = levelCache[key]
	if cached and cached.version == QR.version then
		return cached.view
	end
	if levelJob and levelJob.key == key then
		return cached and cached.view -- ya se está calculando
	end
	local range
	for _, r in ipairs(QR.Views.LEVEL_RANGES) do
		if r.key == db.levelRange then range = r end
	end
	range = range or QR.Views.LEVEL_RANGES[1]
	local job = { key = key, version = QR.version }
	levelJob = job
	local result
	QR.Index.RunSliced(function(Pause)
		local list, count = QR.Views.LevelList(QR.context, range, db.levelFlags, QR.logSet, QR.availableSet,
			function(questId, inLog)
				local r = QR.Evaluate(questId, inLog)
				Pause()
				return r
			end)
		result = { list = list, count = count }
	end, function(ok, err)
		if levelJob ~= job then
			return
		end
		levelJob = nil
		-- Aunque haya habido un recálculo mientras tanto, se guarda con la versión
		-- con la que empezó: se muestra igual y el próximo pedido lo actualiza.
		levelCache[key] = { version = job.version, view = result or { list = {}, count = 0, error = err } }
		if QR.UI and QR.UI:IsShown() then
			QR.UI:Update()
		end
	end)
	return cached and cached.view
end

function QR.DungeonView()
	local key = "mazmorra:" .. db.dungeonMode .. ":" .. tostring(QR.selectedDungeon and QR.selectedDungeon.areaId)
	local cached = QR.viewCache[key]
	if cached then
		return cached
	end
	local view
	if QR.selectedDungeon then
		view = { plan = QR.Views.DungeonPlan(QR.context, QR.selectedDungeon, QR.logSet, QR.availableSet, QR.Evaluate) }
	else
		local list = {}
		for _, entry in ipairs(QR.Views.DungeonList(QR.context)) do
			if db.dungeonMode == "todas" or entry.forYou then
				list[#list + 1] = entry
			end
		end
		view = { dungeons = list }
	end
	QR.viewCache[key] = view
	return view
end

function QR.GearView()
	local cached = QR.viewCache.equipo
	if cached then
		return cached
	end
	cached = QR.Views.Gear(QR.context)
	QR.viewCache.equipo = cached
	return cached
end

--------------------------------------------------------------------------------
-- Actualizaciones
--------------------------------------------------------------------------------

local refreshPending = false

--- Pide una actualización; varias seguidas se juntan en una sola.
function QR.RequestRefresh(delay)
	if refreshPending or not QR.started then
		return
	end
	local windowOpen = QR.UI and QR.UI:IsShown()
	if not windowOpen and not db.tracker and not db.sortTracker then
		return
	end
	refreshPending = true
	C_Timer.After(delay or 0.5, function()
		refreshPending = false
		local open = QR.UI and QR.UI:IsShown()
		if QR.Recalculate(open) and open then
			QR.UI:Update()
		end
	end)
end

local function StartIndex()
	if QR.Index.ready or QR.Index.building then
		return
	end
	QR.Index.Build(QR.Data, function(ok)
		if not ok then
			QR.Print("no pude leer la base de datos de Questie: " .. tostring(QR.Index.error))
			return
		end
		local open = QR.UI and QR.UI:IsShown()
		QR.Recalculate(open)
		if open then
			QR.UI:Update()
		end
	end)
end

function QR.Toggle(tab)
	if not QR.started then
		QR.Print("esperando a que Questie termine de cargar...")
		return
	end
	if tab then
		db.tab = tab
		if QR.UI:IsShown() then
			QR.UI:Update()
			return
		end
	end
	QR.UI:Toggle()
	if QR.UI:IsShown() then
		StartIndex()
		if QR.Recalculate(true) then
			QR.UI:Update()
		end
	end
end

function QR.ToggleTrackerBadges()
	db.tracker = not db.tracker
	QR.Print(db.tracker and "puntaje e íconos en el seguimiento de Questie: activados."
		or "puntaje e íconos en el seguimiento de Questie: desactivados.")
	if db.tracker then
		QR.RequestRefresh(0)
	end
	QR.Tracker.Refresh()
	if QR.UI then QR.UI:Update() end
end

function QR.ToggleTrackerSort()
	db.sortTracker = not db.sortTracker
	QR.Print(db.sortTracker and "el seguimiento de Questie se ordena por relevancia."
		or "el seguimiento de Questie vuelve a su orden normal.")
	QR.Tracker.Refresh()
	if QR.UI then QR.UI:Update() end
end

-- Para el atajo de teclado (Bindings.xml).
function QuestieRelevancia_Toggle()
	QR.Toggle()
end

--------------------------------------------------------------------------------
-- Comandos
--------------------------------------------------------------------------------

local function PrintHelp()
	QR.Print("comandos (también con /qrel o /relevancia):")
	local lines = {
		"/qr  -  abre o cierra la ventana",
		"/qr nivel | mazmorra | equipo  -  abre esa pestaña",
		"/qr seguimiento  -  puntaje e íconos en la barra de Questie (sí/no)",
		"/qr orden  -  ordenar la barra de Questie por relevancia (sí/no)",
		"/qr minimapa  -  muestra u oculta el botón del minimapa",
		"/qr perfil <equilibrado|rapido|equipo|historia|oro>  -  cambia qué se prioriza",
		"/qr peso <xp|historia|cadena|equipo|oro|clase|mazmorra> <0 a 2>  -  ajusta un criterio",
		"/qr pesos  -  muestra los pesos actuales",
		"/qr reiniciar  -  vuelve a los pesos del perfil",
	}
	for _, line in ipairs(lines) do
		DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
	end
end

local function PrintWeights()
	local weights = QR.Weights()
	local parts = {}
	for _, name in ipairs(QR.Scoring.COMPONENTS) do
		parts[#parts + 1] = format("%s %.1f", QR.Scoring.LABELS[name], weights[name])
	end
	QR.Print(format("perfil %s: %s", QR.GetPreset(db.preset).name, table.concat(parts, ", ")))
end

local TAB_COMMANDS = { nivel = "nivel", mazmorra = "mazmorra", mazmorras = "mazmorra", equipo = "equipo",
	misiones = "log", recomendadas = "recomendadas", resto = "resto" }

local function HandleSlash(input)
	local command, arg1, arg2 = strsplit(" ", strtrim(input or ""):lower(), 3)
	if command == "" then
		QR.Toggle()
	elseif TAB_COMMANDS[command] then
		QR.Toggle(TAB_COMMANDS[command])
	elseif command == "seguimiento" or command == "barra" then
		QR.ToggleTrackerBadges()
	elseif command == "orden" then
		QR.ToggleTrackerSort()
	elseif command == "minimapa" then
		db.minimap.hide = not db.minimap.hide
		if QR.minimapButton then
			if db.minimap.hide then QR.minimapButton:Hide() else QR.minimapButton:Show() end
		end
	elseif command == "perfil" then
		for _, preset in ipairs(QR.PRESETS) do
			if preset.key == arg1 then
				db.preset = preset.key
				wipe(db.custom)
				PrintWeights()
				QR.RequestRefresh(0)
				if QR.UI then QR.UI:Update() end
				return
			end
		end
		QR.Print("perfiles: equilibrado, rapido, equipo, historia, oro.")
	elseif command == "peso" then
		local value = tonumber(arg2)
		if arg1 and QR.Scoring.LABELS[arg1] and arg1 ~= "relleno" and value then
			db.custom[arg1] = math.max(0, math.min(2, value))
			PrintWeights()
			QR.RequestRefresh(0)
		else
			QR.Print("ejemplo: /qr peso historia 1.5")
		end
	elseif command == "pesos" then
		PrintWeights()
	elseif command == "reiniciar" then
		wipe(db.custom)
		PrintWeights()
		QR.RequestRefresh(0)
	else
		PrintHelp()
	end
end

SLASH_QUESTIERELEVANCIA1 = "/qr"
SLASH_QUESTIERELEVANCIA2 = "/qrel"
SLASH_QUESTIERELEVANCIA3 = "/relevancia"
SlashCmdList.QUESTIERELEVANCIA = HandleSlash

-- Otro addon (por ejemplo una versión vieja de este) puede usar /qr también.
local function OtherSlashOwner()
	for key, value in pairs(_G) do
		if type(key) == "string" and type(value) == "string" and value:lower() == "/qr"
			and key:find("^SLASH_") and not key:find("^SLASH_QUESTIERELEVANCIA") then
			return key:match("^SLASH_(.-)%d*$")
		end
	end
end

--------------------------------------------------------------------------------
-- Eventos
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")

local function OnQuestieReady()
	if QR.started then
		return
	end
	if not QR.Data.Init() then
		QR.Print("no encontré la base de datos de Questie (QuestieDB). Instalá Questie completo.")
		return
	end
	QR.started = true
	QR.UI = QR.CreateWindow()
	QR.minimapButton = QR.CreateMinimapButton()
	QR.Tracker.Install()

	local other = OtherSlashOwner()
	if other then
		QR.Print(format("listo. Otro addon (%s) también usa /qr: abrí esta ventana con /qrel o con el botón del minimapa.",
			other))
	else
		QR.Print("listo. Abrí la ventana con /qr o con el botón del minimapa.")
	end

	if Questie.API.RegisterForQuestUpdates then
		pcall(Questie.API.RegisterForQuestUpdates, function()
			QR.RequestRefresh()
		end)
	end
	events:RegisterEvent("QUEST_LOG_UPDATE")
	events:RegisterEvent("PLAYER_LEVEL_UP")
	events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")

	-- El índice se arma en segundo plano para tener el puntaje en el seguimiento.
	StartIndex()
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

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		QuestieRelevanciaDB = QuestieRelevanciaDB or {}
		db = QuestieRelevanciaDB
		-- custom guarda pesos sueltos: no se completa con valores por defecto.
		if db.custom == nil then db.custom = {} end
		CopyDefaults(db, DEFAULTS)
	elseif event == "PLAYER_LOGIN" then
		if not Questie or not Questie.API or not Questie.API.RegisterOnReady then
			QR.Print("necesita Questie instalado y activado.")
			return
		end
		Questie.API.RegisterOnReady(OnQuestieReady)
	elseif event == "PLAYER_REGEN_ENABLED" then
		QR.Tracker.OnCombatEnded()
	elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_EQUIPMENT_CHANGED" then
		QR.RequestRefresh(1)
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		QR.RequestRefresh(2)
	else
		QR.RequestRefresh()
	end
end)

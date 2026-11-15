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
}

local db
QR.results = { log = {}, recomendadas = {}, resto = {} }

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

local function Evaluate(set, ctx, inLog, exclude)
	local list = {}
	for questId in pairs(set) do
		if not (exclude and exclude[questId]) then
			local ok, result = pcall(QR.Scoring.Evaluate, questId, ctx, inLog)
			if ok and result then
				list[#list + 1] = result
			elseif not ok and not QR.lastError then
				-- Una misión con datos raros no frena al resto; se avisa una sola vez.
				QR.lastError = result
				QR.Print("no pude evaluar la misión " .. questId .. ": " .. tostring(result))
			end
		end
	end
	return list
end

function QR.Recalculate()
	local D, S = QR.Data, QR.Scoring
	if not QR.Index.ready then
		return false
	end

	local ctx = S.NewContext(D, QR.Weights())
	local log = D.LogQuests()
	local recommended, rest = {}, {}
	for _, result in ipairs(Evaluate(D.AvailableQuests(), ctx, false, log)) do
		if S.IsRecommended(result) then
			recommended[#recommended + 1] = result
		else
			rest[#rest + 1] = result
		end
	end

	QR.results = {
		log = S.Sort(Evaluate(log, ctx, true)),
		recomendadas = S.Sort(recommended),
		resto = S.Sort(rest),
	}
	QR.context = ctx
	return true
end

local refreshPending = false

--- Pide una actualización; varias seguidas se juntan en una sola.
function QR.RequestRefresh(delay)
	if refreshPending or not QR.UI or not QR.UI:IsShown() then
		return
	end
	refreshPending = true
	C_Timer.After(delay or 0.5, function()
		refreshPending = false
		if QR.Recalculate() and QR.UI:IsShown() then
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
		end
		if QR.UI and QR.UI:IsShown() then
			QR.Recalculate()
			QR.UI:Update()
		end
	end)
end

function QR.Toggle()
	if not QR.started then
		QR.Print("esperando a que Questie termine de cargar...")
		return
	end
	QR.UI:Toggle()
	if QR.UI:IsShown() then
		StartIndex()
		if QR.Recalculate() then
			QR.UI:Update()
		end
	end
end

-- Para el atajo de teclado (Bindings.xml).
function QuestieRelevancia_Toggle()
	QR.Toggle()
end

--------------------------------------------------------------------------------
-- Comandos
--------------------------------------------------------------------------------

local function PrintHelp()
	QR.Print("comandos:")
	local lines = {
		"/qr  -  abre o cierra la ventana",
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

SLASH_QUESTIERELEVANCIA1 = "/qr"
SLASH_QUESTIERELEVANCIA2 = "/relevancia"
SlashCmdList.QUESTIERELEVANCIA = function(input)
	local command, arg1, arg2 = strsplit(" ", strtrim(input or ""):lower(), 3)
	if command == "" then
		QR.Toggle()
	elseif command == "perfil" then
		for _, preset in ipairs(QR.PRESETS) do
			if preset.key == arg1 then
				db.preset = preset.key
				wipe(db.custom)
				PrintWeights()
				QR.RequestRefresh(0)
				if QR.UI then QR.UI:UpdatePreset() end
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
		for key, value in pairs(DEFAULTS) do
			if db[key] == nil then
				db[key] = type(value) == "table" and {} or value
			end
		end
	elseif event == "PLAYER_LOGIN" then
		if not Questie or not Questie.API or not Questie.API.RegisterOnReady then
			QR.Print("necesita Questie instalado y activado.")
			return
		end
		Questie.API.RegisterOnReady(OnQuestieReady)
	elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_EQUIPMENT_CHANGED" then
		QR.RequestRefresh(1)
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		QR.RequestRefresh(2)
	else
		QR.RequestRefresh()
	end
end)

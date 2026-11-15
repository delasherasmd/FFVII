-- Acceso a Questie, a su base de datos (LibQuestieDB) y al juego.
-- Todo lo externo pasa por acá, así el resto del addon no depende de
-- detalles internos de Questie y se puede probar con datos de ejemplo.

local _, QR = ...

local D = {}
QR.Data = D

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetDetailedItemLevelInfo = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo

local modules = {}

local function Import(name)
	if not QuestieLoader or not QuestieLoader.ImportModule then
		return nil
	end
	local ok, module = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
	return ok and module or nil
end

-- Llama a una función de Questie sin dejar que un cambio interno rompa el addon.
local function Try(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(fn, ...)
	if ok then
		return a, b
	end
	return nil
end

function D.Init()
	if not LibQuestieDB or not LibQuestieDB.Quest or not LibQuestieDB.Item then
		return false
	end
	for _, name in ipairs({ "QuestieDB", "QuestXP", "ZoneDB", "QuestiePlayer", "ActiveQuests",
		"AvailableQuests", "QuestieCompat", "TrackerUtils", "LineBuilder", "QuestieTracker" }) do
		modules[name] = Import(name) or {}
	end
	return true
end

function D.Module(name)
	return modules[name] or {}
end

function D.IsReady()
	return Questie ~= nil and Questie.API ~= nil and Questie.API.isReady == true and LibQuestieDB ~= nil
end

--------------------------------------------------------------------------------
-- Base de datos
--------------------------------------------------------------------------------

function D.Quest(questId, key)
	return LibQuestieDB.Quest.Get(questId, key)
end

function D.Item(itemId, key)
	return LibQuestieDB.Item.Get(itemId, key)
end

function D.AllQuestIds()
	return LibQuestieDB.Quest.GetAllIds()
end

function D.AllItemIds()
	return LibQuestieDB.Item.GetAllIds()
end

function D.QuestName(questId)
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local title = Try(C_QuestLog.GetTitleForQuestID, questId)
		if title and title ~= "" then
			return title
		end
	end
	return D.Quest(questId, "name") or ("#" .. questId)
end

--------------------------------------------------------------------------------
-- Estado del jugador según Questie
--------------------------------------------------------------------------------

function D.QuestXP(questId)
	local QuestXP = modules.QuestXP
	if QuestXP and QuestXP.GetQuestLogRewardXP then
		return Try(QuestXP.GetQuestLogRewardXP, QuestXP, questId) or 0
	end
	return 0
end

-- El oro de recompensa solo se puede leer de misiones en el registro, y solo
-- en Forever: en Classic Era la función del juego mira la misión seleccionada.
function D.RewardMoney(questId)
	local QuestXP = modules.QuestXP
	if Questie and Questie.IsForever and QuestXP and QuestXP.GetQuestRewardMoney then
		return Try(QuestXP.GetQuestRewardMoney, questId) or 0
	end
	return 0
end

function D.IsComplete(questId)
	return Try(modules.QuestieDB.IsComplete, questId) or 0
end

function D.IsTrivial(questLevel)
	return Try(modules.QuestieDB.IsTrivial, questLevel) == true
end

-- Misiones cuyas etiquetas se le pueden pedir al juego (las del registro y las
-- disponibles). Para las demás alcanza con la zona de la base de datos, así no
-- se le piden datos al servidor por miles de misiones.
D.tagQuests = {}

function D.IsDungeonQuest(questId)
	local zoneOrSort = D.Quest(questId, "zoneOrSort")
	if zoneOrSort and zoneOrSort > 0 and Try(modules.ZoneDB.IsDungeonZone, zoneOrSort) == true then
		return true
	end
	if not D.tagQuests[questId] then
		return false
	end
	local QuestieDB = modules.QuestieDB
	return (Try(QuestieDB.IsDungeonQuest, questId) or Try(QuestieDB.IsRaidQuest, questId)) == true
end

-- Zonas que Questie lista con las mazmorras pero no lo son: campos de batalla y el tranvía.
D.NOT_DUNGEONS = { [2597] = true, [3277] = true, [3358] = true, [2257] = true }

-- Categorías de eventos de temporada, la Feria de la Luna Negra, la guerra de Ahn'Qiraj,
-- invasiones y campos de batalla.
local EVENT_SORTS = {
	[-22] = true, [-25] = true, [-364] = true, [-365] = true, [-366] = true, [-368] = true, [-369] = true,
	[-370] = true, [-374] = true, [-375] = true, [-376] = true, [-378] = true,
}

function D.IsRepeatable(questId)
	return (D.Quest(questId, "specialFlags") or 0) % 2 == 1
end

--- Misiones de eventos o de campos de batalla: no sirven para medir tu nivel.
function D.IsEventOrPvP(questId)
	local zoneOrSort = D.Quest(questId, "zoneOrSort") or 0
	return EVENT_SORTS[zoneOrSort] == true or D.NOT_DUNGEONS[zoneOrSort] == true
end

--- Estado de una misión: "log", "available", "done" o "blocked".
function D.QuestStatus(questId, logSet, availableSet)
	if logSet[questId] then
		return "log"
	elseif D.IsCompleted(questId) then
		return "done"
	elseif availableSet[questId] then
		return "available"
	end
	return "blocked"
end

function D.IsEligible(questId)
	local QuestiePlayer = modules.QuestiePlayer
	local races = D.Quest(questId, "requiredRaces")
	local classes = D.Quest(questId, "requiredClasses")
	local raceOk = Try(QuestiePlayer.HasRequiredRace, races)
	local classOk = Try(QuestiePlayer.HasRequiredClass, classes)
	return raceOk ~= false and classOk ~= false
end

function D.IsCompleted(questId)
	local complete = Questie and Questie.db and Questie.db.char and Questie.db.char.complete
	if complete then
		return complete[questId] == true
	end
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		return Try(C_QuestLog.IsQuestFlaggedCompleted, questId) == true
	end
	return false
end

function D.LogQuests()
	local set = {}
	local ActiveQuests = modules.ActiveQuests
	local all = ActiveQuests and Try(ActiveQuests.GetAll)
	if all then
		for questId in pairs(all) do
			set[questId] = true
		end
	end
	return set
end

-- Las misiones que Questie calcula como disponibles (las del mapa con "!").
function D.AvailableQuests()
	local set = {}
	local AvailableQuests = modules.AvailableQuests
	local available = AvailableQuests and AvailableQuests.__availableQuests
	if type(available) == "table" then
		for questId in pairs(available) do
			set[questId] = true
		end
	end
	return set
end

--------------------------------------------------------------------------------
-- Jugador
--------------------------------------------------------------------------------

function D.PlayerLevel()
	return UnitLevel("player") or 1
end

function D.XPMax()
	local QuestiePlayer = modules.QuestiePlayer
	if Try(QuestiePlayer.IsMaxLevel) then
		return 0
	end
	return UnitXPMax("player") or 0
end

function D.PlayerClass()
	local _, classFile = UnitClass("player")
	return classFile
end

function D.ClassSortKey(classFile)
	local sortKeys = modules.QuestieDB.sortKeys
	return sortKeys and classFile and sortKeys[classFile] or nil
end

function D.AllClassesMask()
	local keys = LibQuestieDB.Enum and LibQuestieDB.Enum.classKeys
	return keys and keys.ALL_CLASSES or 1503
end

--- Lo que llevás puesto, por ranura. itemLevel es nil si todavía no se sabe.
function D.EquippedItems()
	local items, any = {}, false
	for slot = 1, 18 do
		if slot ~= 4 then -- la camisa no cuenta
			local itemId = GetInventoryItemID("player", slot)
			if itemId then
				any = true
				local link = GetInventoryItemLink("player", slot)
				local itemLevel = link and GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)
				if not itemLevel or itemLevel <= 1 then
					-- Al entrar al juego el cliente a veces no tiene los datos todavía:
					-- se usa la base de datos de Questie.
					itemLevel = D.Item(itemId, "itemLevel")
				end
				items[slot] = { itemId = itemId, link = link, itemLevel = itemLevel,
					equipLoc = D.ItemEquipInfo(itemId) }
			end
		end
	end
	-- Sin nada puesto a un nivel avanzado: el equipo todavía no cargó.
	items.loaded = any or D.PlayerLevel() <= 5
	return items
end

--- Nivel de objeto por ranura: un número, nil si está vacía, o false si no se sabe.
function D.EquippedItemLevels(items)
	items = items or D.EquippedItems()
	local levels = {}
	for slot = 1, 18 do
		if slot ~= 4 then
			local item = items[slot]
			if not items.loaded then
				levels[slot] = false
			elseif item then
				levels[slot] = item.itemLevel or false
			end
		end
	end
	return levels
end

--------------------------------------------------------------------------------
-- Objetos
--------------------------------------------------------------------------------

function D.ItemEquipInfo(itemId)
	local _, _, _, equipLoc, _, classID, subClassID = GetItemInfoInstant(itemId)
	if not equipLoc or equipLoc == "" then
		return nil
	end
	return equipLoc, classID or D.Item(itemId, "class"), subClassID or D.Item(itemId, "subClass")
end

function D.ItemSellPrice(itemId)
	return (select(11, GetItemInfo(itemId)))
end

function D.ItemIcon(itemId)
	return (select(5, GetItemInfoInstant(itemId)))
end

function D.ItemName(itemId)
	return D.Item(itemId, "name") or (select(1, GetItemInfo(itemId))) or ("#" .. itemId)
end

function D.ItemQuality(itemId)
	if C_Item and C_Item.GetItemQualityByID then
		return Try(C_Item.GetItemQualityByID, itemId)
	end
	return (select(3, GetItemInfo(itemId)))
end

function D.FactionName(factionId)
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local data = Try(C_Reputation.GetFactionDataByID, factionId)
		if data and data.name then
			return data.name
		end
	end
	if GetFactionInfoByID then
		local name = Try(GetFactionInfoByID, factionId)
		if name then
			return name
		end
	end
	return "#" .. factionId
end

--- Mazmorras y bandas conocidas por Questie: areaId -> {nombre, otras áreas}.
function D.Dungeons()
	local ZoneDB = modules.ZoneDB
	local dungeons = ZoneDB.GetDungeons and Try(ZoneDB.GetDungeons, ZoneDB)
	local list = {}
	for areaId, entry in pairs(dungeons or {}) do
		if not D.NOT_DUNGEONS[areaId] then
			local name = ZoneDB.GetLocalizedDungeonName and Try(ZoneDB.GetLocalizedDungeonName, ZoneDB, areaId)
			list[#list + 1] = {
				areaId = areaId,
				name = name or D.ZoneName(areaId) ~= "" and D.ZoneName(areaId) or entry[1] or ("#" .. areaId),
				areaIds = entry[2] or {},
				parentZone = entry[3],
			}
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- Zonas y mapa
--------------------------------------------------------------------------------

function D.CurrentZone()
	local QuestiePlayer = modules.QuestiePlayer
	return QuestiePlayer.GetCurrentZoneId and Try(QuestiePlayer.GetCurrentZoneId, QuestiePlayer) or nil
end

local function ParentZone(areaId)
	local ZoneDB = modules.ZoneDB
	return ZoneDB.GetParentZoneId and Try(ZoneDB.GetParentZoneId, ZoneDB, areaId) or nil
end

--- Zona de la misión: la de la base de datos, o la de quien la entrega.
function D.QuestZone(questId)
	local zoneOrSort = D.Quest(questId, "zoneOrSort")
	if zoneOrSort and zoneOrSort > 0 then
		return zoneOrSort
	end
	local startedBy = D.Quest(questId, "startedBy")
	local npcs = startedBy and startedBy[1]
	if npcs and npcs[1] and LibQuestieDB.Npc then
		return LibQuestieDB.Npc.Get(npcs[1], "zoneID")
	end
	return nil
end

function D.SameZone(a, b)
	if not a or not b then
		return false
	end
	if a == b then
		return true
	end
	local parentA, parentB = ParentZone(a), ParentZone(b)
	return parentA == b or parentB == a or (parentA ~= nil and parentA == parentB)
end

function D.ZoneName(areaId)
	if not areaId then
		return ""
	end
	if C_Map and C_Map.GetAreaInfo then
		local name = Try(C_Map.GetAreaInfo, areaId)
		if name then
			return name
		end
	end
	return ""
end

--- Abre la misión en el registro, o su zona en el mapa si todavía no la tomaste.
function D.ShowQuest(result)
	local QuestieDB = modules.QuestieDB
	if result.inLog then
		local quest = Try(QuestieDB.GetQuest, result.id)
		local TrackerUtils = modules.TrackerUtils
		if quest and TrackerUtils.ShowQuestLog then
			Try(TrackerUtils.ShowQuestLog, TrackerUtils, quest)
			return
		end
	end
	local ZoneDB = modules.ZoneDB
	local uiMapId = result.zone and ZoneDB.GetUiMapIdByAreaId and Try(ZoneDB.GetUiMapIdByAreaId, ZoneDB, result.zone)
	local QuestieCompat = modules.QuestieCompat
	if uiMapId and QuestieCompat.OpenWorldMap then
		if Try(QuestieCompat.OpenWorldMap, uiMapId) == false then
			QR.Print("no se puede abrir el mapa en combate.")
		end
	else
		QR.Print("no sé en qué zona empieza \"" .. result.name .. "\". Buscala con /questie tomap.")
	end
end

-- Datos de las pestañas Por nivel, Mazmorra y Equipo, y del catálogo de la cadena.

local _, QR = ...

local V = {}
QR.Views = V

local floor, max, min = math.floor, math.max, math.min

--------------------------------------------------------------------------------
-- Por nivel
--------------------------------------------------------------------------------

V.LEVEL_RANGES = {
	{ key = "mio", label = "Mi nivel" },
	{ key = "1-10", from = 1, to = 10 },
	{ key = "11-20", from = 11, to = 20 },
	{ key = "21-30", from = 21, to = 30 },
	{ key = "31-40", from = 31, to = 40 },
	{ key = "41-50", from = 41, to = 50 },
	{ key = "51-60", from = 51, to = 60 },
	{ key = "todas", label = "Todas", from = 1, to = 999 },
}

function V.RangeBounds(range, level)
	if range.key == "mio" then
		return level - 4, level + 2
	end
	return range.from, range.to
end

--- Misiones que tu personaje puede ver (raza y clase), de un rango de niveles,
--- agrupadas por nivel: un encabezado por nivel y adentro de mayor a menor puntaje.
function V.LevelList(ctx, range, flags, logSet, availableSet, evaluate)
	local D = ctx.D
	local from, to = V.RangeBounds(range, ctx.level)
	local byLevel, levels = {}, {}
	for _, questId in ipairs(QR.Index.questIds) do
		local questLevel = D.Quest(questId, "questLevel")
		if questLevel and questLevel <= 0 then
			questLevel = D.Quest(questId, "requiredLevel") or 1
		end
		if questLevel and questLevel >= from and questLevel <= to
			and (D.Quest(questId, "specialFlags") or 0) % 2 == 0 -- sin repetibles
			and D.IsEligible(questId) then
			local status = D.QuestStatus(questId, logSet, availableSet)
			if (status ~= "done" or flags.hechas) and (status ~= "blocked" or flags.bloqueadas) then
				local result = evaluate(questId, status == "log")
				if result and (flags.relleno or not result.tags.relleno) then
					result.status = status
					local group = byLevel[result.level]
					if not group then
						group = {}
						byLevel[result.level] = group
						levels[#levels + 1] = result.level
					end
					group[#group + 1] = result
				end
			end
		end
	end
	table.sort(levels)
	local list, count = {}, 0
	for _, level in ipairs(levels) do
		list[#list + 1] = { header = true, text = "Nivel " .. level }
		for _, result in ipairs(QR.Scoring.Sort(byLevel[level])) do
			list[#list + 1] = result
			count = count + 1
		end
	end
	return list, count
end

--------------------------------------------------------------------------------
-- Mazmorra
--------------------------------------------------------------------------------

local function DungeonQuestIds(dungeon)
	local ids, seen = {}, {}
	local areas = { dungeon.areaId }
	for _, areaId in ipairs(dungeon.areaIds) do
		areas[#areas + 1] = areaId
	end
	for _, areaId in ipairs(areas) do
		for _, questId in ipairs(QR.Index.byZone[areaId] or {}) do
			if not seen[questId] then
				seen[questId] = true
				ids[#ids + 1] = questId
			end
		end
	end
	return ids
end

--- Mazmorras con misiones para tu personaje, ordenadas por nivel.
function V.DungeonList(ctx)
	local D = ctx.D
	local list = {}
	for _, dungeon in ipairs(D.Dungeons()) do
		local total, done, minLevel, maxLevel = 0, 0, nil, nil
		for _, questId in ipairs(DungeonQuestIds(dungeon)) do
			if D.IsEligible(questId) and not D.IsRepeatable(questId) and not D.IsEventOrPvP(questId) then
				total = total + 1
				if D.IsCompleted(questId) then
					done = done + 1
				end
				local level = D.Quest(questId, "questLevel") or 0
				if level > 0 then
					minLevel = min(minLevel or level, level)
					maxLevel = max(maxLevel or level, level)
				end
			end
		end
		if total > 0 then
			list[#list + 1] = {
				dungeon = dungeon,
				name = dungeon.name,
				total = total,
				done = done,
				minLevel = minLevel or 0,
				maxLevel = maxLevel or 0,
				forYou = minLevel ~= nil and ctx.level >= minLevel - 3 and ctx.level <= maxLevel + 2,
			}
		end
	end
	table.sort(list, function(a, b)
		if a.minLevel ~= b.minLevel then
			return a.minLevel < b.minLevel
		end
		return a.name < b.name
	end)
	return list
end

--- Preparar mazmorra: para cada misión de la mazmorra, primero los pasos que la
--- habilitan (los que hay que hacer afuera) y después la misión, en orden.
function V.DungeonPlan(ctx, dungeon, logSet, availableSet, evaluate)
	local D = ctx.D
	local accept = function(id) return D.IsEligible(id) end
	local quests = {}
	for _, questId in ipairs(DungeonQuestIds(dungeon)) do
		if D.IsEligible(questId) and not D.IsRepeatable(questId) and not D.IsEventOrPvP(questId) then
			quests[#quests + 1] = { id = questId, level = D.Quest(questId, "questLevel") or 0 }
		end
	end
	table.sort(quests, function(a, b)
		if a.level ~= b.level then return a.level < b.level end
		return a.id < b.id
	end)

	local inside = {}
	for _, quest in ipairs(quests) do
		inside[quest.id] = true
	end

	local list, seen = {}, {}
	local function Add(questId, role)
		if seen[questId] then
			return
		end
		seen[questId] = true
		local status = D.QuestStatus(questId, logSet, availableSet)
		local result = evaluate(questId, status == "log")
		if result then
			result.status = status
			result.role = role
			list[#list + 1] = result
		end
	end
	for _, quest in ipairs(quests) do
		local before = QR.Index.PreviousSteps(quest.id, 30, accept)
		for i = #before, 1, -1 do
			local stepId = before[i]
			if not D.IsCompleted(stepId) then
				Add(stepId, inside[stepId] and "adentro" or "preparar")
			end
		end
		Add(quest.id, "adentro")
	end
	return list
end

--------------------------------------------------------------------------------
-- Equipo
--------------------------------------------------------------------------------

V.SLOTS = {
	{ slot = 1, name = "Cabeza", locs = { "INVTYPE_HEAD" } },
	{ slot = 2, name = "Cuello", locs = { "INVTYPE_NECK" } },
	{ slot = 3, name = "Hombros", locs = { "INVTYPE_SHOULDER" } },
	{ slot = 15, name = "Espalda", locs = { "INVTYPE_CLOAK" } },
	{ slot = 5, name = "Pecho", locs = { "INVTYPE_CHEST", "INVTYPE_ROBE" } },
	{ slot = 9, name = "Muñecas", locs = { "INVTYPE_WRIST" } },
	{ slot = 10, name = "Manos", locs = { "INVTYPE_HAND" } },
	{ slot = 6, name = "Cintura", locs = { "INVTYPE_WAIST" } },
	{ slot = 7, name = "Piernas", locs = { "INVTYPE_LEGS" } },
	{ slot = 8, name = "Pies", locs = { "INVTYPE_FEET" } },
	{ slot = 11, name = "Dedo 1", locs = { "INVTYPE_FINGER" } },
	{ slot = 12, name = "Dedo 2", locs = { "INVTYPE_FINGER" } },
	{ slot = 13, name = "Abalorio 1", locs = { "INVTYPE_TRINKET" } },
	{ slot = 14, name = "Abalorio 2", locs = { "INVTYPE_TRINKET" } },
	{ slot = 16, name = "Mano principal", locs = { "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND" } },
	{ slot = 17, name = "Mano secundaria", locs = { "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" } },
	{ slot = 18, name = "A distancia", locs = { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC" } },
}

local DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true }

-- Premios de misión que se pueden equipar, agrupados por tipo de ranura.
-- Se arma una vez: los datos de objetos no cambian.
local candidatesByLoc

local function Candidates(D)
	if candidatesByLoc then
		return candidatesByLoc
	end
	candidatesByLoc = {}
	for questId, items in pairs(QR.Index.rewards) do
		for _, itemId in ipairs(items) do
			local equipLoc, classID, subClassID = D.ItemEquipInfo(itemId)
			if equipLoc then
				local byItem = candidatesByLoc[equipLoc]
				if not byItem then
					byItem = {}
					candidatesByLoc[equipLoc] = byItem
				end
				local entry = byItem[itemId]
				if not entry then
					entry = { itemId = itemId, equipLoc = equipLoc, classID = classID, subClassID = subClassID,
						itemLevel = D.Item(itemId, "itemLevel") or 0, requiredLevel = D.Item(itemId, "requiredLevel"),
						quests = {} }
					byItem[itemId] = entry
				end
				entry.quests[#entry.quests + 1] = questId
			end
		end
	end
	return candidatesByLoc
end

-- ¿Este premio es "de tu nivel" y lo podés conseguir ahora?
-- Muchos objetos no traen nivel requerido: se usa el nivel mínimo de la misión.
-- Las misiones de eventos, de campos de batalla y las repetibles no cuentan:
-- algunas dicen "nivel 1" y dan objetos de nivel 60.
local function Reachable(entry, ctx)
	local D = ctx.D
	if entry.itemLevel > ctx.level + 12 then
		return nil
	end
	local bestQuests = {}
	for _, questId in ipairs(entry.quests) do
		local questLevel = D.Quest(questId, "questLevel") or 0
		local required = entry.requiredLevel
		if not required or required <= 0 then
			required = D.Quest(questId, "requiredLevel") or questLevel
		end
		if required <= ctx.level and questLevel > 0 and questLevel <= ctx.level + 2
			and D.IsEligible(questId) and not D.IsCompleted(questId)
			and not D.IsRepeatable(questId) and not D.IsEventOrPvP(questId) then
			bestQuests[#bestQuests + 1] = questId
		end
	end
	return #bestQuests > 0 and bestQuests or nil
end

local function BestFor(locs, ctx)
	local D = ctx.D
	local best, bestQuests
	for _, loc in ipairs(locs) do
		for _, entry in pairs(Candidates(D)[loc] or {}) do
			if QR.Scoring.CanUse(entry.classID, entry.subClassID, entry.equipLoc, ctx)
				and (not best or entry.itemLevel > best.itemLevel
					or (entry.itemLevel == best.itemLevel and entry.itemId < best.itemId)) then
				local quests = Reachable(entry, ctx)
				if quests then
					best, bestQuests = entry, quests
				end
			end
		end
	end
	return best, bestQuests
end

--- Compara ranura por ranura lo que llevás con el mejor premio de misión que tu
--- clase puede usar a tu nivel.
function V.Gear(ctx)
	local D = ctx.D
	local items = D.EquippedItems()
	local mainHand = items[16]
	local twoHanded = mainHand and mainHand.equipLoc == "INVTYPE_2HWEAPON"
	local rows, sumHave, sumIdeal = {}, 0, 0

	for _, def in ipairs(V.SLOTS) do
		local locs = def.locs
		local notApplicable = false
		if def.slot == 16 and twoHanded then
			locs = { "INVTYPE_2HWEAPON" }
		elseif def.slot == 16 and not mainHand then
			locs = { "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_2HWEAPON" }
		elseif def.slot == 17 then
			if twoHanded then
				notApplicable = true
			elseif DUAL_WIELD[ctx.classFile] then
				locs = { "INVTYPE_WEAPONOFFHAND", "INVTYPE_WEAPON", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" }
			end
		end

		local item = items[def.slot]
		local have = item and item.itemLevel
		local row = { slot = def.slot, name = def.name, item = item, have = have, notApplicable = notApplicable }
		if not notApplicable then
			local ideal, quests = BestFor(locs, ctx)
			row.ideal, row.quests = ideal, quests
			if ideal and not items.loaded then
				row.unknown = true -- el equipo todavía no cargó
			elseif ideal then
				if have == nil and item then
					row.unknown = true -- puesto, pero sin datos todavía
				else
					local current = have or 0
					row.gain = max(0, ideal.itemLevel - current)
					sumHave = sumHave + min(current, ideal.itemLevel)
					sumIdeal = sumIdeal + ideal.itemLevel
				end
			end
		end
		rows[#rows + 1] = row
	end

	local percent = sumIdeal > 0 and floor(100 * sumHave / sumIdeal + 0.5) or nil
	local verdict
	if not items.loaded then
		verdict = "Tu equipo todavía no cargó. Abrí de nuevo en unos segundos."
	elseif not percent then
		verdict = "No hay premios de misión para comparar a tu nivel."
	elseif percent >= 95 then
		verdict = "Equipo al día"
	elseif percent >= 85 then
		verdict = "Bastante bien"
	elseif percent >= 70 then
		verdict = "Algo desactualizado"
	else
		verdict = "Muy desactualizado"
	end

	local top = {}
	for _, row in ipairs(rows) do
		if row.gain and row.gain > 0 then
			top[#top + 1] = row
		end
	end
	table.sort(top, function(a, b)
		if a.gain ~= b.gain then return a.gain > b.gain end
		return a.slot < b.slot
	end)
	while #top > 3 do
		table.remove(top)
	end

	return { rows = rows, percent = percent, verdict = verdict, top = top, loaded = items.loaded }
end

--------------------------------------------------------------------------------
-- Catálogo de la cadena
--------------------------------------------------------------------------------

--- Todo lo que se obtiene en la cadena que pasa por una misión: paso por paso
--- y el total de lo que falta.
function V.ChainCatalog(ctx, questId, logSet)
	local D = ctx.D
	local accept = function(id) return D.IsEligible(id) end
	local path, position = QR.Index.ChainPath(questId, accept)
	local steps = {}
	local totals = { xp = 0, items = 0, upgrades = 0, sell = 0, rep = {}, repOrder = {}, remaining = 0 }

	for index, stepId in ipairs(path) do
		local done = D.IsCompleted(stepId)
		local step = {
			id = stepId,
			index = index,
			name = D.QuestName(stepId),
			level = D.Quest(stepId, "questLevel") or 0,
			done = done,
			inLog = logSet[stepId] == true,
			current = stepId == questId,
			xp = D.QuestXP(stepId),
			items = {},
			rep = {},
		}
		for _, itemId in ipairs(QR.Index.rewards[stepId] or {}) do
			local upgrade = QR.Scoring.GearUpgrade(itemId, ctx)
			step.items[#step.items + 1] = { itemId = itemId, upgrade = upgrade > 0 }
		end
		for _, pair in ipairs(D.Quest(stepId, "reputationReward") or {}) do
			step.rep[#step.rep + 1] = { factionId = pair[1], value = pair[2] }
		end

		if not done then
			totals.remaining = totals.remaining + 1
			totals.xp = totals.xp + (step.xp or 0)
			totals.items = totals.items + #step.items
			for _, item in ipairs(step.items) do
				if item.upgrade then
					totals.upgrades = totals.upgrades + 1
				end
				totals.sell = totals.sell + (D.ItemSellPrice(item.itemId) or 0)
			end
			for _, rep in ipairs(step.rep) do
				if not totals.rep[rep.factionId] then
					totals.repOrder[#totals.repOrder + 1] = rep.factionId
				end
				totals.rep[rep.factionId] = (totals.rep[rep.factionId] or 0) + rep.value
			end
		end
		steps[#steps + 1] = step
	end
	return { steps = steps, position = position, totals = totals, questId = questId }
end

-- Índice de cadenas de misiones y de recompensas, armado una sola vez
-- a partir de la base de datos de Questie (QuestieDB).

local _, QR = ...

local Index = {
	successors = {},   -- questId -> {questId = true}: misiones que esta habilita
	predecessors = {}, -- questId -> {questId = true}: misiones previas (sin las de "aviso")
	breadcrumbFor = {},-- questId de aviso -> misión a la que lleva
	rewards = {},      -- questId -> {itemId, ...}
	byZone = {},       -- areaId -> {questId, ...}
	questIds = {},     -- todas las misiones de la base de datos
	ready = false,
	building = false,
	progress = 0,
}
QR.Index = Index

local FRAME_BUDGET_MS = 8 -- trabajo máximo por cuadro, para no trabar el juego
local MAX_DEPTH = 60

local Now = debugprofilestop or function() return os.clock() * 1000 end

local function AddEdge(map, from, to)
	if not from or not to or from == to then
		return
	end
	local set = map[from]
	if not set then
		set = {}
		map[from] = set
	end
	set[to] = true
end

local function IndexQuest(D, questId)
	local breadcrumbTarget = D.Quest(questId, "breadcrumbForQuestId")
	if breadcrumbTarget and breadcrumbTarget > 0 then
		Index.breadcrumbFor[questId] = breadcrumbTarget
		-- Hacer el aviso lleva a la misión: hereda su valor, pero no cuenta
		-- como paso previo de la cadena.
		AddEdge(Index.successors, questId, breadcrumbTarget)
	end

	local nextQuest = D.Quest(questId, "nextQuestInChain")
	if nextQuest and nextQuest > 0 then
		AddEdge(Index.successors, questId, nextQuest)
		if breadcrumbTarget ~= nextQuest then
			AddEdge(Index.predecessors, nextQuest, questId)
		end
	end

	-- preQuestSingle: basta una de la lista; preQuestGroup: hacen falta todas.
	-- Un ID negativo en preQuestGroup sigue siendo requisito.
	for _, key in ipairs({ "preQuestSingle", "preQuestGroup" }) do
		local list = D.Quest(questId, key)
		if list then
			for _, preId in pairs(list) do
				preId = math.abs(preId)
				if preId > 0 then
					AddEdge(Index.successors, preId, questId)
					if D.Quest(preId, "breadcrumbForQuestId") ~= questId then
						AddEdge(Index.predecessors, questId, preId)
					end
				end
			end
		end
	end

	-- Misiones que se habilitan mientras esta está activa.
	local children = D.Quest(questId, "childQuests")
	if children then
		for _, childId in pairs(children) do
			AddEdge(Index.successors, questId, childId)
			AddEdge(Index.predecessors, childId, questId)
		end
	end

	local zoneOrSort = D.Quest(questId, "zoneOrSort")
	if zoneOrSort and zoneOrSort > 0 then
		local list = Index.byZone[zoneOrSort]
		if not list then
			list = {}
			Index.byZone[zoneOrSort] = list
		end
		list[#list + 1] = questId
	end
end

local function IndexItem(D, itemId)
	local quests = D.Item(itemId, "questRewards")
	if not quests then
		return
	end
	for _, questId in pairs(quests) do
		local list = Index.rewards[questId]
		if not list then
			list = {}
			Index.rewards[questId] = list
		end
		list[#list + 1] = itemId
	end
end

--- Corre un trabajo largo de a poco por cuadro, para no trabar el juego.
--- work recibe una función Pause() para llamar seguido; onDone(ok, error).
function Index.RunSliced(work, onDone)
	local sliceStart = 0
	local count = 0
	local function Pause()
		count = count + 1
		if count % 20 == 0 and Now() - sliceStart > FRAME_BUDGET_MS then
			coroutine.yield()
		end
	end
	local worker = coroutine.create(function() work(Pause) end)

	local ticker
	ticker = C_Timer.NewTicker(0.01, function()
		sliceStart = Now()
		local ok, err = coroutine.resume(worker)
		if not ok then
			ticker:Cancel()
			if onDone then onDone(false, tostring(err)) end
		elseif coroutine.status(worker) == "dead" then
			ticker:Cancel()
			if onDone then onDone(true) end
		end
	end)
	return ticker
end

--- Arma el índice en segundo plano.
function Index.Build(D, onDone)
	if Index.ready or Index.building then
		return
	end
	Index.building = true
	Index.error = nil

	local questIds = D.AllQuestIds() or {}
	local itemIds = D.AllItemIds() or {}
	local total = math.max(1, #questIds + #itemIds)
	Index.questIds = questIds

	Index.RunSliced(function(Pause)
		local done = 0
		for i = 1, #questIds do
			IndexQuest(D, questIds[i])
			done = done + 1
			Index.progress = done / total
			Pause()
		end
		for i = 1, #itemIds do
			IndexItem(D, itemIds[i])
			done = done + 1
			Index.progress = done / total
			Pause()
		end
	end, function(ok, err)
		Index.building = false
		if ok then
			Index.ready = true
			Index.progress = 1
		else
			Index.error = err
		end
		if onDone then onDone(ok) end
	end)
end

-- Profundidad máxima siguiendo un mapa de aristas, con protección contra ciclos.
local predDepth, succDepth = {}, {}

local function Depth(map, cache, questId, visiting, depth)
	local cached = cache[questId]
	if cached then
		return cached
	end
	if visiting[questId] or depth > MAX_DEPTH then
		return 0
	end
	visiting[questId] = true
	local best = 0
	local set = map[questId]
	if set then
		for other in pairs(set) do
			local d = 1 + Depth(map, cache, other, visiting, depth + 1)
			if d > best then
				best = d
			end
		end
	end
	visiting[questId] = nil
	cache[questId] = best
	return best
end

--- Paso de la misión dentro de su cadena más larga, y largo total de esa cadena.
function Index.Chain(questId)
	local before = Depth(Index.predecessors, predDepth, questId, {}, 0)
	local after = Depth(Index.successors, succDepth, questId, {}, 0)
	return before + 1, before + 1 + after
end

local function Longest(map, cache, questId, accept)
	local best, bestDepth
	local set = map[questId]
	if set then
		for other in pairs(set) do
			if not accept or accept(other) then
				local d = Depth(map, cache, other, {}, 0)
				if not bestDepth or d > bestDepth or (d == bestDepth and other < best) then
					best, bestDepth = other, d
				end
			end
		end
	end
	return best
end

local function Walk(map, cache, questId, limit, accept)
	local steps, seen = {}, { [questId] = true }
	local current = questId
	while #steps < limit do
		local nextId = Longest(map, cache, current, accept)
		if not nextId or seen[nextId] then
			break
		end
		seen[nextId] = true
		steps[#steps + 1] = nextId
		current = nextId
	end
	return steps
end

--- Los próximos pasos de la cadena, siguiendo la rama más larga.
function Index.NextSteps(questId, limit, accept)
	return Walk(Index.successors, succDepth, questId, limit, accept)
end

--- Los pasos anteriores, del más cercano al primero de la cadena.
function Index.PreviousSteps(questId, limit, accept)
	return Walk(Index.predecessors, predDepth, questId, limit, accept)
end

--- La cadena completa que pasa por esta misión, del primer paso al último.
function Index.ChainPath(questId, accept)
	local path, inPath = {}, {}
	local before = Index.PreviousSteps(questId, MAX_DEPTH, accept)
	for i = #before, 1, -1 do
		path[#path + 1] = before[i]
		inPath[before[i]] = true
	end
	path[#path + 1] = questId
	inPath[questId] = true
	for _, nextId in ipairs(Index.NextSteps(questId, MAX_DEPTH, accept)) do
		if inPath[nextId] then
			break -- datos con ciclos: no repetir pasos
		end
		path[#path + 1] = nextId
		inPath[nextId] = true
	end
	return path, #before + 1
end

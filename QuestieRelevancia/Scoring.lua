-- Puntaje de relevancia de 0 a 100 para cada misión.
--
-- Cada componente (XP, oro, equipo, historia, clase, mazmorra y cadena) vale
-- entre 0 y 1. Se combinan como probabilidades independientes: un componente
-- fuerte alcanza para un buen puntaje, y varios juntos lo acercan a 100.
-- Después se ajusta por prioridad: dificultad, zona actual y si ya se puede
-- entregar.

local _, QR = ...

local S = {}
QR.Scoring = S

local floor, min, max = math.floor, math.min, math.max

local CHAIN_DECAY = 0.7   -- cuánto pesa cada paso siguiente de la cadena
local CHAIN_FULL = 1.2    -- valor de cadena que cuenta como "cadena excelente"
local GEAR_FULL_GAIN = 8  -- niveles de objeto de mejora que cuentan como excelente
local XP_FULL_SHARE = 0.10 -- una misión que da el 10% del nivel cuenta como excelente

S.COMPONENTS = { "xp", "historia", "cadena", "equipo", "oro", "clase", "mazmorra" }

S.LABELS = {
	xp = "XP",
	historia = "Historia",
	cadena = "Cadena",
	equipo = "Equipo",
	oro = "Oro",
	clase = "Clase",
	mazmorra = "Mazmorra",
	relleno = "Relleno",
}

local PRIORITY = {
	green = 0.9,
	yellow = 1.0,
	orange = 0.95,
}

--- Prioridad según el nivel de la misión comparado con el tuyo. Una sola fórmula
--- para misiones sueltas y cadenas: muy por encima de tu nivel tiende a cero.
--- Las grises casi no valen, salvo las de clase, mazmorra o las que desbloquean
--- algo, que valen la mitad.
local function LevelFactor(questLevel, difficulty, ctx, special)
	if difficulty == "grey" then
		return special and 0.5 or 0.25
	end
	local diff = questLevel - ctx.level
	if diff >= 5 then
		return max(0.02, 0.55 * math.exp(-(diff - 5) / 2.5))
	end
	return PRIORITY[difficulty]
end

--- Por encima de 70 el puntaje se comprime suavemente y nunca llega a 100,
--- así las mejores misiones no quedan amontonadas empatadas arriba de todo.
local function Compress(value)
	if value <= 0.7 then
		return value
	end
	return 0.7 + 0.3 * (1 - math.exp(-(value - 0.7) / 0.3))
end

-- Huecos de equipo donde puede ir cada tipo de objeto.
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
	INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- Armaduras que cada clase usa como principales (subclase de objeto 4):
-- 1 tela, 2 cuero, 3 malla, 4 placas. "alto" aplica desde el nivel 40.
local ARMOR = {
	WARRIOR = { bajo = { [2] = true, [3] = true }, alto = { [3] = true, [4] = true } },
	PALADIN = { bajo = { [2] = true, [3] = true }, alto = { [3] = true, [4] = true } },
	HUNTER = { bajo = { [2] = true }, alto = { [2] = true, [3] = true } },
	SHAMAN = { bajo = { [2] = true }, alto = { [2] = true, [3] = true } },
	ROGUE = { bajo = { [2] = true }, alto = { [2] = true } },
	DRUID = { bajo = { [2] = true }, alto = { [2] = true } },
	PRIEST = { bajo = { [1] = true }, alto = { [1] = true } },
	MAGE = { bajo = { [1] = true }, alto = { [1] = true } },
	WARLOCK = { bajo = { [1] = true }, alto = { [1] = true } },
}

-- Otras subclases de armadura: 0 varios (anillos, collares, abalorios), 6 escudos,
-- 7 tratados, 8 ídolos, 9 tótems.
local ARMOR_EXTRA = {
	WARRIOR = { [6] = true }, PALADIN = { [6] = true, [7] = true }, SHAMAN = { [6] = true, [9] = true },
	DRUID = { [8] = true },
}

-- Armas que cada clase puede aprender (subclase de objeto 2).
-- 0 hacha 1M, 1 hacha 2M, 2 arco, 3 arma de fuego, 4 maza 1M, 5 maza 2M, 6 arma de asta,
-- 7 espada 1M, 8 espada 2M, 10 bastón, 13 puño, 15 daga, 16 arrojadiza, 18 ballesta, 19 varita.
local WEAPONS = {
	WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
	PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
	HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
	ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
	PRIEST = { 4, 10, 15, 19 },
	SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
	MAGE = { 7, 10, 15, 19 },
	WARLOCK = { 7, 10, 15, 19 },
	DRUID = { 4, 5, 10, 13, 15 },
}
for class, list in pairs(WEAPONS) do
	local set = {}
	for _, subClass in ipairs(list) do
		set[subClass] = true
	end
	WEAPONS[class] = set
end

local function Clamp(value)
	if value ~= value or value <= 0 then
		return 0
	end
	return value >= 1 and 1 or value
end

--- Peso configurado (0 a 2) convertido a la fuerza de un componente.
local function Strength(weight)
	return min(0.9, max(0, (weight or 0) * 0.6))
end

local function GoldTarget(level)
	return max(100, 2.5 * max(1, level) ^ 2.2)
end

--- Color de dificultad, igual que el registro de misiones.
function S.Difficulty(questLevel, ctx)
	local diff = questLevel - ctx.level
	if diff >= 5 then
		return "red"
	elseif diff >= 3 then
		return "orange"
	elseif diff >= -2 then
		return "yellow"
	elseif ctx.D.IsTrivial(questLevel) then
		return "grey"
	end
	return "green"
end

function S.CanUse(classID, subClassID, equipLoc, ctx)
	local class = ctx.classFile
	if classID == 2 then
		local set = WEAPONS[class]
		return set ~= nil and set[subClassID] == true
	elseif classID == 4 then
		if equipLoc == "INVTYPE_CLOAK" or subClassID == 0 then
			return true
		end
		local extra = ARMOR_EXTRA[class]
		if extra and extra[subClassID] then
			return true
		end
		local armor = ARMOR[class]
		if not armor then
			return true
		end
		local allowed = ctx.level >= 40 and armor.alto or armor.bajo
		return allowed[subClassID] == true
	end
	return false
end

--- Mejora de equipo (0 a 1) que daría un objeto, y el hueco que mejora.
function S.GearUpgrade(itemId, ctx)
	local D = ctx.D
	local equipLoc, classID, subClassID = D.ItemEquipInfo(itemId)
	local slots = equipLoc and SLOTS[equipLoc]
	if not slots or not S.CanUse(classID, subClassID, equipLoc, ctx) then
		return 0
	end

	local itemLevel = D.Item(itemId, "itemLevel") or 0
	local worst, worstSlot = math.huge, nil
	for _, slot in ipairs(slots) do
		-- false: hay algo puesto pero el juego todavía no cargó sus datos.
		-- No se inventan mejoras para esa ranura.
		local equipped = ctx.equipped[slot]
		if equipped ~= false then
			equipped = equipped or 0
			if equipped < worst then
				worst, worstSlot = equipped, slot
			end
		end
	end
	if not worstSlot then
		return 0
	end

	local gain = itemLevel - worst
	if gain <= 0 then
		return 0
	end
	local value = worst == 0 and 1 or Clamp(gain / GEAR_FULL_GAIN)
	local requiredLevel = D.Item(itemId, "requiredLevel") or 0
	if requiredLevel > ctx.level + 3 then
		value = value * 0.5
	end
	-- Sin nada equipado en ese hueco no hay "niveles de mejora" que mostrar.
	return value, worstSlot, worst > 0 and gain or nil
end

local function IsClassQuest(questId, ctx)
	local D = ctx.D
	local zoneOrSort = D.Quest(questId, "zoneOrSort") or 0
	if ctx.classSort and zoneOrSort == ctx.classSort then
		return true
	end
	local required = D.Quest(questId, "requiredClasses")
	if not required or required == 0 or required == ctx.allClasses then
		return false
	end
	-- Misiones para pocas clases (hasta tres) cuentan como "de clase".
	local count, bit = 0, 1
	while bit <= required do
		if required % (bit * 2) >= bit then
			count = count + 1
		end
		bit = bit * 2
	end
	return count <= 3
end

--- Componentes propios de una misión, sin contar historia ni cadena.
local function Intrinsic(questId, ctx, inLog)
	local cache = inLog and ctx.logCache or ctx.intrinsicCache
	local cached = cache[questId]
	if cached then
		return cached
	end

	local D = ctx.D
	local parts = {}

	local xp = D.QuestXP(questId) or 0
	parts.xp = ctx.xpMax > 0 and Clamp(xp / (XP_FULL_SHARE * ctx.xpMax)) or 0

	local questLevel = D.Quest(questId, "questLevel") or ctx.level
	if questLevel <= 0 then
		questLevel = ctx.level
	end

	local bestGear, bestSlot, bestGain, bestSell = 0, nil, nil, 0
	local rewards = QR.Index.rewards[questId]
	if rewards then
		for _, itemId in ipairs(rewards) do
			local value, slot, gain = S.GearUpgrade(itemId, ctx)
			if value > bestGear then
				bestGear, bestSlot, bestGain = value, slot, gain
			end
			local sell = D.ItemSellPrice(itemId)
			if sell and sell > bestSell then
				bestSell = sell
			end
		end
	end
	parts.equipo = bestGear

	local money = inLog and D.RewardMoney(questId) or 0
	parts.oro = Clamp((money + bestSell) / GoldTarget(questLevel))

	parts.clase = IsClassQuest(questId, ctx) and 1 or 0
	parts.mazmorra = D.IsDungeonQuest(questId) and 1 or 0

	local miss = 1
	for name, value in pairs(parts) do
		miss = miss * (1 - Strength(ctx.weights[name]) * value)
	end

	cached = {
		parts = parts,
		value = 1 - miss,
		xp = xp,
		money = money,
		sell = bestSell,
		gearSlot = bestSlot,
		gearGain = bestGain,
		questLevel = questLevel,
	}
	cache[questId] = cached
	return cached
end

--- Valor que suman los pasos siguientes de la cadena, con descuento por distancia.
local function Downstream(questId, ctx, depth, visiting)
	local cached = ctx.downCache[questId]
	if cached then
		return cached
	end
	if depth > 40 or visiting[questId] then
		return 0
	end
	visiting[questId] = true

	local best = 0
	local successors = QR.Index.successors[questId]
	if successors then
		for nextId in pairs(successors) do
			if ctx.D.IsEligible(nextId) and not ctx.D.IsCompleted(nextId) then
				local value = Intrinsic(nextId, ctx, false).value
					+ CHAIN_DECAY * Downstream(nextId, ctx, depth + 1, visiting)
				if value > best then
					best = value
				end
			end
		end
	end

	visiting[questId] = nil
	ctx.downCache[questId] = best
	return best
end

--- Contexto del jugador para puntuar: se arma una vez por actualización.
function S.NewContext(D, weights)
	local classFile = D.PlayerClass()
	return {
		D = D,
		weights = weights,
		level = D.PlayerLevel(),
		xpMax = D.XPMax(),
		classFile = classFile,
		classSort = D.ClassSortKey(classFile),
		allClasses = D.AllClassesMask(),
		equipped = D.EquippedItemLevels(),
		zone = D.CurrentZone(),
		intrinsicCache = {},
		logCache = {},
		downCache = {},
	}
end

--- Puntúa una misión. inLog indica si ya está en el registro de misiones.
function S.Evaluate(questId, ctx, inLog)
	local D = ctx.D
	local own = Intrinsic(questId, ctx, inLog)
	local parts = {}
	for name, value in pairs(own.parts) do
		parts[name] = value
	end

	local step, total = QR.Index.Chain(questId)
	parts.historia = Clamp((total - 1) / 6)
	parts.cadena = Clamp(Downstream(questId, ctx, 0, {}) / CHAIN_FULL)

	local miss = 1
	for _, name in ipairs(S.COMPONENTS) do
		miss = miss * (1 - Strength(ctx.weights[name]) * parts[name])
	end
	local base = 1 - miss

	local difficulty = S.Difficulty(own.questLevel, ctx)
	local zone = D.QuestZone(questId)
	local sameZone = zone ~= nil and D.SameZone(zone, ctx.zone)
	local special = parts.clase > 0 or parts.mazmorra > 0 or total > step
	local multiplier = LevelFactor(own.questLevel, difficulty, ctx, special)
	if inLog and sameZone then
		multiplier = multiplier * 1.1
	end

	local complete = inLog and D.IsComplete(questId) or 0
	local value = Clamp(Compress(base * multiplier))
	if complete == 1 then
		value = 0.9 + 0.1 * base -- lista para entregar: arriba de todo
	elseif complete == -1 then
		value = value * 0.2 -- fallida
	end

	local tags = {
		historia = total >= 3,
		xp = parts.xp >= 0.7,
		oro = parts.oro >= 0.5,
		equipo = parts.equipo > 0,
		mazmorra = parts.mazmorra > 0,
		clase = parts.clase > 0,
	}
	tags.relleno = total <= 1 and not (tags.equipo or tags.mazmorra or tags.clase)

	return {
		id = questId,
		name = D.QuestName(questId),
		level = own.questLevel,
		requiredLevel = D.Quest(questId, "requiredLevel") or 0,
		zone = zone,
		sameZone = sameZone,
		difficulty = difficulty,
		complete = complete,
		inLog = inLog,
		score = floor(value * 100 + 0.5),
		parts = parts,
		tags = tags,
		step = step,
		chainTotal = total,
		xp = own.xp,
		money = own.money,
		sell = own.sell,
		gearSlot = own.gearSlot,
		gearGain = own.gearGain,
	}
end

--- Recomendadas: de tu zona (o de tu clase), ni grises ni demasiado difíciles.
function S.IsRecommended(result)
	if result.difficulty == "grey" or result.difficulty == "red" then
		return false
	end
	return result.tags.clase or result.sameZone
end

function S.Sort(list)
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		if a.level ~= b.level then
			return a.level < b.level
		end
		if a.name ~= b.name then
			return (a.name or "") < (b.name or "")
		end
		return a.id < b.id -- desempate fijo: el orden no cambia entre una vez y otra
	end)
	return list
end

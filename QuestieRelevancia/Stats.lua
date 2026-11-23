-- Evaluación del equipo por estadísticas: rama de talentos, rol, poder de cada
-- objeto según las estadísticas clave, comparación con la media de tu nivel y
-- con lo mejor que se puede conseguir, y los objetos "infaltables".
--
-- Las estadísticas salen de StatsData.lua (base de datos de CMaNGOS Classic);
-- las misiones, PNJ y zonas, de Questie.

local _, QR = ...

local S = {}
QR.Stats = S

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemStats = (C_Item and C_Item.GetItemStats) or GetItemStats
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

--------------------------------------------------------------------------------
-- Ranuras
--------------------------------------------------------------------------------

S.SLOTS = {
	{ id = 1, name = "Cabeza" }, { id = 2, name = "Cuello" }, { id = 3, name = "Hombros" },
	{ id = 15, name = "Espalda" }, { id = 5, name = "Pecho" }, { id = 9, name = "Muñecas" },
	{ id = 10, name = "Manos" }, { id = 6, name = "Cintura" }, { id = 7, name = "Piernas" },
	{ id = 8, name = "Pies" }, { id = 11, name = "Anillo" }, { id = 12, name = "Anillo" },
	{ id = 13, name = "Abalorio" }, { id = 14, name = "Abalorio" }, { id = 16, name = "Mano principal" },
	{ id = 17, name = "Mano secundaria" }, { id = 18, name = "A distancia" },
}

-- Tipo de objeto (InventoryType) -> ranuras donde va.
local INV_SLOTS = {
	[1] = { 1 }, [2] = { 2 }, [3] = { 3 }, [5] = { 5 }, [20] = { 5 }, [6] = { 6 }, [7] = { 7 },
	[8] = { 8 }, [9] = { 9 }, [10] = { 10 }, [11] = { 11, 12 }, [12] = { 13, 14 }, [16] = { 15 },
	[13] = { 16, 17 }, [17] = { 16 }, [21] = { 16 }, [22] = { 17 }, [14] = { 17 }, [23] = { 17 },
	[15] = { 18 }, [25] = { 18 }, [26] = { 18 }, [28] = { 18 },
}
S.INV_SLOTS = INV_SLOTS
local TWO_HAND = 17

--------------------------------------------------------------------------------
-- Qué puede usar cada clase
--------------------------------------------------------------------------------

local CLASS_BITS = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64,
	MAGE = 128, WARLOCK = 256, DRUID = 1024 }

-- Armaduras (subclase): 1 tela, 2 cuero, 3 malla, 4 placas, 6 escudo, 7 tratado, 8 ídolo, 9 tótem.
local ARMOR = {
	WARRIOR = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = 40, [6] = true },
	PALADIN = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = 40, [6] = true, [7] = true },
	HUNTER = { [0] = true, [1] = true, [2] = true, [3] = 40 },
	ROGUE = { [0] = true, [1] = true, [2] = true },
	PRIEST = { [0] = true, [1] = true },
	SHAMAN = { [0] = true, [1] = true, [2] = true, [3] = 40, [6] = true, [9] = true },
	MAGE = { [0] = true, [1] = true },
	WARLOCK = { [0] = true, [1] = true },
	DRUID = { [0] = true, [1] = true, [2] = true, [8] = true },
}
-- Armas (subclase): 0 hacha, 1 hacha 2M, 2 arco, 3 arma de fuego, 4 maza, 5 maza 2M, 6 arma de asta,
-- 7 espada, 8 espada 2M, 10 bastón, 13 puño, 14 varios, 15 daga, 16 arrojadiza, 18 ballesta, 19 varita.
local WEAPONS = {
	WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 14, 15, 16, 18 },
	PALADIN = { 0, 1, 4, 5, 6, 7, 8, 14 },
	HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 14, 15, 16, 18 },
	ROGUE = { 2, 3, 4, 7, 13, 14, 15, 16, 18 },
	PRIEST = { 4, 10, 14, 15, 19 },
	SHAMAN = { 0, 1, 4, 5, 10, 13, 14, 15 },
	MAGE = { 7, 10, 14, 15, 19 },
	WARLOCK = { 7, 10, 14, 15, 19 },
	DRUID = { 4, 5, 10, 13, 14, 15 },
}
local WEAPON_SET = {}
for class, list in pairs(WEAPONS) do
	WEAPON_SET[class] = {}
	for _, sub in ipairs(list) do
		WEAPON_SET[class][sub] = true
	end
end
local DUAL_WIELD = { WARRIOR = 20, ROGUE = 1, HUNTER = 20 }

local function HasBit(mask, bitValue)
	if not mask or mask <= 0 then
		return true
	end
	return mask % (2 * bitValue) >= bitValue
end
S.HasBit = HasBit

--------------------------------------------------------------------------------
-- Datos de los objetos
--------------------------------------------------------------------------------

local PRIMARY = { "S", "A", "T", "I", "P" }
local cache = {}

local function DecodeSources(text)
	local sources = {}
	for part in string.gmatch(text or "", "[^|]+") do
		local kind, rest = part:sub(1, 1), part:sub(2)
		if kind == "q" or kind == "Q" or kind == "R" or kind == "v" then
			local ids = {}
			for id in string.gmatch(rest, "%d+") do
				ids[#ids + 1] = tonumber(id)
			end
			-- q: misión, Q: misión de mazmorra, R: misión de banda.
			sources[#sources + 1] = { kind = kind == "v" and "vendor" or "quest", ids = ids,
				dungeon = kind == "Q", raid = kind == "R" }
		elseif kind == "c" then
			local skill, rank = rest:match("^(%d+)%.(%d+)")
			sources[#sources + 1] = { kind = "craft", skill = tonumber(skill), rank = tonumber(rank) }
		elseif kind == "w" then
			sources[#sources + 1] = { kind = "world", chance = tonumber(rest) or 0 }
		elseif kind == "d" then
			local list = {}
			for creature, chance, instance, rank in string.gmatch(rest, "(%d+):([%d.e+-]+):(%d+):(%d+)") do
				list[#list + 1] = { npc = tonumber(creature), chance = tonumber(chance) or 0,
					instance = tonumber(instance), rank = tonumber(rank) }
			end
			sources[#sources + 1] = { kind = "drop", list = list }
		elseif kind == "g" then
			local object, chance, instance = rest:match("^(%d+):([%d.e+-]+):(%d+)")
			sources[#sources + 1] = { kind = "chest", object = tonumber(object), chance = tonumber(chance) or 0,
				instance = tonumber(instance) }
		elseif kind == "p" then
			sources[#sources + 1] = { kind = "pvprep" } -- intendente de campo de batalla
		elseif kind == "x" then
			sources[#sources + 1] = { kind = "raidrep" } -- pide reputación que solo se sube en bandas
		elseif kind == "i" then
			local container, chance = rest:match("^(%d+):([%d.e+-]+)")
			sources[#sources + 1] = { kind = "container", item = tonumber(container), chance = tonumber(chance) or 0 }
		end
	end
	return sources
end

--- Datos de un objeto de la base (nil si no está).
function S.Item(itemId)
	local item = cache[itemId]
	if item ~= nil then
		return item or nil
	end
	local raw = QR.StatsData and QR.StatsData.items[itemId]
	if not raw then
		cache[itemId] = false
		return nil
	end
	local head, statText, sourceText = raw:match("^([^;]*);([^;]*);(.*)$")
	local f = {}
	for value in string.gmatch(head, "[^,]+") do
		f[#f + 1] = value
	end
	item = {
		id = itemId, inv = tonumber(f[1]), class = tonumber(f[2]), subClass = tonumber(f[3]),
		quality = tonumber(f[4]), itemLevel = tonumber(f[5]), requiredLevel = tonumber(f[6]),
		classes = tonumber(f[7]), races = tonumber(f[8]), bind = tonumber(f[9]), random = f[10] == "1",
		set = tonumber(f[11]), honor = tonumber(f[12]) or 0, stats = {},
	}
	local repFaction, repRank = (f[13] or "0"):match("^(%d+)%.(%d+)$")
	if repFaction then
		item.repFaction, item.repRank = tonumber(repFaction), tonumber(repRank)
	end
	for key, value in string.gmatch(statText, "(%a+)(%-?%d+)") do
		item.stats[key] = tonumber(value)
	end
	item.sources = DecodeSources(sourceText)
	-- De banda: solo se consigue en bandas (botín o misiones de banda).
	local raid, other, forced = false, false, false
	for _, source in ipairs(item.sources) do
		if source.kind == "drop" then
			for _, drop in ipairs(source.list) do
				if S.IsRaid(drop.instance) then
					raid = true
				else
					other = true
				end
			end
		elseif source.kind == "quest" and source.raid then
			raid = true
		elseif source.kind == "raidrep" then
			forced = true
		elseif source.kind == "pvprep" then
			item.pvp = true
		else
			other = true
		end
	end
	item.raid = forced or (raid and not other)
	cache[itemId] = item
	return item
end

--------------------------------------------------------------------------------
-- Mazmorras y bandas
--------------------------------------------------------------------------------

S.INSTANCE_NAMES = {
	[33] = "Castillo de Colmillo Oscuro", [34] = "Las Mazmorras", [36] = "Las Minas de la Muerte",
	[43] = "Cuevas de los Lamentos", [47] = "Horado Rajacieno", [48] = "Cavernas de Brazanegra",
	[70] = "Uldaman", [90] = "Gnomeregan", [109] = "El Templo de Atal'Hakkar", [129] = "Zahúrda Rajacieno",
	[189] = "Monasterio Escarlata", [209] = "Zul'Farrak", [229] = "Cumbre de Roca Negra",
	[230] = "Profundidades de Roca Negra", [249] = "Guarida de Onyxia", [289] = "Scholomance",
	[309] = "Zul'Gurub", [329] = "Stratholme", [349] = "Maraudon", [389] = "Sima Ígnea",
	[409] = "Núcleo de Magma", [429] = "La Masacre", [469] = "Guarida Alanegra",
	[509] = "Ruinas de Ahn'Qiraj", [531] = "Templo de Ahn'Qiraj", [533] = "Naxxramas",
	[999] = "jefe del mundo",
}
local RAID_MAPS = { [249] = true, [309] = true, [409] = true, [469] = true, [509] = true, [531] = true, [533] = true,
	[999] = true }
-- Zonas de Questie (áreas) de las bandas, para los jefes que no tienen aparición fija.
local RAID_AREAS = { [2717] = 409, [2677] = 469, [2159] = 249, [1977] = 309, [3429] = 509, [3428] = 531, [3456] = 533 }

function S.IsRaid(instance)
	return RAID_MAPS[instance or 0] == true
end

function S.InstanceName(instance)
	if not instance or instance == 0 then
		return nil
	end
	return S.INSTANCE_NAMES[instance]
end

--------------------------------------------------------------------------------
-- Ramas de talentos, roles y pesos
--------------------------------------------------------------------------------

-- Pesos: cuánto vale cada punto de cada estadística, con la principal en 1.
-- D es el daño por segundo del arma en décimas (D10 = 1 de DPS).
local PROFILES = {
	warrior_dps = { weapon = "melee", offhand = 0.5,
		w = { S = 1, A = 0.85, T = 0.25, ap = 0.5, crit = 14, hit = 15, ws = 3, D = 0.7, R = 0.01, hp = 0.02 },
		key = { "S", "A", "crit", "hit", "D" } },
	warrior_tank = { weapon = "melee", offhand = 0,
		w = { T = 1, def = 1.5, R = 0.08, A = 0.6, dodge = 12, parry = 12, block = 8, B = 0.3, S = 0.4,
			hit = 6, crit = 3, ap = 0.15, D = 0.3, hp = 0.1 },
		key = { "T", "def", "R", "A", "dodge" } },
	rogue = { weapon = "melee", offhand = 0.5,
		w = { A = 1, S = 0.5, T = 0.25, ap = 0.5, crit = 14, hit = 15, ws = 3, D = 0.7, R = 0.005, hp = 0.02 },
		key = { "A", "crit", "hit", "ap", "D" } },
	hunter = { weapon = "ranged",
		w = { A = 1, I = 0.35, T = 0.25, S = 0.05, rap = 0.45, ap = 0.05, crit = 14, hit = 15, D = 0.8, P = 0.05,
			mp5 = 0.6, R = 0.005 },
		key = { "A", "rap", "crit", "hit", "I" } },
	paladin_holy = { weapon = "caster",
		w = { heal = 1, I = 0.7, scrit = 9, mp5 = 1.6, P = 0.1, T = 0.15 },
		key = { "heal", "I", "mp5", "scrit" } },
	paladin_tank = { weapon = "melee", offhand = 0,
		w = { T = 1, def = 1.5, R = 0.08, A = 0.5, I = 0.3, sp = 0.4, spHo = 0.4, S = 0.3, dodge = 12, parry = 12,
			block = 8, B = 0.4, mp5 = 0.4, hit = 5, D = 0.2, hp = 0.1 },
		key = { "T", "def", "R", "sp", "I" } },
	paladin_dps = { weapon = "melee", offhand = 0,
		w = { S = 1, A = 0.6, I = 0.3, T = 0.25, ap = 0.5, crit = 12, hit = 12, sp = 0.2, spHo = 0.2, D = 0.8,
			mp5 = 0.3, R = 0.005 },
		key = { "S", "crit", "hit", "A", "D" } },
	shaman_ele = { weapon = "caster",
		w = { sp = 1, spNa = 0.9, spFi = 0.1, spFr = 0.05, I = 0.45, P = 0.1, T = 0.15, scrit = 10, scritNa = 8,
			shit = 12, mp5 = 0.8 },
		key = { "sp", "I", "scrit", "shit", "mp5" } },
	shaman_enh = { weapon = "melee", offhand = 0,
		w = { S = 1, A = 0.7, I = 0.3, T = 0.25, ap = 0.5, crit = 12, hit = 12, D = 0.8, mp5 = 0.3, sp = 0.1 },
		key = { "S", "A", "crit", "hit", "D" } },
	shaman_resto = { weapon = "caster",
		w = { heal = 1, I = 0.55, mp5 = 1.6, scrit = 5, P = 0.15, T = 0.15 },
		key = { "heal", "mp5", "I", "scrit" } },
	mage_arcane = { weapon = "caster",
		w = { sp = 1, spAr = 0.3, spFr = 0.5, spFi = 0.3, I = 0.5, P = 0.25, T = 0.15, scrit = 9, shit = 13, mp5 = 0.8 },
		key = { "sp", "I", "shit", "scrit", "P" } },
	mage_fire = { weapon = "caster",
		w = { sp = 1, spFi = 0.95, I = 0.4, P = 0.1, T = 0.15, scrit = 11, scritFi = 10, shit = 13, mp5 = 0.6, pen = 0.2 },
		key = { "sp", "scrit", "shit", "I" } },
	mage_frost = { weapon = "caster",
		w = { sp = 1, spFr = 0.95, I = 0.4, P = 0.1, T = 0.2, scrit = 8, scritFr = 7, shit = 13, mp5 = 0.6, pen = 0.2 },
		key = { "sp", "shit", "scrit", "I" } },
	warlock = { weapon = "caster",
		w = { sp = 1, spSh = 0.95, spFi = 0.1, I = 0.35, T = 0.35, P = 0.1, scrit = 7, shit = 13, mp5 = 0.4 },
		key = { "sp", "shit", "T", "I", "scrit" } },
	warlock_destro = { weapon = "caster",
		w = { sp = 1, spSh = 0.9, spFi = 0.2, I = 0.35, T = 0.3, P = 0.1, scrit = 10, scritSh = 9, shit = 13, mp5 = 0.4 },
		key = { "sp", "shit", "scrit", "T", "I" } },
	priest_heal = { weapon = "caster",
		w = { heal = 1, I = 0.5, P = 0.55, mp5 = 1.5, scrit = 5, T = 0.15 },
		key = { "heal", "P", "mp5", "I" } },
	priest_shadow = { weapon = "caster",
		w = { sp = 1, spSh = 0.95, I = 0.35, P = 0.25, T = 0.2, scrit = 4, shit = 13, mp5 = 0.6 },
		key = { "sp", "shit", "I", "P" } },
	druid_balance = { weapon = "caster",
		w = { sp = 1, spAr = 0.5, spNa = 0.5, I = 0.45, P = 0.25, T = 0.15, scrit = 9, shit = 12, mp5 = 0.8 },
		key = { "sp", "I", "scrit", "shit", "mp5" } },
	druid_tank = { weapon = "feral",
		w = { T = 1, R = 0.1, A = 0.9, S = 0.5, def = 1, dodge = 12, ap = 0.25, hit = 6, crit = 3, hp = 0.1 },
		key = { "T", "R", "A", "dodge", "def" } },
	druid_cat = { weapon = "feral",
		w = { A = 1, S = 0.85, ap = 0.45, crit = 14, hit = 14, T = 0.15 },
		key = { "A", "S", "crit", "hit", "ap" } },
	druid_resto = { weapon = "caster",
		w = { heal = 1, I = 0.5, P = 0.55, mp5 = 1.4, scrit = 3, T = 0.15 },
		key = { "heal", "P", "mp5", "I" } },
}
S.PROFILES = PROFILES

-- Ramas en el orden del juego, con los roles que cubre cada una (el primero es el habitual).
S.TREES = {
	WARRIOR = { { name = "Armas", dps = "warrior_dps" }, { name = "Furia", dps = "warrior_dps" },
		{ name = "Protección", tank = "warrior_tank", dps = "warrior_dps", default = "tank" } },
	PALADIN = { { name = "Sagrado", healer = "paladin_holy", default = "healer" },
		{ name = "Protección", tank = "paladin_tank", default = "tank" },
		{ name = "Reprensión", dps = "paladin_dps" } },
	HUNTER = { { name = "Dominio de bestias", dps = "hunter" }, { name = "Puntería", dps = "hunter" },
		{ name = "Supervivencia", dps = "hunter" } },
	ROGUE = { { name = "Asesinato", dps = "rogue" }, { name = "Combate", dps = "rogue" }, { name = "Sutileza", dps = "rogue" } },
	PRIEST = { { name = "Disciplina", healer = "priest_heal", dps = "priest_shadow", default = "healer" },
		{ name = "Sagrado", healer = "priest_heal", default = "healer" }, { name = "Sombra", dps = "priest_shadow" } },
	SHAMAN = { { name = "Elemental", dps = "shaman_ele" }, { name = "Mejora", dps = "shaman_enh" },
		{ name = "Restauración", healer = "shaman_resto", default = "healer" } },
	MAGE = { { name = "Arcano", dps = "mage_arcane" }, { name = "Fuego", dps = "mage_fire" },
		{ name = "Escarcha", dps = "mage_frost" } },
	WARLOCK = { { name = "Aflicción", dps = "warlock" }, { name = "Demonología", dps = "warlock" },
		{ name = "Destrucción", dps = "warlock_destro" } },
	DRUID = { { name = "Equilibrio", dps = "druid_balance" },
		{ name = "Combate feral", tank = "druid_tank", dps = "druid_cat", default = "tank" },
		{ name = "Restauración", healer = "druid_resto", default = "healer" } },
}
-- Rama para quien todavía no tiene talentos.
local START_TREE = { WARRIOR = 1, PALADIN = 3, HUNTER = 2, ROGUE = 2, PRIEST = 2, SHAMAN = 2, MAGE = 3,
	WARLOCK = 1, DRUID = 2 }
S.ROLE_NAMES = { dps = "DPS", tank = "Tanque", healer = "Sanador" }

local function TreePoints(index)
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
		local ok, _, name, _, _, _, _, points = pcall(C_SpecializationInfo.GetSpecializationInfo, index)
		if ok and name then
			return points or 0, name
		end
	end
	if GetTalentTabInfo then
		local ok, a, b, c, d, e = pcall(GetTalentTabInfo, index)
		if ok then
			if type(a) == "number" then
				return e or 0, b -- especificación, nombre, descripción, ícono, puntos
			end
			return c or 0, a -- nombre, ícono, puntos
		end
	end
	return 0, nil
end

--- Rama de talentos detectada: {index, points = {a, b, c}, names, hybrid, none}.
function S.DetectSpec(classFile)
	local trees = S.TREES[classFile]
	if not trees then
		return nil
	end
	local result = { points = {}, names = {} }
	local best, second = 0, 0
	for index = 1, 3 do
		local points, name = TreePoints(index)
		result.points[index] = points
		result.names[index] = name or trees[index].name
		if points > (result.points[best] or -1) then
			best = index
		end
	end
	for index = 1, 3 do
		if index ~= best and result.points[index] > second then
			second = result.points[index]
		end
	end
	if best == 0 or result.points[best] == 0 then
		result.index, result.none = START_TREE[classFile] or 1, true
	else
		result.index = best
		result.hybrid = second > 0 and result.points[best] - second <= 3
	end
	return result
end

--- Roles que puede cubrir la clase.
function S.ClassRoles(classFile)
	local roles, seen = {}, {}
	for _, role in ipairs({ "dps", "tank", "healer" }) do
		for _, tree in ipairs(S.TREES[classFile] or {}) do
			if tree[role] and not seen[role] then
				seen[role] = true
				roles[#roles + 1] = role
			end
		end
	end
	return roles
end

function S.DefaultRole(classFile, treeIndex)
	local tree = S.TREES[classFile] and S.TREES[classFile][treeIndex]
	if not tree then
		return "dps"
	end
	return tree.default or (tree.dps and "dps") or (tree.tank and "tank") or "healer"
end

--- Perfil de pesos para una clase, rama y rol. Si la rama no cubre ese rol, se usa
--- la primera rama de la clase que lo cubra.
function S.Profile(classFile, treeIndex, role)
	local trees = S.TREES[classFile]
	if not trees then
		return nil
	end
	local tree = trees[treeIndex] or trees[1]
	local key = tree[role]
	if not key then
		for _, other in ipairs(trees) do
			if other[role] then
				key = other[role]
				break
			end
		end
	end
	key = key or tree[S.DefaultRole(classFile, treeIndex)]
	local profile = PROFILES[key]
	return profile and setmetatable({ id = key, classFile = classFile, role = role }, { __index = profile })
end

--------------------------------------------------------------------------------
-- Poder de un objeto
--------------------------------------------------------------------------------

local SUFFIX_PAIRS = {
	{ "A", "T" }, { "S", "A" }, { "S", "T" }, { "I", "T" }, { "I", "P" }, { "T", "P" }, { "S", "I" },
	{ "S", "P" }, { "A", "I" }, { "A", "P" }, { "S" }, { "A" }, { "T" }, { "I" }, { "P" },
}

--- Estadísticas estimadas de un objeto con sufijo al azar: el mejor sufijo para el perfil.
local function SuffixStats(item, profile)
	local budget = QR.StatsData.budget and QR.StatsData.budget[item.inv]
	local ratio = budget and budget[item.quality >= 3 and 2 or 1] or 0
	if ratio <= 0 then
		ratio = budget and (budget[2] or budget[1]) or 0.3
		if ratio <= 0 then
			ratio = 0.3
		end
	end
	local points = math.floor(ratio * (item.itemLevel or 0) + 0.5)
	if points <= 0 then
		return nil
	end
	local best, bestValue
	for _, pair in ipairs(SUFFIX_PAIRS) do
		local value = 0
		for _, stat in ipairs(pair) do
			value = value + (profile.w[stat] or 0) * points / #pair
		end
		if not bestValue or value > bestValue then
			best, bestValue = pair, value
		end
	end
	local stats = {}
	for _, stat in ipairs(best) do
		stats[stat] = math.floor(points / #best + 0.5)
	end
	return stats
end

local function SchoolWeight(profile, key)
	return profile.w[key] or 0
end

--- Poder de un conjunto de estadísticas en la ranura dada.
function S.StatsPower(stats, profile, slot, inv)
	local w, total = profile.w, 0
	for key, value in pairs(stats) do
		if key == "D" then
			local factor = 0
			if profile.weapon == "melee" then
				if slot == 16 then
					factor = 1
				elseif slot == 17 then
					factor = profile.offhand or 0
				else
					factor = 0.05
				end
			elseif profile.weapon == "ranged" then
				factor = slot == 18 and 1 or 0.05
			end
			-- Las armas a dos manos tienen más daño, pero ocupan las dos manos: se compara el total.
			total = total + (w.D or 0) * value * factor
		elseif key ~= "W" and key ~= "proc" then
			total = total + SchoolWeight(profile, key) * value
		end
	end
	return total
end

--- Estadísticas de un objeto para un perfil (con el sufijo estimado si hace falta).
function S.ItemStats(item, profile)
	if not item.random then
		return item.stats, false
	end
	for _, stat in ipairs(PRIMARY) do
		if item.stats[stat] then
			return item.stats, false
		end
	end
	local suffix = SuffixStats(item, profile)
	if not suffix then
		return item.stats, false
	end
	local stats = {}
	for key, value in pairs(item.stats) do
		stats[key] = value
	end
	for key, value in pairs(suffix) do
		stats[key] = (stats[key] or 0) + value
	end
	return stats, true
end

function S.ItemPower(item, profile, slot)
	local stats, estimated = S.ItemStats(item, profile)
	return S.StatsPower(stats, profile, slot or INV_SLOTS[item.inv][1], item.inv), estimated
end

--------------------------------------------------------------------------------
-- Lo que llevás puesto
--------------------------------------------------------------------------------

-- Estadísticas que da el juego -> nuestras claves.
local GAME_STATS = {
	ITEM_MOD_STRENGTH_SHORT = "S", ITEM_MOD_AGILITY_SHORT = "A", ITEM_MOD_STAMINA_SHORT = "T",
	ITEM_MOD_INTELLECT_SHORT = "I", ITEM_MOD_SPIRIT_SHORT = "P", RESISTANCE0_NAME = "R",
	ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
	ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp",
	ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal", ITEM_MOD_MANA_REGENERATION_SHORT = "mp5",
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def", ITEM_MOD_BLOCK_VALUE_SHORT = "B",
}

local function GameItemStats(link)
	if not link or not GetItemStats then
		return nil
	end
	local ok, raw = pcall(GetItemStats, link)
	if not ok or type(raw) ~= "table" then
		return nil
	end
	local stats, any = {}, false
	for key, value in pairs(raw) do
		local ours = GAME_STATS[key]
		if ours then
			stats[ours] = (stats[ours] or 0) + value
			any = true
		elseif key == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then
			stats.D = math.floor(value * 10 + 0.5)
			any = true
		end
	end
	return any and stats or nil
end

--- Lo que llevás en cada ranura: {item = datos de la base o nil, stats, unknown}.
function S.Equipped()
	local equipped = {}
	for _, slot in ipairs(S.SLOTS) do
		local itemId = GetInventoryItemID("player", slot.id)
		if itemId then
			local link = GetInventoryItemLink("player", slot.id)
			local item = S.Item(itemId)
			local entry = { itemId = itemId, link = link, item = item }
			if item and item.random then
				-- El sufijo lo dice el juego; lo demás (armadura, efectos), la base.
				local game = GameItemStats(link)
				if game then
					local stats = {}
					for key, value in pairs(item.stats) do
						stats[key] = value
					end
					for _, stat in ipairs(PRIMARY) do
						if game[stat] then
							stats[stat] = game[stat]
						end
					end
					for _, key in ipairs({ "sp", "heal", "ap", "rap", "mp5" }) do
						if game[key] and not stats[key] then
							stats[key] = game[key]
						end
					end
					entry.stats = stats
				end
			elseif not item then
				-- Objeto que la base no conoce (por ejemplo, nuevo de Forever): datos del juego.
				entry.stats = GameItemStats(link)
				entry.unknown = entry.stats == nil
				entry.fromGame = true
			end
			equipped[slot.id] = entry
		end
	end
	return equipped
end

local function EntryPower(entry, profile, slot)
	if not entry then
		return 0
	end
	if entry.stats then
		return S.StatsPower(entry.stats, profile, slot, entry.item and entry.item.inv)
	end
	if entry.item then
		return (S.ItemPower(entry.item, profile, slot))
	end
	return 0
end

local function EntryStats(entry, profile)
	if not entry then
		return nil
	end
	if entry.stats then
		return entry.stats
	end
	if entry.item then
		return (S.ItemStats(entry.item, profile))
	end
	return nil
end

--------------------------------------------------------------------------------
-- Quién puede usar qué
--------------------------------------------------------------------------------

local function PlayerRaceBit()
	if not UnitRace then
		return nil
	end
	local _, _, raceId = UnitRace("player")
	return raceId and 2 ^ (raceId - 1) or nil
end

--- ¿Puede la clase usar el objeto? (sin mirar el nivel)
function S.CanUse(item, ctx)
	if not HasBit(item.classes, ctx.classBit) then
		return false
	end
	if ctx.raceBit and not HasBit(item.races, ctx.raceBit) then
		return false
	end
	if item.class == 4 then
		local allowed = ARMOR[ctx.classFile] and ARMOR[ctx.classFile][item.subClass]
		if not allowed or (type(allowed) == "number" and ctx.level < allowed) then
			return false
		end
	elseif item.class == 2 then
		if not (WEAPON_SET[ctx.classFile] and WEAPON_SET[ctx.classFile][item.subClass]) then
			return false
		end
		if item.inv == 22 or (item.inv == 13 and ctx.offhandOnly) then
			local from = DUAL_WIELD[ctx.classFile]
			if not from or ctx.level < from then
				return false
			end
		end
	end
	if item.inv == 14 and not (ARMOR[ctx.classFile] and ARMOR[ctx.classFile][6]) then
		return false
	end
	return true
end

--- Contexto del personaje para todos los cálculos.
function S.Context(classFile, level, treeIndex, role)
	local profile = S.Profile(classFile, treeIndex, role)
	return {
		classFile = classFile, classBit = CLASS_BITS[classFile] or 0, level = level,
		raceBit = PlayerRaceBit(), profile = profile, tree = treeIndex, role = role,
		dualWield = DUAL_WIELD[classFile] ~= nil and level >= DUAL_WIELD[classFile],
	}
end

-- ¿Sirve el objeto en la ranura? (una mano en la secundaria solo con doble empuñadura)
local function FitsSlot(item, slot, ctx)
	if slot == 17 and item.inv == 13 then
		return ctx.dualWield
	end
	if slot == 17 and item.class == 2 and item.inv ~= 13 and item.inv ~= 22 then
		return false
	end
	return true
end

--------------------------------------------------------------------------------
-- Índice de objetos por ranura (se arma una sola vez)
--------------------------------------------------------------------------------

local bySlot

function S.Index()
	if bySlot then
		return bySlot
	end
	bySlot = {}
	for _, slot in ipairs(S.SLOTS) do
		bySlot[slot.id] = {}
	end
	for itemId in pairs(QR.StatsData.items) do
		local item = S.Item(itemId)
		for _, slot in ipairs(item and INV_SLOTS[item.inv] or {}) do
			table.insert(bySlot[slot], item)
		end
	end
	return bySlot
end

--------------------------------------------------------------------------------
-- Media, techo e infaltables
--------------------------------------------------------------------------------

local AVERAGE_QUALITY = { [2] = true, [3] = true }

--- Media de poder y de estadísticas de los objetos verdes y azules de tu nivel para la ranura.
function S.Average(slot, ctx, mode)
	local level = ctx.level
	for _, window in ipairs({ 5, 10, 20 }) do
		local count, power, stats = 0, 0, {}
		for _, item in ipairs(S.Index()[slot]) do
			local req = item.requiredLevel
			if AVERAGE_QUALITY[item.quality] and req <= level and req >= level - window and item.honor == 0
				and not item.raid and S.CanUse(item, ctx) and FitsSlot(item, slot, ctx)
				and ((mode == "2h") == (item.inv == TWO_HAND) or slot ~= 16) then
				local itemStats = S.ItemStats(item, ctx.profile)
				count = count + 1
				power = power + S.StatsPower(itemStats, ctx.profile, slot, item.inv)
				for key, value in pairs(itemStats) do
					stats[key] = (stats[key] or 0) + value
				end
			end
		end
		if count >= 4 or (window == 20 and count > 0) then
			for key, value in pairs(stats) do
				stats[key] = value / count
			end
			return power / count, stats, count
		end
	end
	return nil
end

-- Costo de conseguir un objeto por cada fuente: 1 es una misión fácil.
local function DropCost(chance, raid)
	local runs = 100 / math.max(chance, 0.5)
	return (raid and 4 or 1) + 0.25 * math.min(runs, 20)
end

--- Fuentes que le sirven al personaje, ordenadas de la más fácil a la más difícil.
function S.UsableSources(item, ctx, env)
	env = env or S.Env
	local out = {}
	if item.raid and ctx.level < 60 then
		return out
	end
	for _, source in ipairs(item.sources) do
		if source.kind == "quest" then
			if not source.raid or ctx.level >= 60 then
				for _, questId in ipairs(source.ids) do
					if env.QuestOk(questId, ctx) then
						out[#out + 1] = { kind = "quest", id = questId, dungeon = source.dungeon, raid = source.raid,
							cost = (source.raid and 8) or (source.dungeon and 2) or 1 }
						break
					end
				end
			end
		elseif source.kind == "vendor" then
			for _, npc in ipairs(source.ids) do
				if env.NpcFriendly(npc) then
					out[#out + 1] = { kind = "vendor", id = npc,
						cost = (item.raid and 6) or (item.pvp and 3.5) or (item.repFaction and 3) or 1.2,
						repFaction = item.repFaction, repRank = item.repRank, pvp = item.pvp }
					break
				end
			end
		elseif source.kind == "craft" then
			local have = env.ProfessionSkill(source.skill)
			local cost
			if have and have >= source.rank then
				cost = 1.3
			elseif have then
				cost = 1.8
			elseif item.bind ~= 1 then
				cost = 2.2 -- se lo podés pedir a un artesano o comprar en la subasta
			else
				cost = 5
			end
			out[#out + 1] = { kind = "craft", skill = source.skill, rank = source.rank, cost = cost, have = have }
		elseif source.kind == "drop" then
			local best
			for _, drop in ipairs(source.list) do
				local instance = drop.instance
				if (instance or 0) == 0 then
					instance = env.NpcInstance(drop.npc)
				end
				local raid = S.IsRaid(instance)
				local cost = DropCost(drop.chance, raid)
				if not raid or ctx.level >= 60 then
					if not best or cost < best.cost then
						best = { kind = "drop", npc = drop.npc, chance = drop.chance, instance = instance,
							raid = raid, cost = cost }
					end
				end
			end
			if best then
				out[#out + 1] = best
			end
		elseif source.kind == "world" then
			out[#out + 1] = { kind = "world", chance = source.chance, cost = item.bind ~= 1 and 2.5 or 8,
				auction = item.bind ~= 1 }
		elseif source.kind == "chest" then
			out[#out + 1] = { kind = "chest", object = source.object, instance = source.instance, cost = 3 }
		elseif source.kind == "container" then
			out[#out + 1] = { kind = "container", item = source.item, cost = 2.5 }
		end
	end
	table.sort(out, function(a, b) return a.cost < b.cost end)
	return out
end

local function Clone(entry)
	return entry and { itemId = entry.itemId, item = entry.item, stats = entry.stats, link = entry.link } or nil
end

--- Evaluación completa: por ranura (lo tuyo, la media, el techo) e infaltables.
function S.Evaluate(ctx, equipped, env)
	env = env or S.Env
	local profile = ctx.profile
	local mainHand = equipped[16] and equipped[16].item
	local mode = (mainHand and mainHand.inv == TWO_HAND) and "2h" or "1h"
	local report = { slots = {}, mustHave = {}, mode = mode, totals = { have = 0, average = 0, best = 0, raid = 0 },
		unknown = 0 }
	for _, entry in pairs(equipped) do
		if entry.unknown then
			report.unknown = report.unknown + 1
		end
	end
	local keyHave, keyAverage = {}, {}

	local current = {}
	for _, slot in ipairs(S.SLOTS) do
		current[slot.id] = EntryPower(equipped[slot.id], profile, slot.id)
	end

	local candidates = {}
	for _, slot in ipairs(S.SLOTS) do
		local id = slot.id
		local entry = equipped[id]
		local row = { slot = id, name = slot.name, entry = Clone(entry), have = current[id] }
		local skip = (id == 17 and mode == "2h") or (id == 18 and profile.weapon == "caster" and ctx.classFile ~= "PRIEST"
			and ctx.classFile ~= "MAGE" and ctx.classFile ~= "WARLOCK" and ctx.classFile ~= "PALADIN"
			and ctx.classFile ~= "SHAMAN" and ctx.classFile ~= "DRUID")
		row.skip = skip
		local trinket = id == 13 or id == 14

		local average, averageStats = S.Average(id, ctx, mode)
		row.average = average
		if not skip and not trinket and average and average > 0 then
			report.totals.have = report.totals.have + row.have
			report.totals.average = report.totals.average + average
			for key, value in pairs(averageStats) do
				keyAverage[key] = (keyAverage[key] or 0) + value
			end
		end
		local stats = EntryStats(entry, profile)
		for key, value in pairs(stats or {}) do
			keyHave[key] = (keyHave[key] or 0) + value
		end

		-- Lo mejor que se puede conseguir hasta tu nivel (sin bandas y con bandas).
		local best, bestPower, bestRaid, bestRaidPower
		for _, item in ipairs(S.Index()[id]) do
			if item.requiredLevel <= ctx.level and item.honor == 0 and S.CanUse(item, ctx)
				and FitsSlot(item, id, ctx) then
				local twoHand = item.inv == TWO_HAND
				local power, estimated = S.ItemPower(item, profile, id)
				-- Un arma a dos manos se compara con lo que llevás en las dos manos.
				local base = current[id]
				if id == 16 and twoHand and mode == "1h" then
					base = current[16] + current[17]
				elseif id == 16 and not twoHand and mode == "2h" then
					base = nil -- cambiar una a dos manos por una de una mano no se compara acá
				end
				if (id == 16 and ((mode == "2h") == twoHand)) or id ~= 16 then
					if item.raid then
						if not bestRaidPower or power > bestRaidPower then
							bestRaid, bestRaidPower = item, power
						end
					elseif not bestPower or power > bestPower then
						best, bestPower = item, power
					end
				end
				if base and not item.raid and power > base + 0.5 then
					local alreadyHave = (equipped[id] and equipped[id].itemId == item.id)
						or (id == 11 and equipped[12] and equipped[12].itemId == item.id)
						or (id == 12 and equipped[11] and equipped[11].itemId == item.id)
						or (id == 13 and equipped[14] and equipped[14].itemId == item.id)
						or (id == 14 and equipped[13] and equipped[13].itemId == item.id)
					if not alreadyHave then
						candidates[#candidates + 1] = { item = item, slot = id, gain = power - base, power = power,
							estimated = estimated }
					end
				end
			end
		end
		row.best, row.bestPower = best, bestPower
		row.bestRaid, row.bestRaidPower = bestRaid, bestRaidPower
		if not skip and not trinket and bestPower and bestPower > 0 then
			report.totals.best = report.totals.best + math.max(bestPower, row.have)
			report.totals.raid = report.totals.raid + math.max(bestRaidPower or 0, bestPower, row.have)
		end
		report.slots[#report.slots + 1] = row
	end

	-- Anillos y abalorios: el candidato reemplaza al más flojo de los dos; no se repite.
	local seen = {}
	local scored = {}
	for _, candidate in ipairs(candidates) do
		local key = candidate.item.id
		local slot = candidate.slot
		local pair = (slot == 12 and 11) or (slot == 11 and 12) or (slot == 14 and 13) or (slot == 13 and 14)
		local weaker = pair and current[pair] < current[slot]
		if not seen[key] and not weaker then
			local sources = S.UsableSources(candidate.item, ctx, env)
			if sources[1] then
				seen[key] = true
				candidate.sources = sources
				candidate.cost = sources[1].cost
				candidate.score = candidate.gain / candidate.cost
				candidate.owned = env.ItemCount(key) > 0
				scored[#scored + 1] = candidate
			end
		end
	end
	table.sort(scored, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.item.id < b.item.id
	end)
	local perSlot = {}
	for _, candidate in ipairs(scored) do
		local slotKey = (candidate.slot == 12 and 11) or (candidate.slot == 14 and 13) or candidate.slot
		perSlot[slotKey] = (perSlot[slotKey] or 0) + 1
		if perSlot[slotKey] <= 2 then
			report.mustHave[#report.mustHave + 1] = candidate
		end
		if #report.mustHave >= 10 then
			break
		end
	end

	-- Estadísticas clave del perfil: lo que suma tu equipo y lo que suma la media.
	report.keyStats = {}
	for _, key in ipairs(profile.key) do
		report.keyStats[#report.keyStats + 1] = { key = key, have = keyHave[key] or 0, average = keyAverage[key] or 0 }
	end
	return report
end

--------------------------------------------------------------------------------
-- Lo que se consulta afuera (Questie y el juego); en las pruebas se reemplaza.
--------------------------------------------------------------------------------

local SKILL_NAMES = { [164] = "Herrería", [165] = "Peletería", [197] = "Sastrería", [202] = "Ingeniería",
	[171] = "Alquimia", [333] = "Encantamiento", [186] = "Minería", [182] = "Herboristería",
	[393] = "Desuello", [185] = "Cocina", [129] = "Primeros auxilios", [356] = "Pesca" }
S.SKILL_NAMES = SKILL_NAMES

S.Env = {}
local Env = S.Env

function Env.QuestOk(questId, ctx)
	local D = QR.Data
	if not D.Quest(questId, "name") then
		return false
	end
	if D.IsCompleted(questId) then
		return false
	end
	local races = D.Quest(questId, "requiredRaces")
	if races and races > 0 and ctx.raceBit and not HasBit(races, ctx.raceBit) then
		return false
	end
	local classes = D.Quest(questId, "requiredClasses")
	if classes and classes > 0 and not HasBit(classes, ctx.classBit) then
		return false
	end
	return (D.Quest(questId, "requiredLevel") or 0) <= ctx.level
end

function Env.NpcFriendly(npcId)
	local Npc = LibQuestieDB and LibQuestieDB.Npc
	if not Npc then
		return true
	end
	local friendly = Npc.Get(npcId, "friendlyToFaction")
	if not friendly or friendly == "" or friendly == "AH" then
		return true
	end
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	return (faction == "Alliance" and friendly == "A") or (faction == "Horde" and friendly == "H")
end

local npcInstance = {}
function Env.NpcInstance(npcId)
	if npcInstance[npcId] ~= nil then
		return npcInstance[npcId]
	end
	local Npc = LibQuestieDB and LibQuestieDB.Npc
	local zone = Npc and Npc.Get(npcId, "zoneID")
	npcInstance[npcId] = (zone and RAID_AREAS[zone]) or 0
	return npcInstance[npcId]
end

function Env.ProfessionSkill(skillId)
	if GetProfessions and GetProfessionInfo then
		local ok, a, b, c, d, e = pcall(GetProfessions)
		if ok then
			for _, index in ipairs({ a, b, c, d, e }) do
				local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
				if skillLine == skillId then
					return rank
				end
			end
		end
	end
	-- Classic: se busca por nombre en la lista de habilidades.
	if GetNumSkillLines and GetSkillLineInfo and SKILL_NAMES[skillId] then
		for index = 1, GetNumSkillLines() do
			local name, isHeader, _, rank = GetSkillLineInfo(index)
			if not isHeader and name == SKILL_NAMES[skillId] then
				return rank
			end
		end
	end
	return nil
end

function Env.ItemCount(itemId)
	if not GetItemCount then
		return 0
	end
	local ok, count = pcall(GetItemCount, itemId, true)
	return ok and count or 0
end

--------------------------------------------------------------------------------
-- Estado del jugador
--------------------------------------------------------------------------------

--- Contexto actual: rama detectada (o la elegida), rol elegido y nivel.
function S.Current(settings)
	local classFile = QR.Data.PlayerClass()
	local spec = S.DetectSpec(classFile)
	if not spec then
		return nil
	end
	local tree = settings.tree or spec.index
	local role = settings.role
	if not role then
		role = S.DefaultRole(classFile, tree)
	end
	local ctx = S.Context(classFile, QR.Data.PlayerLevel(), tree, role)
	ctx.spec = spec
	return ctx
end

S.STAT_NAMES = {
	S = "Fuerza", A = "Agilidad", T = "Aguante", I = "Intelecto", P = "Espíritu", R = "Armadura",
	B = "Valor de bloqueo", D = "Daño por segundo del arma", ap = "Poder de ataque", rap = "Poder de ataque a distancia",
	crit = "Golpe crítico (%)", hit = "Índice de golpe (%)", sp = "Daño con hechizos", heal = "Sanación",
	scrit = "Crítico con hechizos (%)", shit = "Golpe con hechizos (%)", mp5 = "Maná cada 5 s", hp5 = "Salud cada 5 s",
	def = "Defensa", ws = "Habilidad con armas", dodge = "Esquivar (%)", parry = "Parar (%)", block = "Bloquear (%)",
	hp = "Salud", spSh = "Daño de Sombras", spFi = "Daño de Fuego", spFr = "Daño de Escarcha", spAr = "Daño Arcano",
	spNa = "Daño de Naturaleza", spHo = "Daño Sagrado", pen = "Penetración de hechizos",
}

--------------------------------------------------------------------------------
-- Textos
--------------------------------------------------------------------------------

local function NpcField(npcId, key)
	local Npc = LibQuestieDB and LibQuestieDB.Npc
	if not Npc then
		return nil
	end
	local ok, value = pcall(Npc.Get, npcId, key)
	return ok and value or nil
end

function S.NpcName(npcId)
	return NpcField(npcId, "name") or ("PNJ " .. npcId)
end

local function Chance(chance)
	if chance >= 10 then
		return format("%d%%", math.floor(chance + 0.5))
	elseif chance >= 1 then
		return format("%.1f%%", chance)
	end
	return format("%.2f%%", chance)
end
S.ChanceText = Chance

--- Cómo se consigue: texto corto y lugar (zona o mazmorra), para la lista y el tooltip.
function S.SourceText(source, item)
	local D = QR.Data
	if source.kind == "quest" then
		local label = (source.raid and "Misión de banda") or (source.dungeon and "Misión de mazmorra") or "Misión"
		return format("%s: %s", label, D.QuestName(source.id)), D.ZoneName(D.QuestZone(source.id))
	elseif source.kind == "vendor" then
		local note = ""
		if source.pvp then
			note = " (reputación de campo de batalla)"
		elseif source.repFaction then
			note = " (pide reputación con " .. D.FactionName(source.repFaction) .. ")"
		end
		return "Vendedor: " .. S.NpcName(source.id) .. note, D.ZoneName(NpcField(source.id, "zoneID"))
	elseif source.kind == "drop" then
		local place = S.InstanceName(source.instance) or D.ZoneName(NpcField(source.npc, "zoneID"))
		return format("%s (%s)", S.NpcName(source.npc), Chance(source.chance)), place
	elseif source.kind == "craft" then
		local name = SKILL_NAMES[source.skill] or "Profesión"
		local note
		if source.have and source.have >= source.rank then
			note = " (ya podés)"
		elseif source.have then
			note = format(" (tenés %d)", source.have)
		elseif item and item.bind ~= 1 then
			note = " (pedíselo a un artesano o buscalo en la subasta)"
		else
			note = " (hace falta la profesión)"
		end
		return format("%s %d%s", name, source.rank, note), ""
	elseif source.kind == "world" then
		return source.auction and "Botín del mundo: buscalo en la subasta" or "Botín del mundo (poco común)", ""
	elseif source.kind == "chest" then
		return "Cofre", S.InstanceName(source.instance) or ""
	elseif source.kind == "container" then
		return "Dentro de: " .. D.ItemName(source.item), ""
	end
	return "", ""
end

--- Zona para abrir en el mapa al hacer clic en una fuente.
function S.SourceZone(source)
	local D = QR.Data
	if source.kind == "quest" then
		return D.QuestZone(source.id)
	elseif source.kind == "vendor" then
		return NpcField(source.id, "zoneID")
	elseif source.kind == "drop" then
		return NpcField(source.npc, "zoneID")
	end
	return nil
end

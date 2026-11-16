-- Puntaje e íconos de relevancia en la barra lateral de seguimiento de Questie,
-- y orden por relevancia.

local _, QR = ...

local Tracker = {}
QR.Tracker = Tracker

QR.badges = {} -- questId -> texto que va delante del título en el seguimiento
QR.scores = {} -- questId -> puntaje, para ordenar

local function ScoreHex(score)
	local r, g, b = QR.ScoreColor(score)
	return format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

--- Tamaño de los íconos en el seguimiento: acompaña la letra de los títulos de
--- Questie (10 por defecto, que da íconos de 18).
function Tracker.IconSize()
	local profile = Questie and Questie.db and Questie.db.profile
	local fontSize = profile and tonumber(profile.trackerFontSizeQuest) or 10
	return math.max(14, math.min(28, fontSize + 8))
end

--- Texto corto para el seguimiento: puntaje, íconos y la mejora de equipo.
function Tracker.BadgeText(result)
	local parts = { format("|cff%s%d|r", ScoreHex(result.score), result.score) }
	local icons = QR.TagIcons(result, Tracker.IconSize(), true)
	if icons ~= "" then
		parts[#parts + 1] = icons
	end
	if result.tags.equipo and result.gearGain then
		parts[#parts + 1] = format("|cff20ff20+%d|r", result.gearGain)
	end
	return table.concat(parts, " ")
end

function Tracker.SetResults(results)
	local badges, scores = {}, {}
	for _, result in ipairs(results) do
		badges[result.id] = Tracker.BadgeText(result)
		scores[result.id] = result.score
	end
	local changed = false
	for questId, badge in pairs(badges) do
		if QR.badges[questId] ~= badge then changed = true break end
	end
	if not changed then
		for questId in pairs(QR.badges) do
			if not badges[questId] then changed = true break end
		end
	end
	QR.badges, QR.scores = badges, scores
	return changed
end

local function SortIds(ids, details)
	local sortMode = Questie and Questie.db and Questie.db.profile and Questie.db.profile.trackerSortObjectives
	local byZone = type(sortMode) == "string" and sortMode:find("^byZone") ~= nil
	local position, groupOrder = {}, {}
	for index, questId in ipairs(ids) do
		position[questId] = index
		local group = details and details[questId] and details[questId].zoneName or ""
		if not groupOrder[group] then
			groupOrder[group] = index
		end
	end
	table.sort(ids, function(a, b)
		if byZone then
			-- Agrupado por zona: se respetan los grupos y se ordena adentro de cada uno.
			local groupA = groupOrder[details[a] and details[a].zoneName or ""]
			local groupB = groupOrder[details[b] and details[b].zoneName or ""]
			if groupA ~= groupB then
				return groupA < groupB
			end
		end
		local scoreA, scoreB = QR.scores[a] or -1, QR.scores[b] or -1
		if scoreA ~= scoreB then
			return scoreA > scoreB
		end
		return position[a] < position[b]
	end)
end
Tracker.SortIds = SortIds

function Tracker.Install()
	if Tracker.installed then
		return
	end
	local LineBuilder = QR.Data.Module("LineBuilder")
	local TrackerUtils = QR.Data.Module("TrackerUtils")

	if type(LineBuilder.AddTitle) == "function" then
		local original = LineBuilder.AddTitle
		LineBuilder.AddTitle = function(options, ...)
			if type(options) == "table" and options.clickMode == "quest" and type(options.target) == "table"
				and type(options.text) == "string" then
				local db = QR.DB()
				local badge = db and db.tracker and QR.badges[options.target.Id]
				if badge then
					local text = options.colored and options.text or ("|cFFFFFF00" .. options.text .. "|r")
					options.text = badge .. "  " .. text
					options.colored = true
				end
			end
			return original(options, ...)
		end
		Tracker.hookedTitles = true
	end

	if type(TrackerUtils.GetSortedQuestIds) == "function" then
		local original = TrackerUtils.GetSortedQuestIds
		TrackerUtils.GetSortedQuestIds = function(self, ...)
			local ids, details = original(self, ...)
			local db = QR.DB()
			if db and db.sortTracker and type(ids) == "table" and next(QR.scores) then
				pcall(SortIds, ids, details)
			end
			return ids, details
		end
		Tracker.hookedSort = true
	end
	Tracker.installed = true
end

local pending = false

--- Vuelve a dibujar el seguimiento de Questie. En combate se deja para después.
function Tracker.Refresh()
	local QuestieTracker = QR.Data.Module("QuestieTracker")
	if type(QuestieTracker.Update) ~= "function" or not QuestieTracker.started then
		return
	end
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	pcall(QuestieTracker.Update, QuestieTracker)
end

function Tracker.OnCombatEnded()
	if pending then
		Tracker.Refresh()
	end
end

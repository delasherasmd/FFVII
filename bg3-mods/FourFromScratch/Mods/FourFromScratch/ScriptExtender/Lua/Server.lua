-- Four From Scratch
-- Al empezar la partida (Nautiloide) crea 3 personajes extra en el grupo y
-- abre para cada uno el creador de personajes completo (raza, clase, apariencia...).
-- Todos los controla el mismo jugador.
--
-- ESTADO: sin probar en el juego. Los nombres de las funciones de Osiris que
-- abren el creador NO estan documentados por Script Extender; por eso se prueban
-- varios candidatos en orden y se registra en el log cual funciono.
-- Ver el log en la consola de Script Extender (prefijo [FourFromScratch]).

local MOD = "[FourFromScratch]"
local EXTRA_CHARACTERS = 3
local START_LEVEL = "TUT_Avernus_C" -- Nautiloide

-- Plantilla para los personajes nuevos. Si queda nil se usa la plantilla del
-- personaje del jugador (un "Tav" generico). Se puede reemplazar por la plantilla
-- base de los mercenarios de Withers cuando la extraigamos del juego.
local TEMPLATE_OVERRIDE = nil

-- Funciones candidatas, de la mas completa a la menos completa.
local CC_CANDIDATES = {
    "StartCharacterCreation",   -- creador completo (ideal)
    "StartRespecToTutorial",    -- creador completo usado por otros mods (a verificar)
    "StartRespec",              -- respec de Withers: clase/habilidades, SIN raza
}
local APPEARANCE_CANDIDATES = {
    "StartChangeAppearance",    -- espejo magico: apariencia
}
local PARTY_CANDIDATES = {
    "RegisterAsCompanion",      -- (personaje, jugador)
    "AddPartyFollower",         -- (personaje, jugador)
}

PersistentVars = PersistentVars or {}

local function log(...)
    Ext.Utils.Print(MOD, ...)
end

local function tryOsi(names, ...)
    for _, name in ipairs(names) do
        local fn = Osi[name]
        if fn ~= nil then
            local ok, err = pcall(fn, ...)
            if ok then
                log("OK:", name)
                return name
            end
            log("Fallo", name, err)
        else
            log("No existe:", name)
        end
    end
    return nil
end

local function hostCharacter()
    local host = Osi.GetHostCharacter()
    if host == nil then log("Sin personaje anfitrion") end
    return host
end

-- Cola: el creador solo se puede abrir para un personaje a la vez.
local queue = {}

local function openNext()
    local char = table.remove(queue, 1)
    if char == nil then
        log("Los 4 personajes estan listos.")
        return
    end
    local used = tryOsi(CC_CANDIDATES, char)
    if used == "StartRespec" then
        log("AVISO: solo hay respec de clase, la raza queda bloqueada. Hay que buscar otra funcion.")
    end
    if used == nil then
        tryOsi(APPEARANCE_CANDIDATES, char)
    end
end

-- Al terminar una creacion abrimos la siguiente.
local function onCreationDone(char)
    if PersistentVars.pending and PersistentVars.pending[char] then
        PersistentVars.pending[char] = nil
        openNext()
    end
end

for _, ev in ipairs({"RespecCompleted", "ChangeAppearanceCompleted", "CharacterCreationFinished"}) do
    local ok = pcall(Ext.Osiris.RegisterListener, ev, 1, "after", onCreationDone)
    log(ok and "Escuchando evento" or "Evento no disponible", ev)
end

local function spawnExtra(host)
    local template = TEMPLATE_OVERRIDE or Osi.GetTemplate(host)
    local x, y, z = Osi.GetPosition(host)
    local created = {}
    for i = 1, EXTRA_CHARACTERS do
        local char = Osi.CreateAt(template, x + i, y, z, 0, 1, "")
        if char == nil then
            log("No se pudo crear el personaje", i)
        else
            log("Creado", i, char)
            tryOsi(PARTY_CANDIDATES, char, host)
            if Osi.SetFaction and Osi.GetFaction then
                pcall(Osi.SetFaction, char, Osi.GetFaction(host))
            end
            table.insert(created, char)
        end
    end
    return created
end

local function startParty()
    local host = hostCharacter()
    if host == nil then return end
    local created = spawnExtra(host)
    PersistentVars.created = created
    PersistentVars.pending = {}
    for _, c in ipairs(created) do
        PersistentVars.pending[c] = true
        table.insert(queue, c)
    end
    openNext()
end

Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function(level, isEditor)
    if level ~= START_LEVEL or PersistentVars.done then return end
    PersistentVars.done = true
    log("Inicio de partida detectado:", level)
    startParty()
end)

-- Comandos de consola de Script Extender (escribir en la consola: !ffs_cc ...)
-- !ffs_cc        -> reabre el creador completo para el personaje principal (anfitrion)
-- !ffs_start     -> fuerza el inicio (por si el evento no se disparo)
Ext.RegisterConsoleCommand("ffs_cc", function()
    local host = hostCharacter()
    if host then table.insert(queue, host); openNext() end
end)

Ext.RegisterConsoleCommand("ffs_start", function()
    PersistentVars.done = true
    startParty()
end)

log("Cargado.")

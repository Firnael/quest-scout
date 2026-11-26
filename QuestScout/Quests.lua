-- QuestScout quests: settings, per-character hidden quests, and which quests a pin shows.
local ADDON, ns = ...

local DEFAULTS = {
    -- Advisor
    below = 2,              -- count quests down to playerLevel - below
    above = 4,              -- and up to playerLevel + above
    soon = 2,               -- also count quests unlocked within this many levels (half weight)
    rows = 5,
    -- Pins
    enabled = true,
    badges = true,          -- class / profession / dungeon icon on pins
    showLocked = true,      -- grey pins for quests unlocked within LOCKED_AHEAD levels
    showLowLevel = false,
    pinBelow = 9,           -- low-level: hide quests this many levels below you (3-15)
    pinAbove = 0,           -- hide quests this many levels above you (3-14), 0 = show all
    showNormal = true,
    showClass = true,
    showProfession = true,
    showDungeon = true,
    showRepeatable = true,
    showSeasonal = false,
    showWarEffort = false,
    showOnContinent = true, -- pins on continent and world maps
    pinScale = 100,         -- percent, 50-150
    tomtom = false,         -- waypoint provider: TomTom instead of Blizzard map pins
    debug = false,          -- quest IDs in tooltips
}

local LOCKED_AHEAD = 3
ns.LOCKED_AHEAD = LOCKED_AHEAD

function ns.InitSettings(db)
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    db.hidden = db.hidden or {}
end

---------------------------------------------------------------------------
-- Hidden quests, per character (stored in the account file)
---------------------------------------------------------------------------
local function CharacterKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function HiddenBucket(create)
    local key = CharacterKey()
    local bucket = QuestScoutDB.hidden[key]
    if not bucket and create then
        bucket = {}
        QuestScoutDB.hidden[key] = bucket
    end
    return bucket
end

function ns.IsHidden(id)
    local bucket = HiddenBucket(false)
    return bucket and bucket[id] or false
end

function ns.SetHidden(id, hidden)
    HiddenBucket(true)[id] = hidden or nil
end

function ns.HiddenCount()
    local n = 0
    for _ in pairs(HiddenBucket(false) or {}) do n = n + 1 end
    return n
end

function ns.UnhideAll()
    QuestScoutDB.hidden[CharacterKey()] = nil
end

---------------------------------------------------------------------------
-- Player professions: skillLine -> rank
---------------------------------------------------------------------------
local professions

function ns.ResetProfessions()
    professions = nil
end

local function ProfessionRank(skillLine)
    if not professions then
        professions = {}
        if GetProfessions and GetProfessionInfo then
            for _, index in pairs({ GetProfessions() }) do
                if index then
                    local _, _, rank, _, _, _, line = GetProfessionInfo(index)
                    if line then professions[line] = rank or 0 end
                end
            end
        end
    end
    return professions[skillLine]
end

---------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------
local IsCompleted = C_QuestLog.IsQuestFlaggedCompleted
local IsOnQuest = C_QuestLog.IsOnQuest

local function DoneOrActive(id)
    return id and id ~= 0 and (IsCompleted(id) or IsOnQuest(id))
end

local KIND_NAMES = { dungeon = "donjon/raid", class = "classe", profession = "métier", normal = "normale" }

-- Kinds a quest belongs to; a quest is hidden when any of its kinds is turned off.
local function KindFilter(q, db)
    if q.instance and not db.showDungeon then return "dungeon" end
    if q.class and not db.showClass then return "class" end
    if q.skill and not db.showProfession then return "profession" end
    if not (q.instance or q.class or q.skill) and not db.showNormal then return "normal" end
end

-- Returns state ("open" | "locked" | nil when hidden) and a French reason.
function ns.Visibility(q, playerLevel)
    local db = QuestScoutDB
    if ns.IsHidden(q.id) then return nil, "masquée par toi (Maj-clic)" end

    local kind = KindFilter(q, db)
    if kind then return nil, "type désactivé : " .. KIND_NAMES[kind] end
    if q.repeatable and not db.showRepeatable then return nil, "répétable, masquée" end
    if q.seasonal and not db.showSeasonal then return nil, "saisonnière, masquée" end
    if q.warEffort and not db.showWarEffort then return nil, "effort de guerre d'AQ, masqué" end

    local skillRank
    if q.skill then
        skillRank = ProfessionRank(q.skill[1])
        if not skillRank then return nil, "métier non appris" end
    end

    if not db.showLowLevel and playerLevel - q.level >= db.pinBelow then
        return nil, ("bas niveau (%d niveaux ou plus en dessous de toi)"):format(db.pinBelow)
    end
    if db.pinAbove > 0 and q.level - playerLevel >= db.pinAbove then
        return nil, ("trop haut niveau (%d niveaux ou plus au-dessus de toi)"):format(db.pinAbove)
    end
    if q.maxLevel and q.maxLevel ~= 0 and playerLevel > q.maxLevel then
        return nil, ("niveau max %d dépassé"):format(q.maxLevel)
    end

    if IsCompleted(q.id) then return nil, "déjà faite" end
    if IsOnQuest(q.id) then return nil, "dans ton journal" end
    for _, other in ipairs(q.exclusive or {}) do
        if DoneOrActive(other) then return nil, ("exclusive avec #%d, déjà prise"):format(other) end
    end
    if DoneOrActive(q.next) then return nil, ("suite #%d déjà prise"):format(q.next) end
    if q.parent and q.parent ~= 0 and not IsOnQuest(q.parent) then
        return nil, ("quête parente #%d pas en cours"):format(q.parent)
    end
    if q.preSingle and #q.preSingle > 0 then
        local ok = false
        for _, id in ipairs(q.preSingle) do
            if IsCompleted(id) then ok = true break end
        end
        if not ok then return nil, ("prérequis manquant (une parmi #%s)"):format(table.concat(q.preSingle, ", #")) end
    end
    for _, id in ipairs(q.preGroup or {}) do
        if not IsCompleted(id) then return nil, ("prérequis manquant #%d"):format(id) end
    end

    local lockedBy
    if q.reqLevel > playerLevel then
        lockedBy = ("niv. %d requis"):format(q.reqLevel)
        if q.reqLevel - playerLevel > LOCKED_AHEAD then
            return nil, ("pas avant le niveau %d"):format(q.reqLevel)
        end
    elseif q.skill and skillRank < (q.skill[2] or 0) then
        lockedBy = ("compétence %d requise"):format(q.skill[2])
    end
    if lockedBy then
        if not db.showLocked then return nil, lockedBy .. " (bloquées masquées)" end
        return "locked", lockedBy
    end
    return "open", "visible"
end

function ns.QuestTitle(q)
    return C_QuestLog.GetTitleForQuestID(q.id) or q.name or ("#" .. q.id)
end

-- Classic difficulty colours relative to the player.
local function GrayLevel(playerLevel)
    if playerLevel <= 5 then return 0 end
    if playerLevel <= 39 then return playerLevel - 5 - math.floor(playerLevel / 10) end
    return playerLevel - 1 - math.floor(playerLevel / 5)
end

function ns.DifficultyColor(questLevel, playerLevel)
    local diff = questLevel - playerLevel
    if diff >= 5 then return 1, 0.1, 0.1 end      -- red
    if diff >= 3 then return 1, 0.5, 0.25 end     -- orange
    if diff >= -2 then return 1, 1, 0 end         -- yellow
    if questLevel > GrayLevel(playerLevel) then return 0.25, 0.75, 0.25 end -- green
    return 0.6, 0.6, 0.6                          -- grey
end

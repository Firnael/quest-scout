-- QuestScout data: static index of quests, map pins and dungeons, built once per session from QuestieDB.
local ADDON, ns = ...

local floor = math.floor

function ns.Print(msg)
    print("|cff33ccffQuest Scout|r " .. msg)
end

-- Race masks can exceed 32 bits (Skyborne), so no bit.band.
local function HasBit(mask, bitValue)
    return floor(mask / bitValue) % 2 == 1
end

---------------------------------------------------------------------------
-- Zones: AreaID (QuestieDB) -> UiMapID (client)
---------------------------------------------------------------------------
local areaToUiMap, subZoneToParent

local function Decode(value)
    if type(value) == "table" then return value end
    if type(value) ~= "string" then return {} end
    local fn = loadstring(value)
    local ok, result = pcall(fn)
    return ok and type(result) == "table" and result or {}
end

local function LoadZones(private)
    areaToUiMap = Decode(private.areaIdToUiMapId)
    for k, v in pairs(Decode(private.areaIdToUiMapIdOverride)) do areaToUiMap[k] = v end
    subZoneToParent = Decode(private.subZoneToParentZone)
    for k, v in pairs(Decode(private.subZoneToParentZoneOverride)) do subZoneToParent[k] = v end
end

function ns.UiMapForArea(areaId)
    local uiMap = areaToUiMap[areaId]
    if (not uiMap or uiMap == 0) and subZoneToParent[areaId] then
        uiMap = areaToUiMap[subZoneToParent[areaId]]
    end
    if uiMap and uiMap ~= 0 then return uiMap end
end

---------------------------------------------------------------------------
-- Quest filters that never change during a session
---------------------------------------------------------------------------
local blacklist = {}

local function LoadQuestieBlacklist()
    -- Questie keeps its list of removed/duplicate quests outside QuestieDB.
    if not QuestieLoader then return end
    local ok, result = pcall(function()
        return QuestieLoader:ImportModule("QuestieQuestBlacklist"):Load()
    end)
    if ok and type(result) == "table" then
        for id, v in pairs(result) do
            if v then blacklist[id] = true end
        end
    end
end

---------------------------------------------------------------------------
-- Index
-- ns.questById[id] = quest record (see BuildIndex)
-- ns.quests       = quests the advisor ranks: plain, one-shot, outside dungeons
-- ns.pinsByMap[uiMap] = { pin, ... }   pin = { uiMap, x, y, points, starters, quests }
-- ns.pinsByQuest[id]  = { pin, ... }
-- ns.dungeons     = { {name, uiMap, minLevel, maxLevel, medianLevel, questCount}, ... }
---------------------------------------------------------------------------
ns.questById = {}
ns.quests = {}
ns.pinsByMap = {}
ns.pinsByQuest = {}
ns.dungeons = {}
ns.ready = false

local QUEST_KEYS = {
    "name", "startedBy", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses",
    "exclusiveTo", "requiredSkill", "nextQuestInChain", "specialFlags", "requiredMaxLevel",
    "zoneOrSort", "preQuestGroup", "preQuestSingle", "parentQuest",
}

-- Spawns of one starter closer than this (fraction of the map) share a pin.
local CLUSTER_RADIUS = 0.06
-- Pins of different starters closer than this stack into one.
local STACK_RADIUS = 0.012

-- Single-linkage clusters of points ({x, y} in 0-1).
local function Cluster(points, radius)
    local n = #points
    local parent = {}
    for i = 1, n do parent[i] = i end
    local function find(i)
        while parent[i] ~= i do
            parent[i] = parent[parent[i]]
            i = parent[i]
        end
        return i
    end
    local r2 = radius * radius
    for i = 1, n do
        for j = i + 1, n do
            local dx, dy = points[i].x - points[j].x, points[i].y - points[j].y
            if dx * dx + dy * dy <= r2 then parent[find(i)] = find(j) end
        end
    end
    local groups, byRoot = {}, {}
    for i = 1, n do
        local root = find(i)
        local g = byRoot[root]
        if not g then
            g = {}
            byRoot[root] = g
            groups[#groups + 1] = g
        end
        g[#g + 1] = points[i]
    end
    return groups
end

-- The spawn closest to the cluster's centre anchors its pin.
local function Anchor(points)
    local cx, cy = 0, 0
    for _, p in ipairs(points) do cx, cy = cx + p.x, cy + p.y end
    cx, cy = cx / #points, cy / #points
    local best, bestD
    for _, p in ipairs(points) do
        local d = (p.x - cx) ^ 2 + (p.y - cy) ^ 2
        if not bestD or d < bestD then best, bestD = p, d end
    end
    return best
end

-- Spawn groups of one starter (NPC or object), computed once and shared by its quests.
-- group = { uiMap, x, y, points (only when several), name }
local starterGroups = {}

local function StarterGroups(kind, starterId, db)
    local key = kind .. starterId
    local groups = starterGroups[key]
    if groups then return groups end
    groups = {}
    starterGroups[key] = groups

    local spawns = db.spawns(starterId)
    if not spawns then return groups end
    local name = db.name(starterId)
    local byMap = {}
    for areaId, list in pairs(spawns) do
        local uiMap = ns.UiMapForArea(areaId)
        if uiMap then
            for _, p in ipairs(list) do
                if p[1] and p[2] and p[1] >= 0 and p[2] >= 0 then
                    byMap[uiMap] = byMap[uiMap] or {}
                    table.insert(byMap[uiMap], { x = p[1] / 100, y = p[2] / 100 })
                end
            end
        end
    end
    for uiMap, points in pairs(byMap) do
        for _, cluster in ipairs(Cluster(points, CLUSTER_RADIUS)) do
            local a = Anchor(cluster)
            groups[#groups + 1] = {
                uiMap = uiMap, x = a.x, y = a.y, name = name,
                points = #cluster > 1 and cluster or nil,
                quests = {},
            }
        end
    end
    return groups
end

-- Groups that sit on (almost) the same spot become one pin.
local function BuildPins()
    local byMap = {}
    for _, groups in pairs(starterGroups) do
        for _, g in ipairs(groups) do
            if #g.quests > 0 then
                byMap[g.uiMap] = byMap[g.uiMap] or {}
                table.insert(byMap[g.uiMap], g)
            end
        end
    end
    local r2 = STACK_RADIUS * STACK_RADIUS
    for uiMap, groups in pairs(byMap) do
        local pins = {}
        for _, g in ipairs(groups) do
            local target
            for _, pin in ipairs(pins) do
                if (pin.x - g.x) ^ 2 + (pin.y - g.y) ^ 2 <= r2 then
                    target = pin
                    break
                end
            end
            if not target then
                target = { uiMap = uiMap, x = g.x, y = g.y, starters = {}, quests = {}, seen = {} }
                pins[#pins + 1] = target
            end
            target.starters[#target.starters + 1] = g.name
            if g.points and not target.points then target.points = g.points end
            for _, q in ipairs(g.quests) do
                if not target.seen[q.id] then
                    target.seen[q.id] = true
                    target.quests[#target.quests + 1] = q
                    ns.pinsByQuest[q.id] = ns.pinsByQuest[q.id] or {}
                    table.insert(ns.pinsByQuest[q.id], target)
                end
            end
        end
        for _, pin in ipairs(pins) do pin.seen = nil end
        ns.pinsByMap[uiMap] = pins
    end
    starterGroups = nil
end

local function Median(list)
    table.sort(list)
    return list[floor((#list + 1) / 2)]
end

-- Quest sorts (negative zoneOrSort, names from QuestieDB's quest enum): holidays and the AQ
-- war effort. Extras.lua lists the quests QuestieDB files elsewhere.
local HOLIDAY_SORTS = {
    [-21] = true,  -- Hallow's End
    [-22] = true,  -- Seasonal
    [-41] = true,  -- Day of the Dead
    [-364] = true, -- Darkmoon Faire
    [-366] = true, -- Lunar Festival
    [-369] = true, -- Midsummer
    [-370] = true, -- Brewfest
    [-374] = true, -- Noblegarden
    [-375] = true, -- Pilgrim's Bounty
    [-376] = true, -- Love is in the Air
    [-378] = true, -- Children's Week
    [-402] = true, -- Harvest Festival
    [-404] = true, -- Winter Veil
}
local SORT_AQ_WAR_EFFORT = -365

local function BuildIndex()
    local zoneData = LibQuestieDB.Support.Get("ZoneDB") or {}
    LoadZones(zoneData.private or {})
    LoadQuestieBlacklist()

    local xpSupport = LibQuestieDB.Support.Get("QuestXP")
    local xpDB = xpSupport and xpSupport.db or {}
    local extras = ns.Extras or {}
    local seasonal, instance, warEffort = extras.seasonal or {}, extras.instance or {}, extras.warEffort or {}

    local enum = LibQuestieDB.Enum
    local raceBit = enum.raceMaskById[select(3, UnitRace("player"))]
    local classBit = enum.classKeys[select(2, UnitClass("player"))]

    -- Dungeon area IDs -> dungeon record; quests point at a dungeon through zoneOrSort.
    local dungeonByArea, dungeonLevels = {}, {}
    for areaId, d in pairs(Decode(zoneData.private and zoneData.private.dungeons)) do
        local rec = { areaId = areaId, englishName = d[1], uiMap = ns.UiMapForArea(d[3]) }
        dungeonByArea[areaId] = rec
        for _, alt in ipairs(d[2] or {}) do dungeonByArea[alt] = rec end
        dungeonLevels[rec] = {}
    end

    local QuestDB, NpcDB, ObjectDB = LibQuestieDB.Quest, LibQuestieDB.Npc, LibQuestieDB.Object
    for i, id in ipairs(QuestDB.GetAllIds()) do
        local v = QuestDB.GetAll(id, QUEST_KEYS)
        if v then
            local name, startedBy, reqLevel, level, races, classes,
                exclusive, skill, nextQ, specialFlags, maxLevel, zoneOrSort,
                preGroup, preSingle, parent = unpack(v, 1, v.n)
            local qLevel = level > 0 and level or reqLevel

            -- Dungeon levels use every quest, whatever the faction.
            local dungeon = zoneOrSort > 0 and dungeonByArea[zoneOrSort]
            if dungeon and qLevel > 0 then
                local list = dungeonLevels[dungeon]
                list[#list + 1] = qLevel
            end

            local forPlayer = qLevel > 0
                and not blacklist[id]
                and (not raceBit or races == 0 or HasBit(races, raceBit))
                and (not classBit or classes == 0 or HasBit(classes, classBit))
                and startedBy and (startedBy[1] or startedBy[2])

            if forPlayer then
                local xp = xpDB[id]
                local q = {
                    id = id, name = name, level = qLevel, reqLevel = reqLevel, maxLevel = maxLevel,
                    xp = (xp and xp[2] or 0), exclusive = exclusive, next = nextQ, parent = parent,
                    preGroup = preGroup, preSingle = preSingle,
                    class = classes ~= 0,
                    skill = skill, -- { skillLineId, value } or nil
                    repeatable = specialFlags ~= 0 and HasBit(specialFlags, 1),
                    seasonal = HOLIDAY_SORTS[zoneOrSort] or seasonal[id] or false,
                    warEffort = zoneOrSort == SORT_AQ_WAR_EFFORT or warEffort[id] or false,
                    instance = instance[id] or dungeon and true or false,
                }
                ns.questById[id] = q

                local first
                for _, npcId in ipairs(startedBy[1] or {}) do
                    for _, g in ipairs(StarterGroups("n", npcId, NpcDB)) do
                        g.quests[#g.quests + 1] = q
                        first = first or g
                    end
                end
                for _, objId in ipairs(startedBy[2] or {}) do
                    for _, g in ipairs(StarterGroups("o", objId, ObjectDB)) do
                        g.quests[#g.quests + 1] = q
                        first = first or g
                    end
                end

                -- The advisor ranks plain one-shot quests that start on a known map.
                if first and not (q.skill or q.repeatable or q.seasonal or q.warEffort or q.instance) then
                    q.uiMap, q.x, q.y = first.uiMap, first.x, first.y
                    ns.quests[#ns.quests + 1] = q
                end
            end
        end
        if i % 150 == 0 then coroutine.yield() end
    end

    BuildPins()

    for rec, levels in pairs(dungeonLevels) do
        if #levels >= 2 and rec.uiMap then
            table.sort(levels)
            local areaInfo = C_Map.GetAreaInfo and C_Map.GetAreaInfo(rec.areaId)
            ns.dungeons[#ns.dungeons + 1] = {
                name = areaInfo or rec.englishName,
                uiMap = rec.uiMap,
                minLevel = levels[1],
                maxLevel = levels[#levels],
                medianLevel = Median(levels),
                questCount = #levels,
            }
        end
    end

    ns.ready = true
end

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------
ns.onReady = {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function StartBuild()
    local co = coroutine.create(BuildIndex)
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local ok, err = coroutine.resume(co)
        if not ok then
            ticker:Cancel()
            ns.Print("erreur à l'indexation : " .. tostring(err))
        elseif coroutine.status(co) == "dead" then
            ticker:Cancel()
            for _, fn in ipairs(ns.onReady) do fn() end
        end
    end)
end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        QuestScoutDB = QuestScoutDB or {}
        ns.InitSettings(QuestScoutDB)
    elseif event == "PLAYER_LOGIN" then
        if not LibQuestieDB then
            ns.Print("QuestieDB introuvable, addon inactif.")
            return
        end
        local ok, msg = LibQuestieDB.RequireContract(4)
        if not ok then
            ns.Print(msg)
            return
        end
        if LibQuestieDB.l10n and LibQuestieDB.l10n.currentLocale ~= GetLocale() then
            pcall(LibQuestieDB.l10n.SetLocale, GetLocale())
        end
        StartBuild()
    end
end)

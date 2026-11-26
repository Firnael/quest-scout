-- QuestScout advisor: ranks zones by the quests left for the player's level.
local ADDON, ns = ...

local floor, min = math.floor, math.min

-- Settings (below, above, soon, rows) live in Quests.lua.

-- Tunable weights, kept in one place so the ranking stays explainable.
local SOON_WEIGHT = 0.5
local HUB_RADIUS = 0.07       -- fraction of the map; starters closer than this share a hub
local DENSITY_STEP = 0.1      -- +10% per extra quest per hub
local DENSITY_CAP = 5
local DUNGEON_BONUS = 1.1
local DUNGEON_BELOW, DUNGEON_ABOVE = 3, 5
local MIN_QUESTS = 3

---------------------------------------------------------------------------
-- XP: Classic quest XP scaling (same formula as Questie's QuestXP)
---------------------------------------------------------------------------
local function AdjustedXP(xp, questLevel, playerLevel)
    if xp <= 0 then return 0 end
    local mult = 2 * (questLevel - playerLevel) + 20
    if mult < 1 then mult = 1 elseif mult > 10 then mult = 10 end
    return floor(xp * mult / 10)
end

---------------------------------------------------------------------------
-- Player state
---------------------------------------------------------------------------
local IsCompleted = C_QuestLog.IsQuestFlaggedCompleted
local IsOnQuest = C_QuestLog.IsOnQuest

local function DoneOrActive(id)
    return id ~= 0 and (IsCompleted(id) or IsOnQuest(id))
end

local function StillAvailable(q, playerLevel)
    if DoneOrActive(q.id) or DoneOrActive(q.next) then return false end
    if q.maxLevel ~= 0 and playerLevel > q.maxLevel then return false end
    if q.exclusive then
        for _, other in ipairs(q.exclusive) do
            if DoneOrActive(other) then return false end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Static zone level range: 15th–85th percentile of every eligible quest
---------------------------------------------------------------------------
local zoneRange

local function ZoneRanges()
    if zoneRange then return zoneRange end
    local levels = {}
    for _, q in ipairs(ns.quests) do
        levels[q.uiMap] = levels[q.uiMap] or {}
        table.insert(levels[q.uiMap], q.level)
    end
    zoneRange = {}
    for uiMap, list in pairs(levels) do
        table.sort(list)
        local lo = list[floor(#list * 0.15) + 1]
        local hi = list[floor(#list * 0.85) + 1] or list[#list]
        zoneRange[uiMap] = { lo, hi }
    end
    return zoneRange
end

---------------------------------------------------------------------------
-- Hubs: single-linkage clustering of quest starters
---------------------------------------------------------------------------
local function CountHubs(points)
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
    local r2 = HUB_RADIUS * HUB_RADIUS
    for i = 1, n do
        for j = i + 1, n do
            local dx, dy = points[i].x - points[j].x, points[i].y - points[j].y
            if dx * dx + dy * dy <= r2 then
                parent[find(i)] = find(j)
            end
        end
    end
    local roots = {}
    for i = 1, n do roots[find(i)] = true end
    local hubs = 0
    for _ in pairs(roots) do hubs = hubs + 1 end
    return hubs
end

---------------------------------------------------------------------------
-- Ranking
---------------------------------------------------------------------------
-- Returns a list sorted by score:
-- { uiMap, name, range = {lo, hi}, open, soon, xp, hubs, perHub, quests, dungeons, score }
function ns.RankZones(playerLevel)
    local db = QuestScoutDB
    local lo, hi = playerLevel - db.below, playerLevel + db.above
    local zones = {}

    for _, q in ipairs(ns.quests) do
        if q.level >= lo and q.level <= hi and q.reqLevel <= playerLevel + db.soon
            and StillAvailable(q, playerLevel) then
            local z = zones[q.uiMap]
            if not z then
                z = { uiMap = q.uiMap, open = 0, soon = 0, xp = 0, quests = {}, dungeons = {} }
                zones[q.uiMap] = z
            end
            local xp = AdjustedXP(q.xp, q.level, playerLevel)
            if q.reqLevel <= playerLevel then
                z.open = z.open + 1
                z.xp = z.xp + xp
            else
                z.soon = z.soon + 1
                z.xp = z.xp + xp * SOON_WEIGHT
            end
            z.quests[#z.quests + 1] = q
        end
    end

    for _, d in ipairs(ns.dungeons) do
        local z = zones[d.uiMap]
        if z and d.medianLevel >= playerLevel - DUNGEON_BELOW and d.medianLevel <= playerLevel + DUNGEON_ABOVE then
            z.dungeons[#z.dungeons + 1] = d
        end
    end

    local ranges = ZoneRanges()
    local list = {}
    for uiMap, z in pairs(zones) do
        local total = z.open + z.soon
        if total >= MIN_QUESTS then
            local info = C_Map.GetMapInfo(uiMap)
            z.name = info and info.name or ("#" .. uiMap)
            z.range = ranges[uiMap]
            z.hubs = CountHubs(z.quests)
            z.perHub = total / z.hubs
            local density = 1 + DENSITY_STEP * min(z.perHub - 1, DENSITY_CAP)
            z.score = z.xp * density * (#z.dungeons > 0 and DUNGEON_BONUS or 1)
            list[#list + 1] = z
        end
    end
    table.sort(list, function(a, b) return a.score > b.score end)
    return list
end

---------------------------------------------------------------------------
-- Plain-language verdict
---------------------------------------------------------------------------
local function JoinNames(list, n)
    local names = {}
    for i = 1, min(n, #list) do names[i] = list[i].name end
    if #names <= 1 then return names[1] or "" end
    return table.concat(names, ", ", 1, #names - 1) .. " ou " .. names[#names]
end

function ns.Verdict(list, playerLevel)
    if #list == 0 then
        return ("Niveau %d : aucune zone avec assez de quêtes dans ta plage."):format(playerLevel)
    end
    local top, second = list[1], list[2]
    local text = ("Niveau %d : tu as le choix entre %s."):format(playerLevel, JoinNames(list, 3))
    if not second then return text end

    local reasons = {}
    local topTotal, secondTotal = top.open + top.soon, second.open + second.soon
    if topTotal > secondTotal then
        reasons[#reasons + 1] = ("plus de quêtes (%d contre %d)"):format(topTotal, secondTotal)
    end
    if top.perHub >= second.perHub + 0.5 then
        reasons[#reasons + 1] = ("plus dense (%d hubs)"):format(top.hubs)
    end
    if #top.dungeons > 0 and #second.dungeons == 0 then
        reasons[#reasons + 1] = "un donjon à ton niveau (" .. top.dungeons[1].name .. ")"
    end
    if #reasons == 0 then reasons[1] = "le plus d'XP à prendre" end
    return text .. (" %s est le meilleur choix : %s."):format(top.name, table.concat(reasons, ", "))
end

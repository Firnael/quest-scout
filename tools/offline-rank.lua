-- Offline run of QuestScout Data + Advisor against QuestieDB Forever (source mode).
-- Usage (cwd = QuestieDB clone): luajit run.lua <addonDir> <level> [raceId classFile faction dungeons]
local addonDir, level = arg[1], tonumber(arg[2] or 24)
local raceId, classFile, faction = tonumber(arg[3] or 4), arg[4] or "DRUID", arg[5] or "Alliance"

local client = dofile("emulator/client.lua")
local emulator = dofile("emulator/metadata.lua")
client.install({ expansion = "Forever", faction = faction, classFile = classFile, raceId = raceId, level = level })
local t0 = os.clock()
emulator.loadAddon("QuestieDB.toc", "QuestieDB")
io.stderr:write(("QuestieDB loaded in %.1fs\n"):format(os.clock() - t0))

-- Client stubs used by QuestScout
local scripts = {}
_G.CreateFrame = function()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript(_, fn) scripts[#scripts + 1] = { frame = f, fn = fn } end
  return f
end
_G.C_Timer = {
  After = function(_, fn) fn() end,
  NewTicker = function(_, fn)
    local t = { cancelled = false }
    function t:Cancel() self.cancelled = true end
    while not t.cancelled do fn() end
    return t
  end,
}
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, IsOnQuest = function() return false end }

-- Zone names: uiMap -> areaId -> enum name
local zd = LibQuestieDB.Support.Get("ZoneDB")
local uiToArea = loadstring(zd.private.uiMapIdToAreaId)()
for k, v in pairs(loadstring(zd.private.uiMapIdToAreaIdOverride or "return {}")()) do uiToArea[k] = v end
local areaName = {}
for name, id in pairs(LibQuestieDB.Enum.zoneIDs or zd.zoneIDs) do areaName[id] = name end
_G.C_Map = {
  GetMapInfo = function(ui) return { name = areaName[uiToArea[ui]] or ("ui" .. ui) } end,
  GetAreaInfo = function(a) return areaName[a] end,
}
_G.print = function(...) io.stderr:write(table.concat({ ... }, " ") .. "\n") end

local ns = {}
for _, f in ipairs({ "Data.lua", "Advisor.lua" }) do
  assert(loadfile(addonDir .. "/" .. f))("QuestScout", ns)
end
for _, s in ipairs(scripts) do s.fn(s.frame, "ADDON_LOADED", "QuestScout") end
t0 = os.clock()
for _, s in ipairs(scripts) do s.fn(s.frame, "PLAYER_LOGIN") end
io.stderr:write(("index: %d quests, %d dungeons in %.1fs\n"):format(#ns.quests, #ns.dungeons, os.clock() - t0))

local list = ns.RankZones(level)
for i = 1, math.min(8, #list) do
  local z = list[i]
  local d = z.dungeons[1]
  print(("%d. %-22s (%s) open=%d soon=%d hubs=%d perHub=%.1f xp=%d score=%d%s"):format(
    i, z.name, z.range and (z.range[1] .. "-" .. z.range[2]) or "?", z.open, z.soon, z.hubs, z.perHub, z.xp, z.score,
    d and (" | donjon " .. d.name .. " " .. d.minLevel .. "-" .. d.maxLevel .. " med " .. d.medianLevel) or ""))
end
print(ns.Verdict(list, level))
if arg[6] == "dungeons" then
  table.sort(ns.dungeons, function(a, b) return a.medianLevel < b.medianLevel end)
  for _, d in ipairs(ns.dungeons) do
    print(d.name, d.minLevel, d.medianLevel, d.maxLevel, d.questCount, areaName[uiToArea[d.uiMap]])
  end
end

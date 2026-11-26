-- QuestScout pins: quest starts on the world map, as plain frames on the map canvas.
--
-- Not MapCanvas pins: in Gamepad UI, Blizzard's map scans every MapCanvas pin each
-- frame from its own update (GetCenter, then OnMouseEnter / OnClick on the pins under
-- the gamepad cursor). An addon pin in that scan taints it, and closing the map then
-- hits a blocked action (same bug and fix in Forever Quest Pins). Plain frames stay out
-- of the scan; hover under the gamepad cursor is polled here instead.
local ADDON, ns = ...

local PIN = "QuestScoutPinTemplate"
local DOT = "QuestScoutDotTemplate"
local BASE_SIZE = 18
local ZOOM_GROWTH = 0.4   -- pins grow up to 1.4x fully zoomed in, like Blizzard's area POIs
local GAMEPAD_REACH = 12  -- about screen pixels, as Blizzard's own gamepad pin pick
local POLL_INTERVAL = 0.05

local function PinSize()
    return BASE_SIZE * (QuestScoutDB.pinScale or 100) / 100
end

-- Gamepad UI: the console-style interface, with the soft cursor driven by the stick.
local function IsGamepadUI()
    local util = InputUtil
    return util ~= nil and util.IsGamepadUIEnabled ~= nil and util.IsGamepadUIEnabled() == true
end

---------------------------------------------------------------------------
-- Projection: a zone's 0-1 coordinates onto the viewed map
---------------------------------------------------------------------------
local rects = {} -- [viewed][child] = { minX, maxX, minY, maxY } | false

local function Rect(child, viewed)
    rects[viewed] = rects[viewed] or {}
    local r = rects[viewed][child]
    if r == nil then
        r = false
        if C_Map.GetMapRectOnMap then
            local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, child, viewed)
            if ok and minX and not (minX == 0 and maxX == 0 and minY == 0 and maxY == 0) then
                r = { minX, maxX, minY, maxY }
            end
        end
        rects[viewed][child] = r
    end
    return r
end

local function Project(r, x, y)
    if not r then return x, y end
    return r[1] + (r[2] - r[1]) * x, r[3] + (r[4] - r[3]) * y
end

local mapInfo = {}
local function MapInfo(uiMap)
    local info = mapInfo[uiMap]
    if info == nil then
        info = C_Map.GetMapInfo(uiMap) or false
        mapInfo[uiMap] = info
    end
    return info
end

local function IsContinentOrWorld(uiMap)
    local info = MapInfo(uiMap)
    return info and Enum and Enum.UIMapType and info.mapType <= Enum.UIMapType.Continent
end

-- Maps whose pins show on the viewed map, with their projection (nil = same map).
local function SourceMaps(viewed)
    local list = {}
    if ns.pinsByMap[viewed] then list[#list + 1] = { viewed, nil } end
    local wide = IsContinentOrWorld(viewed)
    if wide and not QuestScoutDB.showOnContinent then return {} end
    for uiMap in pairs(ns.pinsByMap) do
        if uiMap ~= viewed then
            local info = MapInfo(uiMap)
            -- Continent/world: every zone inside. Zone: its child maps (cities, sub-zones).
            if wide or (info and info.parentMapID == viewed) then
                local r = Rect(uiMap, viewed)
                if r then list[#list + 1] = { uiMap, r } end
            end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Canvas placement (what MapCanvas did for its own pins)
---------------------------------------------------------------------------
local function Canvas()
    return WorldMapFrame:GetCanvas()
end

-- Same frame level as Blizzard's area POIs, above the map art and explored overlays.
local function PinLevel()
    local manager = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
    if manager and manager.GetValidFrameLevel then
        local ok, level = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_AREA_POI")
        if ok and type(level) == "number" then return level end
    end
    return Canvas():GetFrameLevel() + 400
end

-- Counter the canvas zoom so the pin keeps its size on screen, growing a little when zoomed in.
local function Place(frame, x, y)
    local canvas = Canvas()
    local zoom = math.min(math.max(WorldMapFrame:GetCanvasZoomPercent() or 0, 0), 1)
    local global = WorldMapFrame.GetGlobalPinScale and WorldMapFrame:GetGlobalPinScale() or 1
    local scale = (1 + ZOOM_GROWTH * zoom) / WorldMapFrame:GetCanvasScale() * global
    frame.nx, frame.ny = x, y
    frame:SetScale(scale)
    frame:ClearAllPoints()
    -- Anchor offsets are in the frame's own scale.
    frame:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * x / scale, -canvas:GetHeight() * y / scale)
end

local active, pinPool, dots = {}, {}, {}

---------------------------------------------------------------------------
-- Spawn dots, shown while hovering a pin with several possible locations
---------------------------------------------------------------------------
QuestScoutDotMixin = {}

function QuestScoutDotMixin:OnLoad()
    self.Outline:SetVertexColor(0, 0, 0, 0.9)
    self.Disc:SetVertexColor(1, 0.82, 0)
end

local function ShowDots(frame)
    local points = frame.pin.points
    if not points then return end
    local level = frame:GetFrameLevel()
    for i, p in ipairs(points) do
        local dot = dots[i]
        if not dot then
            dot = CreateFrame("Frame", nil, Canvas(), DOT)
            dots[i] = dot
        end
        dot:SetFrameLevel(level)
        Place(dot, Project(frame.rect, p.x, p.y))
        dot:Show()
    end
    for i = #points + 1, #dots do dots[i]:Hide() end
end

local function HideDots()
    for _, dot in ipairs(dots) do dot:Hide() end
end

---------------------------------------------------------------------------
-- Tooltip and hover
---------------------------------------------------------------------------
local KIND_TAGS = { { "class", "classe" }, { "skill", "métier" }, { "instance", "donjon" },
    { "repeatable", "répétable" }, { "seasonal", "saisonnière" }, { "warEffort", "effort de guerre" } }

local function QuestTags(q)
    local tags = {}
    for _, t in ipairs(KIND_TAGS) do
        if q[t[1]] then tags[#tags + 1] = t[2] end
    end
    return #tags > 0 and (" |cff8c8c8c(" .. table.concat(tags, ", ") .. ")|r") or ""
end

-- In Gamepad UI the map may keep the shared GameTooltip hidden, so pins get a tooltip of
-- their own there, on top of everything and at the shared tooltip's scale.
local gamepadTip
local function Tooltip()
    if not IsGamepadUI() then return GameTooltip end
    gamepadTip = gamepadTip or CreateFrame("GameTooltip", "QuestScoutTooltip", UIParent, "GameTooltipTemplate")
    gamepadTip:SetFrameStrata("TOOLTIP")
    gamepadTip:SetScale(GameTooltip:GetScale())
    return gamepadTip
end

local function FillTooltip(tip, frame)
    local pin, debug = frame.pin, QuestScoutDB.debug
    tip:SetOwner(frame, "ANCHOR_RIGHT")
    tip:AddLine(table.concat(pin.starters, ", "), 1, 1, 1)
    for _, e in ipairs(frame.entries) do
        local q = e.quest
        local text = ("[%d] %s"):format(q.level, ns.QuestTitle(q)) .. QuestTags(q)
        if debug then text = text .. (" |cff8c8c8c#%d|r"):format(q.id) end
        if e.state == "open" then
            tip:AddLine(text, ns.DifficultyColor(q.level, frame.playerLevel))
        else
            tip:AddDoubleLine(text, e.reason, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
        end
    end
    if pin.points then
        tip:AddLine(("%d emplacements possibles"):format(#pin.points), 1, 0.82, 0)
    end
    if debug then
        tip:AddLine(("carte %d · %.1f, %.1f"):format(pin.uiMap, pin.x * 100, pin.y * 100), 0.5, 0.5, 0.5)
    end
    if IsGamepadUI() then
        tip:AddLine("Clic : point de passage", 0.4, 0.8, 1)
    else
        tip:AddLine("Clic : point de passage · Maj-clic : masquer", 0.4, 0.8, 1)
    end
    tip:Show()
end

local hovered

local function Leave()
    if not hovered then return end
    if GameTooltip:IsOwned(hovered) then GameTooltip:Hide() end
    if gamepadTip then gamepadTip:Hide() end
    HideDots()
    hovered = nil
end

local function Enter(frame)
    Leave()
    hovered = frame
    FillTooltip(Tooltip(), frame)
    ShowDots(frame)
end

-- The pin under the gamepad cursor (or the mouse, if the soft cursor is hidden).
local function PinUnderCursor()
    local x, y
    if SoftCursor and SoftCursor:IsShown() then
        x, y = WorldMapFrame:GetNormalizedGamepadCursorPosition()
    elseif WorldMapFrame.ScrollContainer:IsMouseOver() then
        x, y = WorldMapFrame:GetNormalizedCursorPosition()
    end
    if not x or not y then return nil end
    local canvas = Canvas()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local reach = GAMEPAD_REACH / WorldMapFrame:GetCanvasScale()
    local best, bestD
    for _, f in ipairs(active) do
        -- Half the pin's size in canvas units, never less than the gamepad reach.
        local half = math.max(f:GetWidth() * f:GetScale() / 2, reach)
        local dx, dy = (f.nx - x) * w, (f.ny - y) * h
        if math.abs(dx) <= half and math.abs(dy) <= half then
            local d = dx * dx + dy * dy
            if not bestD or d < bestD then best, bestD = f, d end
        end
    end
    return best
end

-- Runs only while the map is shown.
local poller = CreateFrame("Frame")
poller:Hide()
local sincePoll = 0
poller:SetScript("OnUpdate", function(_, elapsed)
    sincePoll = sincePoll + elapsed
    if sincePoll < POLL_INTERVAL then return end
    sincePoll = 0
    if not IsGamepadUI() then return end
    local pin = PinUnderCursor()
    if pin ~= hovered then
        if pin then Enter(pin) else Leave() end
    end
end)

---------------------------------------------------------------------------
-- Pin
---------------------------------------------------------------------------
-- The client's crisp "!" atlas (same as Forever Quest Pins), old texture file as fallback.
local QUEST_ATLAS = "QuestNormal"
local QUEST_FILE = "Interface\\GossipFrame\\AvailableQuestIcon"
local hasAtlas

local function SetQuestIcon(tex)
    if hasAtlas == nil then
        hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(QUEST_ATLAS) ~= nil or false
    end
    if hasAtlas then
        tex:SetAtlas(QUEST_ATLAS, false)
    else
        tex:SetTexture(QUEST_FILE)
    end
end

QuestScoutPinMixin = {}

-- Mouse hover only; in Gamepad UI the poller decides, as the soft cursor's own
-- enter/leave events on the map are not reliable.
function QuestScoutPinMixin:OnEnter()
    if not IsGamepadUI() then Enter(self) end
end

function QuestScoutPinMixin:OnLeave()
    if not IsGamepadUI() and hovered == self then Leave() end
end

local function Click(frame, shift)
    if shift then
        for _, e in ipairs(frame.entries) do ns.SetHidden(e.quest.id, true) end
        Leave()
        ns.Print(("%d quête%s masquée%s (/qscout unhide pour annuler)."):format(
            #frame.entries, #frame.entries > 1 and "s" or "", #frame.entries > 1 and "s" or ""))
        ns.RefreshPins()
        return
    end
    local x, y = ns.PinTarget(frame.pin)
    ns.SetWaypoint(frame.pin.uiMap, x, y, ns.QuestTitle(frame.entries[1].quest))
end

function QuestScoutPinMixin:OnClick()
    local shift = IsShiftKeyDown()
    if IsGamepadUI() then
        -- A controller click can arrive mid map update: act on the next frame, if the
        -- pin still shows the same giver.
        local frame, pin = self, self.pin
        C_Timer.After(0, function()
            if frame.pin == pin and frame:IsShown() then Click(frame, shift) end
        end)
        return
    end
    Click(self, shift)
end

local function NewPin()
    local frame = CreateFrame("Button", nil, Canvas(), PIN)
    frame:RegisterForClicks("LeftButtonUp")
    -- Right-click over a pin still zooms the map out.
    if frame.SetPassThroughButtons then frame:SetPassThroughButtons("RightButton") end
    return frame
end

local function AcquirePin(pin, rect, entries, playerLevel, level)
    local frame = table.remove(pinPool) or NewPin()
    frame.pin, frame.rect, frame.entries, frame.playerLevel = pin, rect, entries, playerLevel
    frame:SetFrameLevel(level)
    local size = PinSize()
    frame:SetSize(size, size)
    Place(frame, Project(rect, pin.x, pin.y))

    local best = entries[1]
    local icon = frame.Icon
    SetQuestIcon(icon)
    -- Desaturate first so the tint gives the pure difficulty colour.
    icon:SetDesaturated(true)
    if best.state == "open" then
        icon:SetVertexColor(ns.DifficultyColor(best.quest.level, playerLevel))
        icon:SetAlpha(1)
    else
        icon:SetVertexColor(0.8, 0.8, 0.8) -- silver
        icon:SetAlpha(0.75)
    end
    ns.SetBadge(frame, QuestScoutDB.badges and ns.PinBadge(entries) or nil, size)
    frame:Show()
    active[#active + 1] = frame
end

---------------------------------------------------------------------------
-- Data provider: tells us when the map shows, changes map or zooms
---------------------------------------------------------------------------
local provider = CreateFromMixins(MapCanvasDataProviderMixin)

function provider:RemoveAllData()
    Leave()
    for i = #active, 1, -1 do
        local frame = active[i]
        frame:Hide()
        frame.pin, frame.entries = nil, nil
        pinPool[#pinPool + 1] = frame
        active[i] = nil
    end
end

local function SortEntries(a, b)
    if a.state ~= b.state then return a.state == "open" end
    return a.quest.level > b.quest.level
end

local combatPending = false

function provider:RefreshAllData()
    -- Kept from the MapCanvas pins, whose add/remove made Forever call a protected
    -- method. Plain frames should not need it, but that is not tested in game yet.
    if InCombatLockdown() then
        combatPending = true
        return
    end
    self:RemoveAllData()
    if not ns.ready or not QuestScoutDB.enabled then return end

    local map = self:GetMap()
    local playerLevel = UnitLevel("player")
    local level = PinLevel()
    for _, src in ipairs(SourceMaps(map:GetMapID())) do
        for _, pin in ipairs(ns.pinsByMap[src[1]]) do
            local entries
            for _, q in ipairs(pin.quests) do
                local state, reason = ns.Visibility(q, playerLevel)
                if state then
                    entries = entries or {}
                    entries[#entries + 1] = { quest = q, state = state, reason = reason }
                end
            end
            if entries then
                table.sort(entries, SortEntries)
                AcquirePin(pin, src[2], entries, playerLevel, level)
            end
        end
    end
end

local function Relayout()
    for _, frame in ipairs(active) do Place(frame, frame.nx, frame.ny) end
    for _, dot in ipairs(dots) do
        if dot:IsShown() then Place(dot, dot.nx, dot.ny) end
    end
end

function provider:OnCanvasScaleChanged()
    Relayout()
end

function provider:OnCanvasSizeChanged()
    Relayout()
end

function provider:OnMapChanged()
    self:RefreshAllData()
end

function provider:OnShow()
    sincePoll = 0
    poller:Show()
    self:RefreshAllData()
end

function provider:OnHide()
    poller:Hide()
    Leave()
end

WorldMapFrame:AddDataProvider(provider)

local refreshPending = false
function ns.RefreshPins()
    if refreshPending then return end
    refreshPending = true
    -- Completion flags lag a little behind turn-in events.
    C_Timer.After(0.5, function()
        refreshPending = false
        if WorldMapFrame:IsShown() then provider:RefreshAllData() end
    end)
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED" }) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if not combatPending then return end
        combatPending = false
    end
    ns.RefreshPins()
end)
table.insert(ns.onReady, ns.RefreshPins)

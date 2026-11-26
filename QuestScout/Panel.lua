-- QuestScout panel: "which zone now?"
local ADDON, ns = ...

local WIDTH, ROW_HEIGHT, PAD = 400, 36, 12
local GREY = "|cff8c8c8c"

local panel, summary, rows = nil, nil, {}

local function FormatXP(xp)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(xp)) or tostring(math.floor(xp))
end

local function OpenMap(uiMap)
    if OpenWorldMap then
        OpenWorldMap(uiMap)
    else
        ShowUIPanel(WorldMapFrame)
        WorldMapFrame:SetMapID(uiMap)
    end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function RowOnEnter(row)
    local z = row.zone
    if not z then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(z.name, 1, 1, 1)
    table.sort(z.quests, function(a, b) return a.level < b.level end)
    local playerLevel = UnitLevel("player")
    for _, q in ipairs(z.quests) do
        local title = C_QuestLog.GetTitleForQuestID(q.id) or q.name or ("#" .. q.id)
        local color = GetQuestDifficultyColor and GetQuestDifficultyColor(q.level) or NORMAL_FONT_COLOR
        if q.reqLevel > playerLevel then
            GameTooltip:AddDoubleLine(("[%d] %s"):format(q.level, title), ("niv. %d"):format(q.reqLevel),
                0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
        else
            GameTooltip:AddLine(("[%d] %s"):format(q.level, title), color.r, color.g, color.b)
        end
    end
    for _, d in ipairs(z.dungeons) do
        GameTooltip:AddLine(("Donjon : %s (%d–%d, %d quêtes)"):format(d.name, d.minLevel, d.maxLevel, d.questCount),
            0.4, 0.8, 1)
    end
    GameTooltip:AddLine("Clic : ouvrir la carte", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(WIDTH - 2 * PAD, ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.title:SetPoint("TOPLEFT", 4, -3)
    row.title:SetJustifyH("LEFT")

    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.detail:SetPoint("RIGHT", -4, 0)
    row.detail:SetJustifyH("LEFT")

    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self) if self.zone then OpenMap(self.zone.uiMap) end end)
    rows[index] = row
    return row
end

local function FillRow(row, i, z)
    row.zone = z
    local range = z.range and (GREY .. " (%d–%d)|r"):format(z.range[1], z.range[2]) or ""
    row.title:SetText(("%d. %s%s"):format(i, z.name, range))

    local parts = { ("%d quêtes"):format(z.open) }
    if z.soon > 0 then parts[1] = parts[1] .. (" (+%d bientôt)"):format(z.soon) end
    parts[#parts + 1] = ("%d hub%s"):format(z.hubs, z.hubs > 1 and "s" or "")
    parts[#parts + 1] = FormatXP(z.xp) .. " XP"
    if z.dungeons[1] then
        local d = z.dungeons[1]
        parts[#parts + 1] = ("|cff66ccffdonjon %s (%d–%d)|r"):format(d.name, d.minLevel, d.maxLevel)
    end
    row.detail:SetText(table.concat(parts, " · "))
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
function ns.RefreshPanel()
    if not panel or not panel:IsShown() then return end
    if not ns.ready then
        summary:SetText("Indexation des quêtes…")
        return
    end

    local playerLevel = UnitLevel("player")
    local list = ns.RankZones(playerLevel)
    summary:SetText(ns.Verdict(list, playerLevel))

    local shown = math.min(#list, QuestScoutDB.rows)
    local y = -(PAD + 24 + summary:GetStringHeight() + 8)
    for i = 1, shown do
        local row = rows[i] or CreateRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD, y)
        FillRow(row, i, list[i])
        row:Show()
        y = y - ROW_HEIGHT
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    panel:SetHeight(-y + PAD)
end

local function CreatePanel()
    panel = CreateFrame("Frame", "QuestScoutPanel", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(WIDTH, 200)
    -- Above the world map (HIGH), so the map button and a row click show both at once.
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        QuestScoutDB.position = { point, relPoint, x, y }
    end)
    local pos = QuestScoutDB.position
    if pos then
        panel:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        panel:SetPoint("CENTER")
    end

    local title = panel.TitleText or panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not panel.TitleText then title:SetPoint("TOP", 0, -5) end
    title:SetText("Quelle zone maintenant ?")

    summary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summary:SetPoint("TOPLEFT", PAD, -(PAD + 24))
    summary:SetWidth(WIDTH - 2 * PAD)
    summary:SetJustifyH("LEFT")
    summary:SetSpacing(2)

    panel:SetScript("OnShow", ns.RefreshPanel)
    tinsert(UISpecialFrames, "QuestScoutPanel") -- Escape closes it
    panel:Hide()
end

function ns.TogglePanel()
    if not panel then CreatePanel() end
    panel:SetShown(not panel:IsShown())
end

---------------------------------------------------------------------------
-- Events and slash command
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED" }) do
    events:RegisterEvent(e)
end
local pending = false
events:SetScript("OnEvent", function()
    if pending then return end
    pending = true
    -- Level and completion flags lag a little behind these events.
    C_Timer.After(1, function()
        pending = false
        ns.RefreshPanel()
    end)
end)
table.insert(ns.onReady, function() ns.RefreshPanel() end)

function ns.ResetPanelPosition()
    QuestScoutDB.position = nil
    if panel then
        panel:ClearAllPoints()
        panel:SetPoint("CENTER")
    end
end

---------------------------------------------------------------------------
-- World map button: opens the panel without typing /qscout (gamepad mode)
---------------------------------------------------------------------------
local function CreateMapButton()
    local anchor = WorldMapFrame.ScrollContainer or WorldMapFrame
    -- Parented to the map frame, not the canvas, so it neither zooms nor pans.
    local button = CreateFrame("Button", "QuestScoutMapButton", WorldMapFrame, "UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetText("Quelle zone ?")
    button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -8, -8)
    -- Pins live in the canvas with their own frame levels; stay above them.
    button:SetFrameLevel(anchor:GetFrameLevel() + 1000)
    button:SetScript("OnClick", ns.TogglePanel)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("Quelle zone maintenant ?", 1, 1, 1)
        GameTooltip:AddLine("Les zones classées selon les quêtes qui restent à ton niveau.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

CreateMapButton()

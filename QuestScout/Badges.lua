-- QuestScout badges: a small round icon on the top-right of a pin's "!".
-- Class quest -> class icon, profession quest -> profession icon, dungeon quest -> dungeon icon.
local ADDON, ns = ...

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local BADGE_RATIO = 2 / 3 -- of the pin size
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local function AtlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- { atlas = name } or { file = path|fileID }
local classIcon, dungeonIcon
local professionIcons = {}

local function ClassIcon()
    if classIcon then return classIcon end
    local _, classFile = UnitClass("player")
    local atlas = "classicon-" .. classFile:lower()
    if AtlasExists(atlas) then
        classIcon = { atlas = atlas }
    else
        local name = classFile == "DEATHKNIGHT" and "DeathKnight"
            or classFile:sub(1, 1) .. classFile:sub(2):lower()
        classIcon = { file = "Interface\\Icons\\ClassIcon_" .. name }
    end
    return classIcon
end

local function DungeonIcon()
    if dungeonIcon then return dungeonIcon end
    dungeonIcon = AtlasExists("Dungeon") and { atlas = "Dungeon" }
        or { file = "Interface\\Icons\\INV_Misc_Key_03" }
    return dungeonIcon
end

-- Profession pins only show for the player's own professions, so their icons come first.
local function RefreshProfessionIcons()
    wipe(professionIcons)
    if not GetProfessions or not GetProfessionInfo then return end
    for _, index in pairs({ GetProfessions() }) do
        if index then
            local _, icon, _, _, _, _, skillLine = GetProfessionInfo(index)
            if skillLine and icon then professionIcons[skillLine] = { file = icon } end
        end
    end
end

local function ProfessionIcon(skillLine)
    local known = professionIcons[skillLine]
    if known then return known end
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture then
        local ok, tex = pcall(C_TradeSkillUI.GetTradeSkillTexture, skillLine)
        if ok and tex then
            professionIcons[skillLine] = { file = tex }
            return professionIcons[skillLine]
        end
    end
    return { file = QUESTION_MARK }
end

---------------------------------------------------------------------------
-- Which badge for a pin: the highest-priority kind among its shown quests
---------------------------------------------------------------------------
local PRIORITY = { class = 3, profession = 2, dungeon = 1 }

local function QuestBadge(q)
    if q.class then return "class", ClassIcon() end
    if q.skill then return "profession", ProfessionIcon(q.skill[1]) end
    if q.instance then return "dungeon", DungeonIcon() end
end

-- entries = { {quest, state}, ... }
function ns.PinBadge(entries)
    local bestKind, bestIcon
    for _, e in ipairs(entries) do
        local kind, icon = QuestBadge(e.quest)
        if kind and (not bestKind or PRIORITY[kind] > PRIORITY[bestKind]) then
            bestKind, bestIcon = kind, icon
        end
    end
    return bestIcon
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function EnsureBadge(pin)
    local badge = pin.badge
    if badge then return badge end

    badge = {}
    badge.icon = pin:CreateTexture(nil, "OVERLAY", nil, 7)

    badge.mask = pin:CreateMaskTexture()
    badge.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    badge.mask:SetAllPoints(badge.icon)
    badge.masked = false

    pin.badge = badge
    return badge
end

function ns.SetBadge(pin, icon, pinSize)
    if not icon then
        if pin.badge then pin.badge.icon:Hide() end
        return
    end
    -- No outline: every badge is a bare round icon sitting on the pin's corner.
    local badge = EnsureBadge(pin)
    local size = math.floor(pinSize * BADGE_RATIO + 0.5)
    badge.icon:SetSize(size, size)
    badge.icon:ClearAllPoints()
    badge.icon:SetPoint("CENTER", pin, "TOPRIGHT", -size / 4, -size / 4)
    if icon.atlas then
        -- Atlas icons (dungeon vortex, class crest) are already shaped: no round mask.
        badge.icon:SetAtlas(icon.atlas, false)
        badge.icon:SetTexCoord(0, 1, 0, 1)
        if badge.masked then
            badge.icon:RemoveMaskTexture(badge.mask)
            badge.masked = false
        end
    else
        badge.icon:SetTexture(icon.file)
        badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the square icon border
        if not badge.masked then
            badge.icon:AddMaskTexture(badge.mask)
            badge.masked = true
        end
    end
    badge.icon:Show()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:SetScript("OnEvent", function()
    RefreshProfessionIcons()
    ns.ResetProfessions()
    if ns.RefreshPins then ns.RefreshPins() end
end)

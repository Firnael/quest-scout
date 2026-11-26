-- QuestScout options: panel in Escape > Options > AddOns, and the /qscout command.
local ADDON, ns = ...

local function Changed(key)
    if key == "below" or key == "above" or key == "rows" then
        if ns.RefreshPanel then ns.RefreshPanel() end
    else
        ns.RefreshPins()
    end
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
local controls = {}

-- Title in gold, explanation in white, shown beside the control under the cursor.
local function Explain(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        local tip = GameTooltip
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:AddLine(title, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
        tip:AddLine(body, 1, 1, 1, true)
        tip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- A check box bound to a setting through get() / set(value). The click flips the setting
-- itself, then the box follows it, so the box never disagrees with the saved value.
local function Checkbox(parent, label, tooltip, get, set)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    -- Older templates have no label of their own.
    box.Text = box.Text or box:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    box.Text:SetPoint("LEFT", box, "RIGHT", 4, 1)
    box.Text:SetText(label)
    function box:Sync() self:SetChecked(not not get()) end
    box:SetScript("OnClick", function(self)
        set(not get())
        self:Sync()
    end)
    if tooltip then Explain(box, label, tooltip) end
    controls[#controls + 1] = box
    return box
end

local function OptionBox(parent, key, label, tooltip)
    return Checkbox(parent, label, tooltip,
        function() return QuestScoutDB[key] end,
        function(v)
            QuestScoutDB[key] = v
            Changed(key)
        end)
end

-- format(value) -> label text; toSaved/fromSaved map slider values to saved values.
local function Slider(parent, key, minV, maxV, step, format, toSaved, fromSaved)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetSize(220, 16)
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    if slider.Low then slider.Low:SetText("") end
    if slider.High then slider.High:SetText("") end
    if slider.Text then slider.Text:SetText("") end
    local label = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)
    toSaved = toSaved or function(v) return v end
    fromSaved = fromSaved or function(v) return v end
    slider.Sync = function(self)
        self.syncing = true
        local v = fromSaved(QuestScoutDB[key])
        self:SetValue(v)
        label:SetText(format(v))
        self.syncing = false
    end
    slider:SetScript("OnValueChanged", function(self, value)
        if self.syncing then return end
        value = math.floor(value / step + 0.5) * step
        QuestScoutDB[key] = toSaved(value)
        label:SetText(format(value))
        Changed(key)
    end)
    controls[#controls + 1] = slider
    return slider
end

local function Heading(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetText(text)
    return fs
end

-- Stacks widgets top to bottom from an anchor.
local function Column(anchor, x, y)
    local last
    return function(widget, gap)
        widget:ClearAllPoints()
        if last then
            widget:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -(gap or 0))
        else
            widget:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
        end
        last = widget
        return widget
    end
end

local function SyncAll()
    for _, c in ipairs(controls) do c:Sync() end
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local category

local function BuildPanel(panel)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Quest Scout")
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Départs de quête sur la carte et panneau « Quelle zone maintenant ? » (/qscout).")

    -- Left column: pins and levels
    local left = Column(panel, 16, -64)
    left(Heading(panel, "Repères"))
    left(OptionBox(panel, "enabled", "Afficher les repères de quête"), 6)
    left(OptionBox(panel, "badges", "Pastilles classe / métier / donjon"))
    left(OptionBox(panel, "showLocked", "Quêtes bientôt disponibles en grisé",
        ("Quêtes dont le niveau requis est au plus %d niveaux au-dessus du tien."):format(ns.LOCKED_AHEAD)))
    left(OptionBox(panel, "showOnContinent", "Repères sur les cartes de continent et du monde"))
    left(Slider(panel, "pinScale", 50, 150, 5, function(v) return ("Taille des repères : %d %%"):format(v) end), 24)

    left(Heading(panel, "Niveaux"), 24)
    left(OptionBox(panel, "showLowLevel", "Afficher les quêtes bas niveau"), 6)
    left(Slider(panel, "pinBelow", 3, 15, 1,
        function(v) return ("Bas niveau : %d niveaux ou plus en dessous"):format(v) end), 24)
    -- 15 on the slider means "no upper limit" (saved as 0).
    left(Slider(panel, "pinAbove", 3, 15, 1,
        function(v) return v >= 15 and "Haut niveau : tout afficher"
            or ("Haut niveau : masquer à %d niveaux ou plus au-dessus"):format(v) end,
        function(v) return v >= 15 and 0 or v end,
        function(v) return v == 0 and 15 or v end), 30)

    -- Right column: types, navigation, misc
    local right = Column(panel, 340, -64)
    right(Heading(panel, "Types de quête"))
    right(OptionBox(panel, "showNormal", "Normales"), 6)
    right(OptionBox(panel, "showClass", "De classe"))
    right(OptionBox(panel, "showProfession", "De métier", "Seulement pour les métiers que tu connais."))
    right(OptionBox(panel, "showDungeon", "Donjon et raid"))
    right(OptionBox(panel, "showRepeatable", "Répétables"))
    right(OptionBox(panel, "showSeasonal", "Saisonnières (fêtes, Foire de Sombrelune…)"))
    right(OptionBox(panel, "showWarEffort", "Effort de guerre d'AQ",
        "Remises de matériaux dans les capitales, avant l'ouverture d'Ahn'Qiraj."))

    right(Heading(panel, "Navigation"), 16)
    right(OptionBox(panel, "tomtom", "Points de passage TomTom",
        "Sinon, repère de carte Blizzard. TomTom doit être installé et activé."), 6)
    right(Checkbox(panel, "Marqueur de destination en jeu",
        "Marqueur flottant avec la distance. Réglage partagé du jeu (showInGameNavigation) : d'autres addons peuvent le changer.",
        ns.GetInWorldMarker, ns.SetInWorldMarker))

    right(Heading(panel, "Divers"), 16)
    right(OptionBox(panel, "debug", "Debug : IDs de quête et carte dans les infobulles"), 6)
    local unhide = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    unhide:SetSize(220, 22)
    unhide.Sync = function(self)
        local n = ns.HiddenCount()
        self:SetText(("Réafficher les quêtes masquées (%d)"):format(n))
        self:SetEnabled(n > 0)
    end
    unhide:SetScript("OnClick", function(self)
        ns.UnhideAll()
        ns.RefreshPins()
        self:Sync()
    end)
    controls[#controls + 1] = unhide
    right(unhide, 8)
    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    help:SetText("Maj-clic sur un repère pour le masquer. /qscout help pour les commandes.")
    right(help, 8)

    panel:SetScript("OnShow", SyncAll)
    SyncAll()
end

local function RegisterPanel()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
    panel:Hide()
    local built = false
    panel:SetScript("OnShow", function(self)
        if built then return end
        built = true
        BuildPanel(self)
    end)
    category = Settings.RegisterCanvasLayoutCategory(panel, "Quest Scout")
    Settings.RegisterAddOnCategory(category)
end

local function OpenOptions()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
    else
        ns.Print("panneau d'options indisponible sur ce client.")
    end
end

---------------------------------------------------------------------------
-- /qscout
---------------------------------------------------------------------------
local function Why(id)
    local q = ns.questById[id]
    if not q then
        ns.Print(("#%d : absente de l'index (inconnue de QuestieDB, pas pour ta race/classe, ou sans donneur)."):format(id))
        return
    end
    local state, reason = ns.Visibility(q, UnitLevel("player"))
    local pins = ns.pinsByQuest[id] or {}
    local maps = {}
    for _, pin in ipairs(pins) do
        local info = C_Map.GetMapInfo(pin.uiMap)
        maps[#maps + 1] = ("%s %.1f,%.1f"):format(info and info.name or pin.uiMap, pin.x * 100, pin.y * 100)
    end
    ns.Print(("#%d [%d] %s : %s%s"):format(id, q.level, ns.QuestTitle(q),
        state and (state == "open" and "|cff40ff40visible|r" or "|cffaaaaaagrisée|r (" .. reason .. ")") or ("|cffff6060masquée|r, " .. reason),
        #maps > 0 and (" · " .. table.concat(maps, " ; ")) or " · aucun emplacement sur une carte"))
end

local function Track(id)
    local pins = ns.pinsByQuest[id]
    if not pins or #pins == 0 then
        ns.Print(("#%d : aucun emplacement connu."):format(id))
        return
    end
    local here = C_Map.GetBestMapForUnit("player")
    local target = pins[1]
    for _, pin in ipairs(pins) do
        if pin.uiMap == here then target = pin break end
    end
    local x, y = ns.PinTarget(target)
    local q = ns.questById[id]
    if ns.SetWaypoint(target.uiMap, x, y, q and ns.QuestTitle(q) or ("#" .. id)) then
        ns.Print(("point de passage : %s"):format(q and ns.QuestTitle(q) or ("#" .. id)))
    end
end

local HELP = {
    "/qscout : panneau « Quelle zone maintenant ? »",
    "/qscout <en dessous> <au-dessus> : plage du panneau",
    "/qscout on | off : repères sur la carte",
    "/qscout options : réglages",
    "/qscout why <id> : pourquoi une quête est affichée ou masquée",
    "/qscout track <id> : point de passage vers une quête  ·  /qscout clear : l'enlever",
    "/qscout unhide <id | all> : réafficher des quêtes masquées",
    "/qscout debug : IDs dans les infobulles  ·  /qscout refresh  ·  /qscout reset : position du panneau",
}

SLASH_QUESTSCOUT1 = "/qscout"
SlashCmdList.QUESTSCOUT = function(input)
    local db = QuestScoutDB
    local a, b = input:match("^%s*(%d+)%s+(%d+)%s*$")
    local cmd, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local id = tonumber(rest)
    if a then
        db.below, db.above = tonumber(a), tonumber(b)
        ns.Print(("plage du panneau : -%d / +%d niveaux"):format(db.below, db.above))
        ns.RefreshPanel()
    elseif cmd == "" then
        ns.TogglePanel()
    elseif cmd == "on" or cmd == "off" then
        db.enabled = cmd == "on"
        ns.Print("repères : " .. (db.enabled and "affichés" or "masqués"))
        ns.RefreshPins()
    elseif cmd == "badges" then
        db.badges = not db.badges
        ns.Print("pastilles : " .. (db.badges and "oui" or "non"))
        ns.RefreshPins()
    elseif cmd == "debug" then
        db.debug = not db.debug
        ns.Print("debug : " .. (db.debug and "oui" or "non"))
    elseif cmd == "refresh" then
        ns.RefreshPins()
    elseif cmd == "options" then
        OpenOptions()
    elseif cmd == "why" and id then
        Why(id)
    elseif cmd == "track" and id then
        Track(id)
    elseif cmd == "clear" then
        ns.ClearWaypoint()
    elseif cmd == "unhide" and rest == "all" then
        ns.UnhideAll()
        ns.Print("toutes les quêtes masquées sont réaffichées.")
        ns.RefreshPins()
    elseif cmd == "unhide" and id then
        ns.SetHidden(id, false)
        ns.Print(("#%d réaffichée."):format(id))
        ns.RefreshPins()
    elseif cmd == "hidden" or cmd == "unhide" then
        ns.Print(("%d quête(s) masquée(s) sur ce personnage. /qscout unhide <id | all>"):format(ns.HiddenCount()))
    elseif cmd == "reset" then
        ns.ResetPanelPosition()
    else
        for _, line in ipairs(HELP) do ns.Print(line) end
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", RegisterPanel)

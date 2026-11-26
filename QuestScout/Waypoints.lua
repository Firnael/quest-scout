-- QuestScout waypoints: Blizzard map pin (default) or TomTom, plus Blizzard's in-world marker.
local ADDON, ns = ...

local tomtomUID   -- TomTom waypoint we created
local blizzardSet -- { uiMap, x, y } of the Blizzard pin we created

local function ClearOwn()
    if tomtomUID and TomTom and TomTom.RemoveWaypoint then
        pcall(TomTom.RemoveWaypoint, TomTom, tomtomUID)
    end
    tomtomUID = nil
    if blizzardSet and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
        local point = C_Map.GetUserWaypoint()
        -- Only clear the Blizzard pin when it is still ours.
        if point and point.uiMapID == blizzardSet[1]
            and math.abs(point.position.x - blizzardSet[2]) < 1e-4
            and math.abs(point.position.y - blizzardSet[3]) < 1e-4 then
            C_Map.ClearUserWaypoint()
        end
    end
    blizzardSet = nil
end
ns.ClearWaypoint = ClearOwn

-- x, y in 0-1 on uiMap.
function ns.SetWaypoint(uiMap, x, y, title)
    ClearOwn()
    if QuestScoutDB.tomtom then
        if not (TomTom and TomTom.AddWaypoint) then
            ns.Print("TomTom n'est pas chargé : active-le ou repasse sur les repères Blizzard (/qscout options).")
            return false
        end
        tomtomUID = TomTom:AddWaypoint(uiMap, x, y, {
            title = title, persistent = false, minimap = true, world = true, from = "QuestScout",
        })
        return tomtomUID ~= nil
    end

    if not (C_Map.SetUserWaypoint and UiMapPoint) then
        ns.Print("Les repères Blizzard ne sont pas disponibles sur ce client.")
        return false
    end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(uiMap) then
        ns.Print("Impossible de poser un repère sur cette carte.")
        return false
    end
    local ok = pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMap, x, y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end)
    if ok then blizzardSet = { uiMap, x, y } end
    return ok
end

-- Nearest spawn of a pin to the player when they stand on its map, else its anchor.
function ns.PinTarget(pin)
    local x, y = pin.x, pin.y
    if pin.points and C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(pin.uiMap, "player")
        if pos then
            local px, py = pos:GetXY()
            local bestD
            for _, p in ipairs(pin.points) do
                local d = (p.x - px) ^ 2 + (p.y - py) ^ 2
                if not bestD or d < bestD then x, y, bestD = p.x, p.y, d end
            end
        end
    end
    return x, y
end

---------------------------------------------------------------------------
-- In-world destination marker: Blizzard's shared showInGameNavigation setting
---------------------------------------------------------------------------
local NAV_CVAR = "showInGameNavigation"

function ns.InWorldMarkerAvailable()
    return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(NAV_CVAR) ~= nil
end

function ns.GetInWorldMarker()
    return ns.InWorldMarkerAvailable() and C_CVar.GetCVar(NAV_CVAR) == "1"
end

function ns.SetInWorldMarker(on)
    if ns.InWorldMarkerAvailable() then C_CVar.SetCVar(NAV_CVAR, on and "1" or "0") end
end

local addonName, ns = ...

-- Finding recipe vendors on the map. Uses only the game's own map pin (the same one a
-- Ctrl-click on the world map places), so no other addon is needed. If TomTom is installed
-- it is given the same waypoint as a convenience.
--
-- Vendor positions are bundled data (see LICENSE.txt). Zones are matched to the client's
-- maps by name at run time, so no map numbers are assumed.

local function say(text)
    local chat = rawget(_G, "DEFAULT_CHAT_FRAME")
    if chat and chat.AddMessage then chat:AddMessage("|cffffc842Profession Planner:|r " .. text) end
end

-- The vendors in an acquisition text that this faction can buy from, in the order given.
-- Each is { name, zone, x, y }; x and y are missing when no position is known.
function ns.VendorStops(source, faction)
    local stops = {}
    if type(source) ~= "string" then return stops end
    local list = string.match(source, "^%a+ %d[%dgsc ]*: (.+)$")
    if not list then return stops end
    list = string.gsub(list, " and %d+ more$", "")
    local mine = (faction == "Horde" and "H") or (faction == "Alliance" and "A") or nil
    local known = ns.RawData and ns.RawData.vendors or {}
    for vendor in string.gmatch(list .. ";", "%s*(.-)%s*;") do
        local tag = string.match(vendor, "%((%a)%)$")
        if vendor ~= "" and (not tag or not mine or tag == mine) then
            local name, zone = string.match((string.gsub(vendor, "%s*%(%a%)$", "")), "^(.+),%s*(.-)$")
            if name and zone ~= "" then
                local stop = { name = name, zone = zone }
                for _, place in ipairs(known[name] or {}) do
                    if place.zone == zone then stop.x, stop.y = place.x, place.y end
                end
                table.insert(stops, stop)
            end
        end
    end
    return stops
end

function ns.StopText(stop)
    if stop.x then return string.format("%s, %s (%.1f, %.1f)", stop.name, stop.zone, stop.x, stop.y) end
    return stop.name .. ", " .. stop.zone
end

-- The acquisition text for the player's faction, with map coordinates where known.
function ns.SourceWithCoords(source, faction)
    local text = ns.SourceForFaction(source, faction)
    if type(text) ~= "string" then return text end
    for _, stop in ipairs(ns.VendorStops(source, faction)) do
        if stop.x then
            local plain = stop.name .. ", " .. stop.zone
            local from, to = string.find(text, plain, 1, true)
            if from then text = string.sub(text, 1, from - 1) .. ns.StopText(stop) .. string.sub(text, to + 1) end
        end
    end
    return text
end

local mapByName
local function indexMaps()
    mapByName = {}
    local maps = rawget(_G, "C_Map")
    if type(maps) ~= "table" or type(maps.GetMapChildrenInfo) ~= "function" then return end
    for _, root in ipairs({ 946, 947 }) do
        local ok, children = pcall(maps.GetMapChildrenInfo, root, nil, true)
        if ok and type(children) == "table" then
            for _, info in pairs(children) do
                if type(info) == "table" and type(info.name) == "string" and type(info.mapID) == "number" then
                    local seen = mapByName[info.name]
                    -- Prefer a zone or city map over a floor or cave of the same name.
                    if not seen or ((info.mapType or 99) < (seen.mapType or 99)) then mapByName[info.name] = info end
                end
            end
        end
    end
end

function ns.FindMap(zone)
    if not mapByName or next(mapByName) == nil then indexMaps() end
    local info = mapByName[zone] or mapByName[zone .. " City"] or mapByName["City of " .. zone]
    return info and info.mapID or nil
end

local function continentOf(mapId)
    local maps = rawget(_G, "C_Map")
    for _ = 1, 8 do
        if not mapId or type(maps) ~= "table" or type(maps.GetMapInfo) ~= "function" then return nil end
        local ok, info = pcall(maps.GetMapInfo, mapId)
        if not ok or type(info) ~= "table" then return nil end
        if info.mapType == 2 then return mapId end
        mapId = info.parentMapID
    end
    return nil
end

-- Order the stops so the one in the player's zone comes first, then ones on the same
-- continent, then the rest.
function ns.SortStops(stops)
    local maps = rawget(_G, "C_Map")
    local here
    if type(maps) == "table" and type(maps.GetBestMapForUnit) == "function" then
        local ok, mapId = pcall(maps.GetBestMapForUnit, "player")
        if ok then here = mapId end
    end
    local continent = continentOf(here)
    local ranked = {}
    for index, stop in ipairs(stops) do
        local mapId = ns.FindMap(stop.zone)
        local rank = 3
        if mapId and mapId == here then rank = 1
        elseif mapId and continent and continentOf(mapId) == continent then rank = 2 end
        table.insert(ranked, { stop = stop, rank = rank, index = index })
    end
    table.sort(ranked, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.index < b.index end)
    local result = {}
    for _, entry in ipairs(ranked) do table.insert(result, entry.stop) end
    return result
end

-- Pin one vendor and open the map on it. Returns true when a pin was placed.
function ns.ShowStop(stop, another)
    local mapId = ns.FindMap(stop.zone)
    if not mapId then
        say("Cannot find a map called " .. stop.zone .. ". Look for " .. ns.StopText(stop) .. ".")
        return false
    end
    local pinned = false
    local maps, point, track = rawget(_G, "C_Map"), rawget(_G, "UiMapPoint"), rawget(_G, "C_SuperTrack")
    if stop.x and type(maps) == "table" and type(maps.SetUserWaypoint) == "function"
        and type(point) == "table" and type(point.CreateFromCoordinates) == "function" then
        local allowed = true
        if type(maps.CanSetUserWaypointOnMap) == "function" then
            local ok, can = pcall(maps.CanSetUserWaypointOnMap, mapId)
            allowed = ok and can == true
        end
        if allowed then
            pinned = pcall(function() maps.SetUserWaypoint(point.CreateFromCoordinates(mapId, stop.x / 100, stop.y / 100)) end)
            if pinned and type(track) == "table" and type(track.SetSuperTrackedUserWaypoint) == "function" then
                pcall(track.SetSuperTrackedUserWaypoint, true)
            end
        end
    end
    local tomtom = rawget(_G, "TomTom")
    if stop.x and type(tomtom) == "table" and type(tomtom.AddWaypoint) == "function" then
        pcall(tomtom.AddWaypoint, tomtom, mapId, stop.x / 100, stop.y / 100, { title = stop.name, from = "Profession Planner" })
    end
    local open = rawget(_G, "OpenWorldMap")
    if type(open) == "function" then pcall(open, mapId) end
    local message
    if pinned then message = "Map pin placed on " .. ns.StopText(stop) .. "."
    elseif stop.x then message = "Could not place a pin on this map. " .. ns.StopText(stop) .. "."
    else message = "No position is known for " .. stop.name .. "; opened the map of " .. stop.zone .. "." end
    if another then message = message .. " Click again for " .. another.name .. ", " .. another.zone .. "." end
    say(message)
    return pinned
end

-- "Show on map" for a recipe: the nearest usable vendor first; each further click moves on
-- to the next one.
local lastSource, lastIndex
function ns.ShowVendor(source, faction)
    local stops = ns.SortStops(ns.VendorStops(source, faction))
    if #stops == 0 then return nil end
    if lastSource == source then lastIndex = lastIndex % #stops + 1 else lastSource, lastIndex = source, 1 end
    local stop = stops[lastIndex]
    ns.ShowStop(stop, #stops > 1 and stops[lastIndex % #stops + 1] or nil)
    return stop
end

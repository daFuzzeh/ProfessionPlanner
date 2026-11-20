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

local tomtomPin

-- Remove the pin this addon placed. A pin the player has since put somewhere else is left
-- alone. `reason` starts the chat message; pass false for no message.
function ns.ClearPin(reason)
    local ours = ns.pinned
    if not ours then return false end
    ns.pinned = nil
    local maps = rawget(_G, "C_Map")
    if type(maps) == "table" and type(maps.ClearUserWaypoint) == "function" then
        local still = true
        if type(maps.GetUserWaypoint) == "function" then
            local ok, point = pcall(maps.GetUserWaypoint)
            still = ok and type(point) == "table" and point.uiMapID == ours.map and type(point.position) == "table"
                and math.abs((point.position.x or 0) - ours.x) < 0.002 and math.abs((point.position.y or 0) - ours.y) < 0.002
        end
        if still then pcall(maps.ClearUserWaypoint) end
    end
    local tomtom = rawget(_G, "TomTom")
    if tomtomPin and type(tomtom) == "table" and type(tomtom.RemoveWaypoint) == "function" then
        pcall(tomtom.RemoveWaypoint, tomtom, tomtomPin)
    end
    tomtomPin = nil
    if reason ~= false then say((reason or "Map pin") .. " cleared.") end
    if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then ns.RefreshUI() end
    return true
end

-- Talking to the vendor the pin points at means the trip is done.
function ns.ArrivedAtVendor()
    local unitName = rawget(_G, "UnitName")
    if not ns.pinned or type(unitName) ~= "function" then return false end
    local ok, vendor = pcall(unitName, "npc")
    if ok and vendor == ns.pinned.name then return ns.ClearPin("Reached " .. vendor .. "; map pin") end
    return false
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
        local ok, uid = pcall(tomtom.AddWaypoint, tomtom, mapId, stop.x / 100, stop.y / 100, { title = stop.name, from = "Profession Planner" })
        tomtomPin = ok and uid or nil
    end
    -- Remember our pin so it can be removed again, by the button or on reaching the vendor.
    if pinned then ns.pinned = { name = stop.name, zone = stop.zone, map = mapId, x = stop.x / 100, y = stop.y / 100 } end
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
    if ns.pinned then ns.pinned.source = source end
    if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then ns.RefreshUI() end
    return stop
end

-- Limited vendor stock --------------------------------------------------------
-- Some vendors hold only one or two of a recipe and take hours to get another, so those
-- recipes are often sold out or camped. Two sources say which: bundled data describing the
-- original game (see LICENSE.txt), and what this player has actually seen in vendor windows
-- (`seen[itemId][vendorName] = { left = n, at = time }`, left = -1 for no limit). What was
-- seen always wins.

local function contains(list, value)
    for _, item in ipairs(list or {}) do if item == value then return true end end
    return false
end

-- nil when the recipe item can always be bought from some vendor this faction can use.
-- Otherwise { max, restock (seconds), vendors = { names }, last = { name, left, at } }.
function ns.VendorStock(source, itemId, faction, seen)
    local data = ns.RawData and ns.RawData.vendorStock and ns.RawData.vendorStock[itemId] or nil
    local observed = type(seen) == "table" and seen[itemId] or nil
    if not data and type(observed) ~= "table" then return nil end
    local result = { vendors = {} }
    local function limitedAt(name, max, restock)
        table.insert(result.vendors, name)
        if max and (not result.max or max > result.max) then result.max = max end
        if restock and restock > 0 and (not result.restock or restock < result.restock) then result.restock = restock end
    end
    local judged = {}
    local function judge(name)
        if judged[name] then return true end
        judged[name] = true
        local sight = type(observed) == "table" and observed[name] or nil
        if type(sight) == "table" and type(sight.left) == "number" then
            if sight.left < 0 then return false end
            local known = data and data.limited[name] or nil
            limitedAt(name, known and known.max or nil, known and known.restock or nil)
            if not result.last or (sight.at or 0) > (result.last.at or 0) then
                result.last = { name = name, left = sight.left, at = sight.at }
            end
        elseif data and data.limited[name] then
            limitedAt(name, data.limited[name].max, data.limited[name].restock)
        elseif data and contains(data.open, name) then
            return false
        end
        return true
    end
    local stops = ns.VendorStops(source, faction)
    for _, stop in ipairs(stops) do
        if not judge(stop.name) then return nil end
    end
    -- Vendors the player has bought from that the text does not name.
    if type(observed) == "table" then
        for name in pairs(observed) do
            if not judge(name) then return nil end
        end
    end
    if #stops == 0 and #result.vendors == 0 and data and #(data.open or {}) == 0 then
        -- The text names no vendor we can match; go by the item alone.
        for name, limit in pairs(data.limited) do limitedAt(name, limit.max, limit.restock) end
    end
    if #result.vendors == 0 then return nil end
    return result
end

local function duration(seconds)
    if seconds >= 5400 then return string.format("%d hours", math.floor(seconds / 3600 + 0.5)) end
    if seconds >= 3600 then return "1 hour" end
    return string.format("%d minutes", math.max(1, math.floor(seconds / 60 + 0.5)))
end

-- One line describing a stock limit for the player.
function ns.StockText(stock, now)
    local text = "Limited stock"
    if stock.max then text = text .. ": " .. stock.max .. " at a time" end
    if stock.restock then text = text .. (stock.max and ", " or ": ") .. "about " .. duration(stock.restock) .. " to restock" end
    text = text .. ". May be sold out or camped."
    local last = stock.last
    if last then
        local ago = (type(now) == "number" and type(last.at) == "number" and now >= last.at) and (" " .. duration(now - last.at) .. " ago") or ""
        if last.left == 0 then text = text .. " " .. last.name .. " was sold out when you looked" .. ago .. "."
        else text = text .. " " .. last.name .. " had " .. last.left .. " when you looked" .. ago .. "." end
    end
    return text
end

local teachItems
local function isTeachItem(itemId)
    if not teachItems then
        teachItems = {}
        for _, recipe in ipairs(ns.RawData and ns.RawData.recipes or {}) do
            for _, item in ipairs(recipe.teachItems or {}) do teachItems[item] = true end
        end
    end
    return teachItems[itemId] == true
end

-- Called while a vendor window is open: remember how many of each recipe the vendor has.
function ns.ScanMerchant()
    if not ns.DB then return 0 end
    local unitName, count, linkOf = rawget(_G, "UnitName"), rawget(_G, "GetMerchantNumItems"), rawget(_G, "GetMerchantItemLink")
    if type(unitName) ~= "function" or type(count) ~= "function" or type(linkOf) ~= "function" then return 0 end
    local okName, vendor = pcall(unitName, "npc")
    local okCount, total = pcall(count)
    if not okName or type(vendor) ~= "string" or vendor == "" or not okCount or type(total) ~= "number" then return 0 end
    local frameApi, legacy, clock = rawget(_G, "C_MerchantFrame"), rawget(_G, "GetMerchantItemInfo"), rawget(_G, "time")
    local now = type(clock) == "function" and clock() or nil
    local recorded = 0
    for index = 1, total do
        local okLink, link = pcall(linkOf, index)
        local itemId = okLink and type(link) == "string" and tonumber(string.match(link, "item:(%d+)")) or nil
        if itemId and isTeachItem(itemId) then
            local left
            if type(frameApi) == "table" and type(frameApi.GetItemInfo) == "function" then
                local ok, info = pcall(frameApi.GetItemInfo, index)
                if ok and type(info) == "table" then left = info.numAvailable end
            elseif type(legacy) == "function" then
                local ok, _, _, _, _, available = pcall(legacy, index)
                if ok then left = available end
            end
            if type(left) == "number" then
                ns.DB.vendorSeen = ns.DB.vendorSeen or {}
                ns.DB.vendorSeen[itemId] = ns.DB.vendorSeen[itemId] or {}
                ns.DB.vendorSeen[itemId][vendor] = { left = left, at = now }
                recorded = recorded + 1
            end
        end
    end
    if recorded > 0 and ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then ns.RefreshUI() end
    return recorded
end

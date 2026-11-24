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
-- continent, then the rest; a zone the game has no map for goes last.
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
        local rank = mapId and 3 or 4
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
    -- Point the travel arrow at it too; a problem there must not cost the player the pin.
    if stop.x and ns.Travel then pcall(ns.Travel.GoTo, mapId, stop.x / 100, stop.y / 100, stop.name) end
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
function ns.ShowVendor(source, faction, given)
    local stops = ns.SortStops(given or ns.VendorStops(source, faction))
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

local function plural(number, word)
    return number .. " " .. word .. (number == 1 and "" or "s")
end

local function duration(seconds)
    if seconds >= 5400 then return plural(math.floor(seconds / 3600 + 0.5), "hour") end
    if seconds >= 3600 then return "1 hour" end
    return plural(math.max(1, math.floor(seconds / 60 + 0.5)), "minute")
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

-- Whether the trainer window shows the recipes the player can learn now. A window that hides
-- them lists less than the trainer teaches, so then nothing may be concluded from what is
-- missing. A client without the call has no such filter; a call that fails cannot be trusted.
local function availableShown()
    local filter = rawget(_G, "GetTrainerServiceTypeFilter")
    if type(filter) ~= "function" then return true end
    local ok, shown = pcall(filter, "available")
    if not ok then return false end
    return shown == true or (type(shown) == "number" and shown ~= 0)
end

-- Profession -> skill of the character being played, as the game reports it now (TSM's copy
-- can lag behind).
local function playedSkills()
    local skills = {}
    local profile = ns.profile
    local char = profile and profile.currentId and profile.chars and profile.chars[profile.currentId] or nil
    for name, prof in pairs(char and char.profs or {}) do
        if type(prof) == "table" and type(prof.level) == "number" then skills[name] = prof.level end
    end
    if type(ns.ReadLiveSkills) == "function" then
        for name, live in pairs(ns.ReadLiveSkills()) do skills[name] = live.level end
    end
    return skills
end

-- Called while a trainer window is open: read the skill each recipe is taught at. The game is
-- the only place that knows it, so this replaces the shipped rank from then on. A trainer that
-- lists the profession's recipes but not one the planner counted on is noted too.
function ns.ScanTrainer()
    if not ns.DB or not ns.D then return 0 end
    local count, infoOf, needOf = rawget(_G, "GetNumTrainerServices"), rawget(_G, "GetTrainerServiceInfo"), rawget(_G, "GetTrainerServiceSkillReq")
    if type(count) ~= "function" or type(infoOf) ~= "function" or type(needOf) ~= "function" then return 0 end
    local okCount, total = pcall(count)
    if not okCount or type(total) ~= "number" then return 0 end
    -- `listed` is every service in the window; `services` those that ask for a skill.
    local listed, services = {}, {}
    for index = 1, total do
        local okInfo, name, _, category = pcall(infoOf, index)
        if okInfo and type(name) == "string" and category ~= "header" then
            local okNeed, skill, rank = pcall(needOf, index)
            local line = { name = name }
            if okNeed and type(skill) == "string" then line.skill = skill end
            table.insert(listed, line)
            if okNeed and type(skill) == "string" and type(rank) == "number" then
                table.insert(services, { name = name, skill = skill, rank = rank })
            end
        end
    end
    if #listed == 0 then return 0 end
    local unitName, clock = rawget(_G, "UnitName"), rawget(_G, "time")
    local npc
    if type(unitName) == "function" then
        local ok, who = pcall(unitName, "npc")
        if ok and type(who) == "string" and who ~= "" then npc = who end
    end
    local now = type(clock) == "function" and clock() or nil
    local name = npc or "This trainer"
    local fresh, differ, changed = 0, 0, {}
    if #services > 0 then
        if type(ns.DB.trainerRanks) ~= "table" then ns.DB.trainerRanks = {} end
        fresh, differ, changed = ns.RecordTrainerRanks(ns.DB.trainerRanks, services, npc, now)
        if fresh > 0 then ns.ApplyTrainerRanks(ns.DB.trainerRanks) end
    end
    if type(ns.DB.trainerMissing) ~= "table" then ns.DB.trainerMissing = {} end
    local added, cleared = ns.RecordTrainerMissing(ns.DB.trainerMissing, listed, npc, playedSkills(), ns.PlayedKnows, now, availableShown())
    if fresh > 0 then
        if differ == 0 then
            say("read " .. fresh .. (fresh == 1 and " learn rank" or " learn ranks") .. " from " .. (npc or "this trainer") .. ".")
        else
            local parts = {}
            for index = 1, math.min(3, #changed) do
                local change = changed[index]
                table.insert(parts, change.name .. " from skill " .. change.rank .. (change.was and (", not " .. change.was) or ""))
            end
            say(name .. " teaches " .. table.concat(parts, "; ") .. (#changed > 3 and ("; and " .. (#changed - 3) .. " more") or "")
                .. ". Routes now use that.")
        end
    end
    -- One line for each profession whose recipes a trainer did not offer.
    local byProfession, order = {}, {}
    for _, recipe in ipairs(added) do
        if not byProfession[recipe.prof] then
            byProfession[recipe.prof] = {}
            table.insert(order, recipe.prof)
        end
        table.insert(byProfession[recipe.prof], recipe)
    end
    for _, prof in ipairs(order) do
        local recipes = byProfession[prof]
        table.sort(recipes, function(a, b)
            if a.learn ~= b.learn then return a.learn < b.learn end
            return a.name < b.name
        end)
        local names = {}
        for _, recipe in ipairs(recipes) do table.insert(names, recipe.name) end
        local many = #recipes > 1
        say(name .. " does not teach " .. ns.NameList(names) .. " at your skill (" .. ns.DB.trainerMissing[recipes[1].spell].skill .. "). "
            .. (many and "They are" or "It is") .. " out of your routes until a trainer lists " .. (many and "them" or "it") .. ".")
    end
    -- The lines above already say why these recipes moved; the kept route must not say it a second time.
    ns.routeExplained = ns.routeExplained or {}
    for _, change in ipairs(changed) do ns.routeExplained[change.spell] = true end
    for _, recipe in ipairs(added) do ns.routeExplained[recipe.spell] = true end
    if (fresh > 0 or #added > 0 or cleared > 0) and ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then ns.RefreshUI() end
    return fresh
end

-- Rank trainers ---------------------------------------------------------------
-- Not every trainer teaches every rank, and the title does not say which: an "Expert
-- Alchemist" teaches Journeyman only. `cap` is the skill cap the rank lifts (75, 150, 225).
-- Returns the trainers this faction can use, as map stops.
function ns.RankTrainers(profession, cap, faction)
    local stops = {}
    local data = ns.RawData and ns.RawData.rankTrainers and ns.RawData.rankTrainers[profession] or nil
    local mine = (faction == "Horde" and "H") or (faction == "Alliance" and "A") or nil
    for _, trainer in ipairs(data and data[cap] or {}) do
        local side = trainer.fac or ""
        if not mine or side == "" or string.find(side, mine, 1, true) then
            table.insert(stops, { name = trainer.name, zone = trainer.zone, x = trainer.x, y = trainer.y, title = trainer.title })
        end
    end
    return stops
end

function ns.ShowTrainer(profession, cap, faction)
    return ns.ShowVendor("trainer:" .. profession .. ":" .. cap, faction, ns.RankTrainers(profession, cap, faction))
end

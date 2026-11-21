local _, ns = ...

-- Travel: works out how to get from where the character stands to a chosen spot (walk,
-- flight paths the character has learned, boats and zeppelins) and points an arrow at the
-- next stop. The player does every step; nothing here moves the character or clicks.
--
-- Positions are world coordinates as the client's own tables store them: `c` is the map id
-- of the continent, `x` grows to the north and `y` to the west, both in yards.

local T = {}
ns.Travel = T

local RUN_SPEED = 7      -- yards per second on foot
local DETOUR = 1.3       -- a walked path is longer than the straight line
local ARRIVE = 15        -- yards from the goal that count as there
local AT_MASTER = 8      -- close enough to talk to a flight master
local AT_DOCK = 25
local PICKUP_MIN_WALK = 600  -- shorter walks never detour to learn a flight point
local BEND = 12           -- yards from a bend in the trail that count as reached
local OFF_TRAIL = 70      -- further than this from the trail: work the trail out again
local OFF_COURSE = 400   -- further than this from the best distance so far: plan again

local function dist(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
T.Distance = dist

local function data() return ns.TravelData end

-- ---------------------------------------------------------------------------------------
-- Places
-- ---------------------------------------------------------------------------------------

-- The landmass a point is on. Two points on one landmass can be walked between.
function T.Landmass(c, x, y, zone)
    local d = data()
    for _, pocket in ipairs(d.pockets) do
        if pocket.c == c and dist(pocket, { x = x, y = y }) <= pocket.r then return pocket.lm end
    end
    local known = zone and d.zones[zone]
    if known and not known.wide and known.c == c then return known.lm end
    local best, area
    for _, z in pairs(d.zones) do
        if not z.wide and z.c == c and x >= z.x0 and x <= z.x1 and y >= z.y0 and y <= z.y1 then
            local size = (z.x1 - z.x0) * (z.y1 - z.y0)
            if not area or size < area then best, area = z, size end
        end
    end
    if best then return best.lm end
    for _, z in pairs(d.zones) do
        if z.wide and z.c == c then return z.c == 0 and "ek" or (z.c == 1 and "kalimdor" or tostring(z.c)) end
    end
    return tostring(c)
end

-- A spot on a zone map (fractions 0-1 from the top left) as a world position.
function T.FromMap(mapId, fx, fy)
    local z = data().zones[mapId]
    if not z or type(fx) ~= "number" or type(fy) ~= "number" then return nil end
    local x = z.x1 - (z.x1 - z.x0) * fy
    local y = z.y1 - (z.y1 - z.y0) * fx
    return { c = z.c, x = x, y = y, lm = T.Landmass(z.c, x, y, mapId), zone = z.wide and nil or z.n }
end

function T.Place(c, x, y, zone)
    return { c = c, x = x, y = y, lm = T.Landmass(c, x, y, zone) }
end

-- ---------------------------------------------------------------------------------------
-- Route planning (no game calls: testable on its own)
-- ---------------------------------------------------------------------------------------

local function usable(faction, who) return faction == "B" or faction == who end

-- who = { faction = "H"|"A", known = { [nodeId] = true } }. With known = nil every flight
-- point of the faction counts as learned.
-- Returns { steps = {...}, seconds = n } or nil and a reason.
function T.Plan(from, to, who)
    local d = data()
    local known = who.known
    local verts = { { kind = "start", c = from.c, x = from.x, y = from.y, lm = from.lm },
                    { kind = "goal", c = to.c, x = to.x, y = to.y, lm = to.lm } }
    local byNode = {}
    for id, node in pairs(d.nodes) do
        if usable(node.f, who.faction) and (known == nil or known[id]) then
            table.insert(verts, { kind = "node", id = id, c = node.c, x = node.x, y = node.y, lm = node.lm, n = node.n })
            byNode[id] = #verts
        end
    end
    local docks = {}
    for index, line in ipairs(d.transports) do
        if usable(line.f, who.faction) then
            docks[index] = {}
            for stopIndex, stop in ipairs(line.stops) do
                table.insert(verts, { kind = "dock", line = line, c = stop.c, x = stop.x, y = stop.y, lm = stop.lm, n = stop.n })
                docks[index][stopIndex] = #verts
            end
        end
    end
    local count = #verts
    local special = {}
    for index = 1, count do special[index] = {} end
    for _, flight in ipairs(d.flights) do
        local a, b = byNode[flight[1]], byNode[flight[2]]
        if a and b then special[a][b] = { secs = flight[3], kind = "fly" } end
    end
    for index, stops in pairs(docks) do
        local line = d.transports[index]
        local total = #stops
        for i = 1, total do
            for j = 1, total do
                if i ~= j then
                    local legs = (j - i) % total
                    local via = {}
                    for hop = 1, legs - 1 do table.insert(via, line.stops[(i + hop - 1) % total + 1].n) end
                    special[stops[i]][stops[j]] = { secs = line.wait + line.ride * legs, kind = "ride", via = via }
                end
            end
        end
    end

    local best, prev, how, done = {}, {}, {}, {}
    for index = 1, count do best[index] = math.huge end
    best[1] = 0
    while true do
        local u, low = nil, math.huge
        for index = 1, count do
            if not done[index] and best[index] < low then u, low = index, best[index] end
        end
        if not u or u == 2 then break end
        done[u] = true
        local a = verts[u]
        for v = 1, count do
            if not done[v] and v ~= 1 then
                local b = verts[v]
                local edge = special[u][v]
                local secs, kind = edge and edge.secs, edge and edge.kind
                if a.c == b.c and a.lm == b.lm then
                    local walk = dist(a, b) * DETOUR / RUN_SPEED
                    if not secs or walk < secs then secs, kind = walk, "walk" end
                end
                if secs and low + secs < best[v] then best[v], prev[v], how[v] = low + secs, u, kind end
            end
        end
    end
    if best[2] == math.huge then return nil, "no route" end

    local chain, at = {}, 2
    while at ~= 1 do
        table.insert(chain, 1, at)
        at = prev[at]
    end
    local steps, last, lastIndex = {}, verts[1], 1
    for index, v in ipairs(chain) do
        local b, kind = verts[v], how[v]
        local previous = steps[#steps]
        if kind == "walk" then
            local length = dist(last, b)
            if b.kind == "goal" and previous and length <= ARRIVE then
                previous.final = true   -- the last stop is the goal itself
            elseif b.kind == "goal" then
                table.insert(steps, { kind = "walk", c = b.c, x = b.x, y = b.y, r = ARRIVE, final = true, text = "Go to " .. (to.title or "the marked spot") })
            elseif length > AT_MASTER then
                if b.kind == "node" then
                    table.insert(steps, { kind = "walk", c = b.c, x = b.x, y = b.y, r = AT_MASTER, text = "Go to the flight master at " .. b.n, node = b.id })
                else
                    table.insert(steps, { kind = "walk", c = b.c, x = b.x, y = b.y, r = AT_DOCK, text = "Go to the " .. b.line.kind .. " dock at " .. b.n })
                end
            end
        elseif kind == "fly" then
            if previous and previous.kind == "fly" then
                previous.c, previous.x, previous.y, previous.text, previous.node = b.c, b.x, b.y, "Fly to " .. b.n, b.id
            else
                table.insert(steps, { kind = "fly", c = b.c, x = b.x, y = b.y, r = 80, text = "Fly to " .. b.n, node = b.id })
            end
        else
            local via = special[lastIndex][v].via
            local text = "Take the " .. b.line.kind .. " to " .. b.n
            if #via > 0 then text = text .. " (stay on at " .. table.concat(via, ", ") .. ")" end
            table.insert(steps, { kind = "ride", c = b.c, x = b.x, y = b.y, r = 150, text = text })
        end
        last, lastIndex = b, v
        if index == #chain and #steps == 0 then
            table.insert(steps, { kind = "walk", c = b.c, x = b.x, y = b.y, r = ARRIVE, final = true, text = "Go to " .. (to.title or "the marked spot") })
        end
    end
    return { steps = steps, seconds = best[2] }
end

-- Flight points the character has not learned that lie almost on a walked leg are worth the
-- few extra steps. They are added as stops of their own.
function T.AddPickups(plan, from, who)
    if who.known == nil then return plan end
    local d = data()
    local result, at = {}, { c = from.c, x = from.x, y = from.y, lm = from.lm }
    for _, step in ipairs(plan.steps) do
        -- Only on a long walk, and only where the flight map has been read: until then nothing
        -- is known about what the character has learned, and "not seen" is not "not learned".
        local read = who.scanned == nil or who.scanned[step.c]
        local leg = dist(at, step)
        if step.kind == "walk" and read and leg >= PICKUP_MIN_WALK then
            local found = {}
            for id, node in pairs(d.nodes) do
                if node.f ~= "U" and usable(node.f, who.faction) and not who.known[id] and node.c == step.c and node.lm == at.lm and id ~= step.node then
                    local extra = dist(at, node) + dist(node, step) - leg
                    if extra <= leg * 0.15 then table.insert(found, { id = id, node = node, along = dist(at, node) }) end
                end
            end
            table.sort(found, function(a, b) if a.along ~= b.along then return a.along < b.along end return a.id < b.id end)
            for _, entry in ipairs(found) do
                table.insert(result, { kind = "learn", c = entry.node.c, x = entry.node.x, y = entry.node.y, r = AT_MASTER, node = entry.id,
                    text = "Pick up the flight point at " .. entry.node.n })
            end
        end
        table.insert(result, step)
        at = { c = step.c, x = step.x, y = step.y, lm = T.Landmass(step.c, step.x, step.y) }
    end
    plan.steps = result
    return plan
end

-- How much sooner the trip would be with every flight point of the faction learned.
function T.Route(from, to, who)
    local plan, reason = T.Plan(from, to, who)
    if not plan then return nil, reason end
    if who.known ~= nil then
        local ideal = T.Plan(from, to, { faction = who.faction })
        if ideal and plan.seconds - ideal.seconds > 120 then plan.slower = plan.seconds - ideal.seconds end
        T.AddPickups(plan, from, who)
    end
    return plan
end

-- Which way to turn. `facing` is the game's: radians, 0 = north, growing anticlockwise.
function T.Bearing(from, to, facing)
    local angle = math.atan2(to.y - from.y, to.x - from.x) - (facing or 0)
    while angle > math.pi do angle = angle - 2 * math.pi end
    while angle < -math.pi do angle = angle + 2 * math.pi end
    return angle
end

function T.Heading(angle)
    local turn = math.abs(angle)
    if turn < math.pi / 8 then return "ahead" end
    if turn > math.pi * 7 / 8 then return "behind you" end
    local side = angle > 0 and "left" or "right"
    if turn < math.pi * 3 / 8 then return "ahead, " .. side end
    if turn < math.pi * 5 / 8 then return "to the " .. side end
    return "behind, " .. side
end

-- ---------------------------------------------------------------------------------------
-- The game side
-- ---------------------------------------------------------------------------------------

local function say(text)
    local chat = rawget(_G, "DEFAULT_CHAT_FRAME")
    if chat and chat.AddMessage then chat:AddMessage("|cffffc842Profession Planner:|r " .. text) end
end

local function call(name, ...)
    local fn = rawget(_G, name)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, e = pcall(fn, ...)
    if ok then return a, b, c, e end
    return nil
end

local function saved()
    if not ns.DB then return nil end
    if type(ns.DB.travel) ~= "table" then ns.DB.travel = {} end
    local store = ns.DB.travel
    if type(store.chars) ~= "table" then store.chars = {} end
    return store
end

local function faction()
    local side = call("UnitFactionGroup", "player")
    if side == "Alliance" then return "A" end
    if side == "Horde" then return "H" end
    return nil
end

local function character()
    local store = saved()
    if not store then return nil end
    local name = call("UnitName", "player") or "?"
    local key = name .. "-" .. (call("GetRealmName") or "?") .. "-" .. (faction() or "?")
    if type(store.chars[key]) ~= "table" then store.chars[key] = { nodes = {}, scanned = {} } end
    local entry = store.chars[key]
    if type(entry.nodes) ~= "table" then entry.nodes = {} end
    if type(entry.scanned) ~= "table" then entry.scanned = {} end
    return entry
end

function T.Who()
    local entry = character()
    return { faction = faction() or "H", known = entry and entry.nodes or {}, scanned = entry and entry.scanned or {} }
end

-- Where the character is, or nil inside an instance. The map position is the reference;
-- UnitPosition is used when the two agree, because it also works where no zone map does.
function T.PlayerPlace()
    local d = data()
    local maps = rawget(_G, "C_Map")
    local zone, mapPlace
    if type(maps) == "table" and type(maps.GetBestMapForUnit) == "function" then
        local ok, mapId = pcall(maps.GetBestMapForUnit, "player")
        if ok and type(mapId) == "number" and d.zones[mapId] and not d.zones[mapId].wide and type(maps.GetPlayerMapPosition) == "function" then
            local fine, point = pcall(maps.GetPlayerMapPosition, mapId, "player")
            if fine and type(point) == "table" then
                local fx, fy = point.x, point.y
                if type(point.GetXY) == "function" then fx, fy = point:GetXY() end
                mapPlace = T.FromMap(mapId, fx, fy)
                zone = mapId
            end
        end
    end
    local x, y, _, instance = call("UnitPosition", "player")
    if type(x) == "number" and type(y) == "number" and type(instance) == "number" then
        instance = d.alias[instance] or instance
        local routable = false
        for _, z in pairs(d.zones) do if z.c == instance then routable = true break end end
        if routable then
            local place = T.Place(instance, x, y, zone)
            if not mapPlace or (mapPlace.c == instance and dist(mapPlace, place) < 200) then return place end
        end
    end
    return mapPlace
end

-- Read the open flight map: every flight point on it is learned, every other flight point
-- of this continent is not. Returns how many were read.
function T.ScanTaxi()
    local entry, d = character(), data()
    local total = call("NumTaxiNodes")
    local here = T.PlayerPlace()
    if not entry or type(total) ~= "number" or total == 0 or not here then return 0 end
    local side = faction()
    local byName = {}
    for id, node in pairs(d.nodes) do
        if node.c == here.c then
            if not byName[node.n] or node.f == side then byName[node.n] = id end
        end
    end
    local seen, read = {}, 0
    for index = 1, total do
        local name, kind = call("TaxiNodeName", index), call("TaxiNodeGetType", index)
        local id = type(name) == "string" and byName[name]
        if id and kind ~= "NONE" then seen[id] = true read = read + 1 end
    end
    if read == 0 then return 0 end
    for id, node in pairs(d.nodes) do
        if node.c == here.c then entry.nodes[id] = seen[id] or nil end
    end
    entry.scanned[here.c] = true
    return read
end

-- The arrow --------------------------------------------------------------------------

local ARROW = "Interface\\Minimap\\MinimapArrow"

local function buildFrame()
    local parent = rawget(_G, "UIParent")
    local frame = CreateFrame("Frame", "ProfessionPlannerTravelFrame", parent)
    frame:SetSize(340, 80)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local store = saved()
        local point, _, _, x, y = self:GetPoint(1)
        if store and point then store.pos = { point = point, x = x, y = y } end
    end)
    local store = saved()
    local pos = store and store.pos
    if type(pos) == "table" and type(pos.point) == "string" and type(pos.x) == "number" and type(pos.y) == "number" then
        frame:SetPoint(pos.point, parent, pos.point, pos.x, pos.y)
    else
        frame:SetPoint("TOP", parent, "TOP", 0, -140)
    end
    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(frame)
    back:SetColorTexture(0.06, 0.05, 0.04, 0.82)
    frame.arrow = frame:CreateTexture(nil, "ARTWORK")
    frame.arrow:SetSize(44, 44)
    frame.arrow:SetPoint("LEFT", frame, "LEFT", 8, 0)
    frame.arrow:SetTexture(ARROW)
    frame.step = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.step:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, -8)
    frame.step:SetWidth(240)
    frame.step:SetJustifyH("LEFT")
    frame.where = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.where:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, -36)
    frame.where:SetWidth(272)
    frame.where:SetJustifyH("LEFT")
    frame.via = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.via:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, -50)
    frame.via:SetWidth(272)
    frame.via:SetJustifyH("LEFT")
    frame.next = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.next:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, -64)
    frame.next:SetWidth(272)
    frame.next:SetJustifyH("LEFT")

    local function small(label, offset, onClick)
        local button = CreateFrame("Button", nil, frame)
        button:SetSize(14, 14)
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", offset, -4)
        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.label:SetText(label)
        button:SetScript("OnClick", onClick)
        return button
    end
    frame.close = small("x", -4, function() T.Stop("Travel stopped.") end)
    frame.skip = small(">", -20, function() T.Skip() end)

    local sinceArrow, sinceStep = 0, 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        sinceArrow, sinceStep = sinceArrow + elapsed, sinceStep + elapsed
        if sinceStep >= 0.5 then sinceStep = 0 T.Tick() end
        if sinceArrow >= 0.05 then sinceArrow = 0 T.Draw() end
    end)
    frame:Hide()
    return frame
end

local function frame()
    if not T.frame then T.frame = buildFrame() end
    return T.frame
end

local function yards(n)
    if n >= 1000 then return string.format("%.1fk yd", n / 1000) end
    return string.format("%d yd", n)
end

local function minutes(seconds)
    if seconds < 90 then return "about a minute" end
    return string.format("about %d min", math.floor(seconds / 60 + 0.5))
end

-- The trail for the current walking stop: path points from where the player stands to the
-- stop, around what the terrain puts in the way. One point (the stop) when no path is known.
function T.Trail(trip, step, here)
    local trail = trip.trail
    if trail and trail.step == step and trail.c == here.c then return trail end
    local points, _, partial
    if ns.Paths then points, _, partial = ns.Paths.Find(here.c, here.x, here.y, step.x, step.y) end
    trail = { step = step, c = here.c, known = points ~= nil, partial = partial, points = points or { { x = step.x, y = step.y } },
        at = 1, from = { x = here.x, y = here.y }, age = 0 }
    trip.trail = trail
    return trail
end

-- Move on to the next bend once this one is reached or the player is already past it.
local function follow(trail, here)
    local points = trail.points
    while trail.at < #points do
        local bend, after = points[trail.at], points[trail.at + 1]
        local off, along = ns.Paths.FromSegment(here.x, here.y, bend.x, bend.y, after.x, after.y)
        if dist(here, bend) <= BEND or (off < 20 and along > 0.02) then
            trail.from, trail.at = bend, trail.at + 1
        else
            break
        end
    end
end

function T.Draw()
    local trip = T.trip
    if not trip or not T.frame or not T.frame:IsShown() then return end
    local f = T.frame
    local step = trip.plan and trip.plan.steps[trip.index]
    local here = T.PlayerPlace()
    if not step then return end
    local total = #trip.plan.steps
    f.step:SetText(string.format("%d/%d  %s", trip.index, total, step.text))
    local following = trip.plan.steps[trip.index + 1]
    f.next:SetText(following and ("Then: " .. following.text) or "")
    local pointing = here and here.c == step.c and step.kind ~= "fly" and step.kind ~= "ride"
    f.via:SetText("")
    if pointing then
        local trail = T.Trail(trip, step, here)
        follow(trail, here)
        local points, at = trail.points, trail.at
        local aim = points[at]
        local gap = dist(here, aim)
        local left = gap
        for index = at, #points - 1 do left = left + dist(points[index], points[index + 1]) end
        local facing = call("GetPlayerFacing")
        if type(facing) == "number" then
            f.arrow:SetRotation(T.Bearing(here, aim, facing))
            f.arrow:Show()
        else
            f.arrow:Hide()
        end
        local where = yards(gap) .. " " .. ns.Paths.Compass(here.x, here.y, aim.x, aim.y)
        if at < #points then
            local turn = ns.Paths.Turn(here.x, here.y, aim.x, aim.y, points[at + 1].x, points[at + 1].y)
            where = where .. ", then " .. (turn or "straight on")
        end
        f.where:SetText(where)
        local toward
        for index = at, #points - 1 do
            if points[index].name then toward = points[index].name break end
        end
        local via = yards(left) .. " to go"
        if toward then via = "Towards " .. toward .. " - " .. via end
        if not trail.known and left > 150 then via = via .. " (straight line: no path known here)" end
        if trail.partial then
            via = via .. (at < #points and " (path known part of the way)" or " (straight line from here)")
        end
        f.via:SetText(via)
        local close = dist(here, step) <= step.r * 2
        if close and (step.kind == "learn" or (step.node and step.kind == "walk")) then f.where:SetText("Talk to the flight master") end
    else
        f.arrow:Hide()
        if not here then f.where:SetText("No position in here; the arrow returns outside")
        elseif step.kind == "fly" then f.where:SetText(call("UnitOnTaxi", "player") and "In flight" or "Choose it on the flight map")
        elseif step.kind == "ride" then f.where:SetText("Board when it docks, and stay on until it arrives")
        else f.where:SetText("On another continent") end
    end
end

local function goal() return T.trip and T.trip.goal end

function T.Replan(quiet)
    local trip = T.trip
    if not trip then return false end
    local here = T.PlayerPlace()
    if not here then trip.waiting = true return false end
    trip.waiting = nil
    local who = T.Who()
    local plan, reason = T.Route(here, trip.goal, who)
    if not plan then
        if here.c == trip.goal.c then
            plan = { steps = { { kind = "walk", c = trip.goal.c, x = trip.goal.x, y = trip.goal.y, r = ARRIVE, final = true,
                text = "No known route; straight line to " .. (trip.goal.title or "the marked spot") } }, seconds = 0, direct = true }
        else
            T.Stop("No route to " .. (trip.goal.title or "that spot") .. " with the boats, zeppelins and flight points your faction can use (" .. tostring(reason) .. ").")
            return false
        end
    end
    trip.plan, trip.index, trip.best = plan, 1, nil
    if not quiet then
        local parts = {}
        for index, step in ipairs(plan.steps) do table.insert(parts, index .. ". " .. step.text) end
        say("Route to " .. (trip.goal.title or "the marked spot") .. (plan.direct and "" or (", " .. minutes(plan.seconds))) .. ": " .. table.concat(parts, "  "))
        if not who.scanned[here.c] then say("Flight points on this continent have not been read yet. Open any flight map once and the route will use the ones you know.") end
        if plan.slower then say("With every flight point learned this trip would be " .. minutes(plan.slower) .. " shorter.") end
    end
    frame():Show()
    T.Draw()
    return true
end

-- Start guiding to a spot on a zone map. Returns true when a route is showing.
function T.GoTo(mapId, fx, fy, title)
    local place = T.FromMap(mapId, fx, fy)
    if not place then
        say("Travel does not know the map for that spot.")
        return false
    end
    return T.GoToPlace(place, title)
end

function T.GoToPlace(place, title)
    local current = goal()
    if current and current.c == place.c and dist(current, place) < 5 then
        -- The same spot again (the planner's button and its map pin both report it): keep the trip.
        if title then current.title = title end
        if T.trip.plan then return T.Replan(true) end
    end
    place.title = title or place.title
    T.trip = { goal = place }
    if T.Replan() then return true end
    if T.trip and T.trip.waiting then
        say("Travel will start when you are back in the open world.")
        frame():Show()
        return true
    end
    return false
end

function T.Stop(message)
    if not T.trip then return false end
    T.trip = nil
    if T.frame then T.frame:Hide() end
    if message then say(message) end
    return true
end

function T.Skip()
    local trip = T.trip
    if not trip or not trip.plan then return end
    if trip.index >= #trip.plan.steps then T.Stop("Travel stopped.") return end
    trip.index, trip.best = trip.index + 1, nil
    T.Draw()
end

-- Called twice a second while a trip is showing: has the current stop been reached?
function T.Tick()
    local trip = T.trip
    if not trip then return end
    if not trip.plan then T.Replan() return end
    local step = trip.plan.steps[trip.index]
    local here = T.PlayerPlace()
    if not step or not here then return end
    local flying = call("UnitOnTaxi", "player") and true or false
    local gap = here.c == step.c and dist(here, step) or nil
    local function advance()
        if trip.index >= #trip.plan.steps then
            T.Stop("You have arrived at " .. (trip.goal.title or "the marked spot") .. ".")
        else
            trip.index, trip.best = trip.index + 1, nil
        end
    end
    local trail = trip.trail
    if gap and trail and trail.step == step and (step.kind == "walk" or step.kind == "learn") then
        trail.age = trail.age + 1
        local aim = trail.points[trail.at]
        local off = ns.Paths.FromSegment(here.x, here.y, trail.from.x, trail.from.y, aim.x, aim.y)
        if off > OFF_TRAIL and trail.age >= 4 and not flying then trip.trail = nil end
    end
    if step.kind == "walk" then
        if not gap then T.Replan(true) return end
        if gap <= step.r then advance() return end
        trip.best = math.min(trip.best or gap, gap)
        if gap > trip.best + OFF_COURSE and not flying then T.Replan(true) end
    elseif step.kind == "learn" then
        if not gap then T.Replan(true) return end
        if T.Who().known[step.node] then T.Replan(true) end
    elseif step.kind == "fly" then
        if flying then trip.flew = true return end
        if gap and gap <= step.r then trip.flew = nil advance() return end
        if trip.flew then trip.flew = nil T.Replan(true) end
    elseif step.kind == "ride" then
        if gap and gap <= step.r then advance() end
    end
end

-- Names the player can type after /pp go: dungeons, flight points, zones.
function T.Find(text)
    local d = data()
    local want = string.lower(text or "")
    if want == "" then return nil end
    local function match(name) return string.find(string.lower(name), want, 1, true) end
    local exact, partial
    local function consider(name, place)
        if string.lower(name) == want then exact = exact or { name = name, place = place }
        elseif match(name) then partial = partial or { name = name, place = place } end
    end
    for _, dungeon in ipairs(d.dungeons) do consider(dungeon.n, { c = dungeon.c, x = dungeon.x, y = dungeon.y, lm = dungeon.lm }) end
    local side = faction() or "H"
    local ids = {}
    for id in pairs(d.nodes) do table.insert(ids, id) end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local node = d.nodes[id]
        if usable(node.f, side) then consider(node.n, { c = node.c, x = node.x, y = node.y, lm = node.lm }) end
    end
    local zoneIds = {}
    for id in pairs(d.zones) do table.insert(zoneIds, id) end
    table.sort(zoneIds)
    for _, id in ipairs(zoneIds) do
        local z = d.zones[id]
        if not z.wide then consider(z.n, T.FromMap(id, 0.5, 0.5)) end
    end
    return exact or partial
end

-- /pp go <place> | /pp go <x> <y> (this zone) | /pp stop
function T.Slash(message)
    local text = string.gsub(message or "", "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    local lower = string.lower(text)
    if lower == "stop" then
        if not T.Stop("Travel stopped.") then say("No trip is showing.") end
        return true
    end
    if lower == "record" or lower == "record on" or lower == "record off" then
        local store = saved()
        if store and lower ~= "record" then store.record = lower == "record on" end
        local total = 0
        for _, strokes in pairs(store and type(store.trails) == "table" and store.trails or {}) do
            for _, stroke in ipairs(strokes) do total = total + #stroke / 2 end
        end
        say("Recording walked paths is " .. (T.Recording() and "on" or "off") .. ". " .. total .. " points recorded so far. /pp record off or /pp record on changes it.")
        return true
    end
    if lower ~= "go" and string.sub(lower, 1, 3) ~= "go " then return false end
    local rest = string.gsub(string.sub(text, 3), "^%s+", "")
    if rest == "" then
        local names = {}
        for _, dungeon in ipairs(data().dungeons) do table.insert(names, dungeon.n) end
        say("Type /pp go and a dungeon, flight point or zone, or /pp go 45 62 for a spot in this zone. /pp stop ends the trip. Or place a map pin. Dungeons: " .. table.concat(names, ", ") .. ".")
        return true
    end
    local sx, sy = string.match(rest, "^(%d+%.?%d*)[%s,]+(%d+%.?%d*)$")
    if sx then
        local maps = rawget(_G, "C_Map")
        local ok, mapId = false, nil
        if type(maps) == "table" and type(maps.GetBestMapForUnit) == "function" then ok, mapId = pcall(maps.GetBestMapForUnit, "player") end
        local zone = ok and data().zones[mapId]
        if not zone or zone.wide then say("Travel cannot tell which zone you are in.") return true end
        T.GoTo(mapId, tonumber(sx) / 100, tonumber(sy) / 100, string.format("%s %s, %s", zone.n, sx, sy))
        return true
    end
    local found = T.Find(rest)
    if not found then say("Travel knows no dungeon, flight point or zone called " .. rest .. ".") return true end
    T.GoToPlace(found.place, found.name)
    return true
end

-- A map pin placed by the player (or by another addon) starts a trip; removing it ends one.
function T.PinChanged()
    local store = saved()
    if store and store.followPins == false then return end
    local maps = rawget(_G, "C_Map")
    if type(maps) ~= "table" or type(maps.GetUserWaypoint) ~= "function" then return end
    local ok, point = pcall(maps.GetUserWaypoint)
    if not ok then return end
    if type(point) ~= "table" or type(point.position) ~= "table" then
        if T.trip and T.trip.fromPin then T.Stop("Map pin removed; travel stopped.") end
        return
    end
    local px, py = point.position.x, point.position.y
    if type(point.position.GetXY) == "function" then px, py = point.position:GetXY() end
    local place = T.FromMap(point.uiMapID, px, py)
    if not place then return end
    local title = ns.pinned and ns.pinned.map == point.uiMapID and ns.pinned.name or "your map pin"
    if T.GoToPlace(place, title) and T.trip then T.trip.fromPin = true end
end

-- The recorder ---------------------------------------------------------------------------
-- Remembers where the player walks, so trails can use real paths through cities, tunnels and
-- over bridges that the terrain data does not show. Kept in the addon's saved settings.

local RECORD_STEP = 10      -- yards between recorded points
local RECORD_JUMP = 80      -- further than this in a second is not walking
local RECORD_CAP = 40000    -- points per continent
local REBUILD_AFTER = 25    -- new points before the trails take them in

local rec = { known = {} }

local function trails(c)
    local store = saved()
    if not store then return nil end
    if type(store.trails) ~= "table" then store.trails = {} end
    if type(store.trails[c]) ~= "table" then store.trails[c] = {} end
    return store.trails[c]
end

local function cellKey(x, y) return math.floor(x / 8) * 65536 + math.floor(y / 8) end

-- The 8-yard squares that already hold a recorded point, per continent.
local function knownCells(c)
    if rec.known[c] then return rec.known[c] end
    local cells, total = {}, 0
    for _, stroke in ipairs(trails(c) or {}) do
        for at = 1, #stroke - 1, 2 do
            cells[cellKey(stroke[at], stroke[at + 1])] = true
            total = total + 1
        end
    end
    rec.known[c] = { cells = cells, total = total, fresh = 0 }
    return rec.known[c]
end

local function isKnown(known, x, y)
    for dx = -8, 8, 8 do
        for dy = -8, 8, 8 do
            if known.cells[cellKey(x + dx, y + dy)] then return true end
        end
    end
    return false
end

-- The stroke being walked only counts as recorded ground once it ends; otherwise its own
-- last point would end it.
local function endStroke()
    if rec.stroke and rec.pending then
        local known = knownCells(rec.pending.c)
        for key in pairs(rec.pending.keys) do known.cells[key] = true end
    end
    rec.stroke, rec.pending = nil, nil
end

function T.Recording()
    local store = saved()
    return store ~= nil and store.record ~= false
end

-- Called once a second. Adds the player's position to the walked trails when they are on
-- foot (or mounted) on ground nobody has recorded yet.
function T.Record()
    if not T.Recording() then endStroke() rec.last = nil return end
    local here = T.PlayerPlace()
    if not here or call("UnitOnTaxi", "player") or call("UnitIsDeadOrGhost", "player") then
        endStroke()
        rec.last = nil
        return
    end
    local last = rec.last
    if not last or last.c ~= here.c then
        endStroke()
        rec.last = { c = here.c, x = here.x, y = here.y }
        return
    end
    local moved = dist(last, here)
    if moved < RECORD_STEP then return end
    local speed = call("GetUnitSpeed", "player")
    local carried = type(speed) == "number" and speed == 0      -- moving without walking: a boat, zeppelin or lift
    if moved > RECORD_JUMP or carried then
        endStroke()
        rec.last = { c = here.c, x = here.x, y = here.y }
        return
    end
    local known = knownCells(here.c)
    local x, y = math.floor(here.x + 0.5), math.floor(here.y + 0.5)
    local old = isKnown(known, x, y)
    if old and not rec.stroke then                              -- still on ground already recorded
        rec.last = { c = here.c, x = here.x, y = here.y }
        return
    end
    if known.total >= RECORD_CAP then
        if not rec.full then rec.full = true say("Travel has recorded as many walked paths as it keeps for this continent.") end
        return
    end
    local list = trails(here.c)
    if not list then return end
    if not rec.stroke then                                      -- leaving recorded ground: start from the last point on it
        rec.stroke = { math.floor(last.x + 0.5), math.floor(last.y + 0.5) }
        rec.pending = { c = here.c, keys = { [cellKey(rec.stroke[1], rec.stroke[2])] = true } }
        list[#list + 1] = rec.stroke
        known.total = known.total + 1
    end
    local stroke = rec.stroke
    stroke[#stroke + 1], stroke[#stroke + 2] = x, y
    rec.pending.keys[cellKey(x, y)] = true
    known.total, known.fresh = known.total + 1, known.fresh + 1
    rec.last = { c = here.c, x = here.x, y = here.y }
    if old then endStroke() end                            -- joined recorded ground again: the stroke ends here
    if known.fresh >= REBUILD_AFTER then
        known.fresh = 0
        ns.Paths.Reset(here.c)
    end
end

if ns.Paths then ns.Paths.SetWalked(function(c)
    local store = saved()
    return store and type(store.trails) == "table" and store.trails[c] or nil
end) end

local watcher = CreateFrame("Frame")
local sinceRecord = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
    sinceRecord = sinceRecord + elapsed
    if sinceRecord >= 1 then
        sinceRecord = 0
        pcall(T.Record)
    end
end)
for _, event in ipairs({ "TAXIMAP_OPENED", "PLAYER_ENTERING_WORLD", "USER_WAYPOINT_UPDATED", "PLAYER_CONTROL_GAINED" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event)
    if event == "TAXIMAP_OPENED" then
        local ok, read = pcall(T.ScanTaxi)
        if ok and read and read > 0 and T.trip then pcall(T.Replan, true) end
    elseif event == "USER_WAYPOINT_UPDATED" then
        pcall(T.PinChanged)
    elseif T.trip then
        if event == "PLAYER_ENTERING_WORLD" then pcall(T.Replan, true) else pcall(T.Tick) end
    end
end)

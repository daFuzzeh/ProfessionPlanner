local _, ns = ...

-- Paths: finds a walkable trail between two spots on one continent over the path points in
-- TravelPaths.lua (worked out from the game's terrain: around mountains, along roads). No game
-- calls in here. Positions are world yards: x grows north, y grows west.

local P = {}
ns.Paths = P

local BUCKET = 250        -- yards per cell of the lookup grid
local JOIN = 600          -- a spot further than this from every path point has no trail
local OFF_PATH = 1.6      -- walking to and from the network counts this much slower
local FASTEST = 0.35 / 7  -- seconds per yard on the cheapest ground (a walked trail): keeps the search honest

local WALKED = 0.35 / 7   -- seconds per yard on a trail somebody actually walked: preferred over a road
local LINK = 30           -- a walked point this close to another path point is joined to it

local built = {}
local walkedSource        -- function(c) -> list of strokes { x1, y1, x2, y2, ... } recorded on this client

-- The recorder hands over what the player has walked; it is merged into the path points.
function P.SetWalked(source) walkedSource = source end

local function prepare(c)
    if built[c] ~= nil then return built[c] end
    local raw = ns.TravelPaths and ns.TravelPaths[c]
    local strokes = {}
    for _, stroke in ipairs(raw and raw.walked or {}) do strokes[#strokes + 1] = stroke end
    for _, stroke in ipairs(walkedSource and walkedSource(c) or {}) do strokes[#strokes + 1] = stroke end
    if (not raw or #raw.x == 0) and #strokes == 0 then built[c] = false return false end
    local x, y = raw and raw.x or {}, raw and raw.y or {}
    local count = #x
    if #strokes > 0 then            -- the shipped tables stay as they are
        local cx, cy = {}, {}
        for i = 1, count do cx[i], cy[i] = x[i], y[i] end
        x, y = cx, cy
    end
    local first, nextLink, target, secs = {}, {}, {}, {}
    local links = raw and raw.links or {}
    local n = 0
    local function add(a, b, s)
        n = n + 1
        target[n], secs[n], nextLink[n] = b, s, first[a]
        first[a] = n
    end
    for i = 1, #links, 3 do
        local a, b, s = links[i], links[i + 1], links[i + 2]
        if a >= 1 and a <= count and b >= 1 and b <= count then
            add(a, b, s)
            add(b, a, s)
        end
    end
    local cells = {}
    local function file(i)
        local key = math.floor(x[i] / BUCKET) * 4096 + math.floor(y[i] / BUCKET)
        local cell = cells[key]
        if not cell then cell = {} cells[key] = cell end
        cell[#cell + 1] = i
    end
    for i = 1, count do
        if first[i] then file(i) end
    end
    -- Walked strokes: each is a chain of new points, joined to whatever was already there.
    local function join(i, before)
        local bx, by = math.floor(x[i] / BUCKET), math.floor(y[i] / BUCKET)
        local best, bestD
        for dx = -1, 1 do
            for dy = -1, 1 do
                for _, id in ipairs(cells[(bx + dx) * 4096 + by + dy] or {}) do
                    if id < before then
                        local d = math.sqrt((x[id] - x[i]) ^ 2 + (y[id] - y[i]) ^ 2)
                        if d <= LINK and (not bestD or d < bestD) then best, bestD = id, d end
                    end
                end
            end
        end
        if best then
            local s = math.max(bestD, 1) / 7
            add(i, best, s)
            add(best, i, s)
        end
    end
    for _, stroke in ipairs(strokes) do
        local start = #x + 1
        for at = 1, #stroke - 1, 2 do
            local i = #x + 1
            x[i], y[i] = stroke[at], stroke[at + 1]
            if i > start then
                local s = math.max(math.sqrt((x[i] - x[i - 1]) ^ 2 + (y[i] - y[i - 1]) ^ 2), 1) * WALKED
                add(i, i - 1, s)
                add(i - 1, i, s)
            end
        end
        local last = #x
        for i = start, last do
            if i == start or i == last or (i - start) % 4 == 0 then join(i, start) end
        end
        for i = start, last do file(i) end
    end
    built[c] = { x = x, y = y, names = raw and raw.names or {}, first = first, next = nextLink, target = target, secs = secs, cells = cells }
    return built[c]
end

-- Forget the prepared lookups (after the path data is replaced).
function P.Reset(c)
    if c then built[c] = nil else built = {} end
end

function P.Has(c) return prepare(c) and true or false end

-- Up to `limit` path points nearest to a spot, closest first: { id, yards }.
local function nearest(g, x, y, limit)
    local found = {}
    local cx, cy = math.floor(x / BUCKET), math.floor(y / BUCKET)
    for ring = 0, 2 do
        for dx = -ring, ring do
            for dy = -ring, ring do
                if math.max(math.abs(dx), math.abs(dy)) == ring then
                    local cell = g.cells[(cx + dx) * 4096 + cy + dy]
                    if cell then
                        for _, id in ipairs(cell) do
                            local ddx, ddy = g.x[id] - x, g.y[id] - y
                            local d = math.sqrt(ddx * ddx + ddy * ddy)
                            if d <= JOIN then found[#found + 1] = { id, d } end
                        end
                    end
                end
            end
        end
        if #found >= limit and ring >= 1 then break end
    end
    table.sort(found, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
    for i = #found, limit + 1, -1 do found[i] = nil end
    return found
end

-- A small binary heap of { priority, id }.
local function push(heap, priority, id)
    local at = #heap + 1
    heap[at] = { priority, id }
    while at > 1 do
        local up = math.floor(at / 2)
        if heap[up][1] <= heap[at][1] then break end
        heap[up], heap[at] = heap[at], heap[up]
        at = up
    end
end

local function pop(heap)
    local top, size = heap[1], #heap
    heap[1] = heap[size]
    heap[size] = nil
    size = size - 1
    local at = 1
    while true do
        local left, right, low = at * 2, at * 2 + 1, at
        if left <= size and heap[left][1] < heap[low][1] then low = left end
        if right <= size and heap[right][1] < heap[low][1] then low = right end
        if low == at then break end
        heap[low], heap[at] = heap[at], heap[low]
        at = low
    end
    return top
end

-- The trail from (ax, ay) to (bx, by) on continent c: a list of { x =, y =, name = } ending at
-- the goal, without the start. nil when no path points serve the trip (walk the straight line).
-- Also returns the seconds along the path points, and true when the path points only cover
-- the first part of the trip (the rest is a straight line).
function P.Find(c, ax, ay, bx, by)
    local g = prepare(c)
    if not g then return nil end
    local straight = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
    if straight < 120 then return nil end
    local starts, goals = nearest(g, ax, ay, 10), nearest(g, bx, by, 10)
    if #starts == 0 then return nil end
    if #goals > 0 and starts[1][2] + goals[1][2] >= straight then return nil end

    local tail = {}
    for _, goal in ipairs(goals) do tail[goal[1]] = goal[2] * OFF_PATH / 7 end
    local best, from, heap, closed = {}, {}, {}, {}
    local function ahead(id)
        local dx, dy = g.x[id] - bx, g.y[id] - by
        return math.sqrt(dx * dx + dy * dy) * FASTEST
    end
    for _, start in ipairs(starts) do
        local cost = start[2] * OFF_PATH / 7
        if not best[start[1]] or cost < best[start[1]] then
            best[start[1]] = cost
            push(heap, cost + ahead(start[1]), start[1])
        end
    end
    local GOAL = 0
    local last
    while #heap > 0 do
        local id = pop(heap)[2]
        if id == GOAL then last = from[GOAL] break end
        if not closed[id] then
            closed[id] = true
            local cost = best[id]
            if tail[id] then
                local total = cost + tail[id]
                if not best[GOAL] or total < best[GOAL] then
                    best[GOAL], from[GOAL] = total, id
                    push(heap, total, GOAL)
                end
            end
            local link = g.first[id]
            while link do
                local to = g.target[link]
                if not closed[to] then
                    local total = cost + g.secs[link]
                    if not best[to] or total < best[to] then
                        best[to], from[to] = total, id
                        push(heap, total + ahead(to), to)
                    end
                end
                link = g.next[link]
            end
        end
    end
    local partial = false
    if not last then
        -- The path points do not reach the goal (a bridge, tunnel or city the terrain does not
        -- show). Take them as far as they help: the reached point from which the rest is shortest.
        local low
        for id, cost in pairs(best) do
            if closed[id] then
                local dx, dy = g.x[id] - bx, g.y[id] - by
                local rest = math.sqrt(dx * dx + dy * dy)
                local score = cost + rest * 3 / 7
                if rest < straight * 0.7 and (not low or score < low) then low, last = score, id end
            end
        end
        if not last then return nil end
        partial = true
    end

    local ids = {}
    while last do
        table.insert(ids, 1, last)
        last = from[last]
    end
    local trail = {}
    for _, id in ipairs(ids) do trail[#trail + 1] = { x = g.x[id], y = g.y[id], name = g.names[id] } end
    -- Do not walk back to the first point when the second is as easy to reach, nor overshoot the goal.
    while #trail >= 2 do
        local d1 = math.sqrt((trail[1].x - ax) ^ 2 + (trail[1].y - ay) ^ 2)
        local d2 = math.sqrt((trail[2].x - ax) ^ 2 + (trail[2].y - ay) ^ 2)
        local hop = math.sqrt((trail[1].x - trail[2].x) ^ 2 + (trail[1].y - trail[2].y) ^ 2)
        if d2 < hop and d1 < 60 then table.remove(trail, 1) else break end
    end
    local finish = trail[#trail]
    if not finish or math.sqrt((finish.x - bx) ^ 2 + (finish.y - by) ^ 2) > 5 then
        trail[#trail + 1] = { x = bx, y = by }
    end
    return trail, partial and best[ids[#ids]] or best[GOAL], partial
end

-- How far a spot is from the line between two points.
function P.FromSegment(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len = dx * dx + dy * dy
    local t = len > 0 and ((px - ax) * dx + (py - ay) * dy) / len or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local cx, cy = ax + dx * t, ay + dy * t
    return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2), t
end

local COMPASS = { "north", "north-west", "west", "south-west", "south", "south-east", "east", "north-east" }

-- Compass word for the way from one spot to another.
function P.Compass(ax, ay, bx, by)
    local angle = math.atan2(by - ay, bx - ax)          -- 0 = north, growing towards west
    local index = math.floor(angle / (math.pi / 4) + 0.5) % 8
    return COMPASS[index + 1]
end

-- What the walker does at point b coming from a and leaving for c: nil for straight on.
function P.Turn(ax, ay, bx, by, cx, cy)
    local turn = math.atan2(cy - by, cx - bx) - math.atan2(by - ay, bx - ax)
    while turn > math.pi do turn = turn - 2 * math.pi end
    while turn < -math.pi do turn = turn + 2 * math.pi end
    local size = math.abs(turn)
    if size < math.pi / 7 then return nil end
    local side = turn > 0 and "left" or "right"
    if size < math.pi / 3 then return "bear " .. side end
    if size < math.pi * 0.7 then return "turn " .. side end
    return "turn sharp " .. side
end

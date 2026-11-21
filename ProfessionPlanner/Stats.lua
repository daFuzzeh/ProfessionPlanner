local addonName, ns = ...

-- Tracking: what crafting actually cost and gave, per character and profession, for this
-- session and for all time. Three things are counted:
--   crafts        a profession spell the player finished casting
--   skill points  rises in the game's own skill list
--   gold          the materials a craft uses and what its product sells back for, at the
--                 prices of that moment (not the wallet: recipes and training are left out)
-- Each craft also adds its chance of a skill point to "expected", so points gained can be
-- compared with the average for those crafts.

-- A craft and its skill point arrive as separate events in no fixed order; they are paired
-- when they fall within this many seconds of each other.
local WINDOW = 3

local state = { session = {}, last = {}, pending = {}, levels = nil, caps = {} }
ns.StatsState = state

local function clock()
    local read = rawget(_G, "GetTime")
    if type(read) == "function" then
        local ok, value = pcall(read)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

local function today()
    local read = rawget(_G, "time")
    if type(read) == "function" then
        local ok, value = pcall(read)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

local function blank()
    return { points = 0, crafts = 0, expected = 0, mats = 0, back = 0, since = today(), recipes = {} }
end

-- The logged-in character, named the way the rest of the addon names characters.
function ns.StatsCharacter()
    local profile = ns.profile
    if profile and profile.currentId then return profile.currentId end
    return ns.current and ns.current.name or "Unknown"
end

local function saved()
    if not ns.DB then return nil end
    if type(ns.DB.stats) ~= "table" then ns.DB.stats = {} end
    return ns.DB.stats
end

local function bucket(root, char, prof, create)
    if not root or not char or not prof then return nil end
    local mine = root[char]
    if type(mine) ~= "table" then
        if not create then return nil end
        mine = {}
        root[char] = mine
    end
    local found = mine[prof]
    if type(found) ~= "table" and create then
        found = blank()
        mine[prof] = found
    end
    if type(found) == "table" and type(found.recipes) ~= "table" then found.recipes = {} end
    return type(found) == "table" and found or nil
end

local function row(into, spell)
    local found = into.recipes[spell]
    if type(found) ~= "table" then
        found = { crafts = 0, points = 0, expected = 0, mats = 0, back = 0 }
        into.recipes[spell] = found
    end
    return found
end

-- Runs `change` on this session's record and on the saved one.
local function both(prof, change)
    local char = ns.StatsCharacter()
    change(bucket(state.session, char, prof, true))
    local kept = bucket(saved(), char, prof, true)
    if kept then change(kept) end
end

local bySpell
function ns.RecipeBySpell(spell)
    if not bySpell then
        if not ns.D then return nil end
        bySpell = {}
        for _, recipe in ipairs(ns.D.recipes) do bySpell[recipe.spell] = recipe end
    end
    return bySpell[spell]
end

-- What one craft uses and gives back, valued the way the route values it.
local function craftValue(recipe)
    local request = ns.request or {}
    local credit = request.credit
    if credit ~= "none" and credit ~= "ah" then credit = "vendor" end
    local ctx = { D = ns.D, prices = ns.prices, ahmode = request.ahMode == "min" and "min" or "median", credit = credit, unitCache = {} }
    local mats, back = 0, 0
    for _, reagent in ipairs(recipe.reagents or {}) do
        mats = mats + reagent.qty * (ns.UnitCost(ctx, reagent.item) or 0)
    end
    for _, product in ipairs(recipe.products or {}) do
        back = back + (ns.SellValue(ctx, product.item, product.qty))
    end
    return mats, back
end

-- A finished cast. Anything that is not a known profession recipe is ignored.
function ns.RecordCraft(spell)
    local recipe = type(spell) == "number" and ns.RecipeBySpell(spell) or nil
    if not recipe or not ns.DB then return false end
    local prof, at = recipe.prof, clock()
    -- A skill point that arrived just before this event belongs to this craft.
    local waiting = state.pending[prof]
    local took = false
    if waiting and waiting.count > 0 and at - waiting.at <= WINDOW then
        waiting.count = waiting.count - 1
        took = true
    end
    local level = state.levels and state.levels[prof] or nil
    if level and took then level = level - 1 end
    local chance = 0
    if level and not (state.caps[prof] and state.caps[prof] > 0 and level >= state.caps[prof]) then
        chance = ns.SkillChance(recipe, level)
    end
    local mats, back = craftValue(recipe)
    both(prof, function(into)
        local mine = row(into, spell)
        into.crafts, mine.crafts = into.crafts + 1, mine.crafts + 1
        into.expected, mine.expected = into.expected + chance, mine.expected + chance
        into.mats, mine.mats = into.mats + mats, mine.mats + mats
        into.back, mine.back = into.back + back, mine.back + back
        if took then mine.points = mine.points + 1 end
    end)
    state.last[prof] = { spell = spell, at = at, credited = took }
    return true
end

-- Compares the game's skill list with the last reading and counts the rises.
function ns.ScanSkills()
    if not ns.DB or not ns.D then return end
    local live = ns.ReadLiveSkills()
    if not state.levels then state.levels = {} end
    local at = clock()
    for prof, skill in pairs(live) do
        local before = state.levels[prof]
        state.levels[prof] = skill.level
        state.caps[prof] = skill.maxLevel
        -- The first reading of a profession is only a starting point.
        if before and skill.level > before then
            local gained = skill.level - before
            both(prof, function(into) into.points = into.points + gained end)
            for _ = 1, gained do
                local last = state.last[prof]
                if last and not last.credited and at - last.at <= WINDOW then
                    last.credited = true
                    both(prof, function(into)
                        local mine = row(into, last.spell)
                        mine.points = mine.points + 1
                    end)
                else
                    local waiting = state.pending[prof]
                    if not waiting or at - waiting.at > WINDOW then
                        waiting = { count = 0, at = at }
                        state.pending[prof] = waiting
                    end
                    waiting.count, waiting.at = waiting.count + 1, at
                end
            end
        end
    end
end

-- Session and all-time records for a character and profession; either may be nil.
function ns.StatsFor(char, prof)
    return bucket(state.session, char, prof, false), bucket(saved(), char, prof, false)
end

-- scope "session" clears this session's record; anything else clears both.
function ns.ResetStats(char, prof, scope)
    if state.session[char] then state.session[char][prof] = nil end
    local kept = saved()
    if scope ~= "session" and kept and type(kept[char]) == "table" then kept[char][prof] = nil end
end

-- Net cost, cost per point gained, cost per point expected, and luck (points gained as a
-- share of the points expected). Values that cannot be worked out are nil.
function ns.StatsFigures(record)
    local net = record.mats - record.back
    local per = record.points > 0 and net / record.points or nil
    local planned = record.expected > 0 and net / record.expected or nil
    local luck = record.expected > 0 and record.points / record.expected or nil
    return net, per, planned, luck
end

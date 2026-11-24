local addonName, ns = ...

ns.MAX_SKILL = 300
ns.MIN_RUN = 4
ns.MIN_CHANCE = 0.25
-- A grind below MIN_CHANCE is still used when it costs less than GRIND_RATIO of the best normal recipe per point
-- (measured at full price), but never below GRIND_FLOOR: ten crafts a point is the limit whatever it saves.
ns.GRIND_RATIO = 0.25
ns.GRIND_FLOOR = 0.10
-- The per-point route replaces the low-swap route only when it costs under this share of it.
ns.SWAP_MARGIN = 0.95
ns.STOCK_SHADOW = 0.25
ns.BASIC_FOCUS = { Anvil = true, Forge = true, ["Cooking Fire"] = true }
ns.CAP_NOTES = {
    [75] = "Train Journeyman to go past 75 (character level 10; you can train from skill 50).",
    [150] = "Train Expert to go past 150 (character level 20; you can train from skill 125).",
    [225] = "Train Artisan to go past 225 (character level 35; you can train from skill 200).",
}

local vendorList = {
    3371, 3372, 8925, 18256,
    2320, 2321, 4291, 8343, 14341,
    2604, 2605, 4341, 6260, 4342, 4340, 2325, 6261,
    4289, 2880, 3466, 6217, 4470, 11291,
    159, 1179, 2894, 2678, 2692, 3713, 10284,
    4399, 4400,
    4357, 4364, 4377,
}

function ns.SkillChance(recipe, skill)
    if skill < recipe.yellow then return 1.0 end
    if skill >= recipe.grey or recipe.grey <= recipe.yellow then return 0.0 end
    return (recipe.grey - skill) / (recipe.grey - recipe.yellow)
end

function ns.Colour(recipe, skill)
    -- Green starts at the whole-number midpoint, as the game shows it (yellow 50, grey 75: green from 62).
    local mid = recipe.mid or math.floor((recipe.yellow + recipe.grey) / 2)
    if skill < recipe.yellow then return "orange" end
    if skill < mid then return "yellow" end
    if skill < recipe.grey then return "green" end
    return "grey"
end

function ns.PrepareData()
    local raw = ns.RawData
    local data = { build = raw.build, items = raw["items"], recipes = raw.recipes, by_prof = {}, by_spell = {}, vendor = {} }
    for _, recipe in ipairs(data.recipes) do
        recipe.mid = math.floor((recipe.yellow + recipe.grey) / 2)
        -- A list: two spells are filed under more than one profession.
        if not data.by_spell[recipe.spell] then data.by_spell[recipe.spell] = {} end
        table.insert(data.by_spell[recipe.spell], recipe)
        if not data.by_prof[recipe.prof] then data.by_prof[recipe.prof] = {} end
        table.insert(data.by_prof[recipe.prof], recipe)
    end
    for _, itemId in ipairs(vendorList) do
        local item = data["items"][itemId]
        if item and (item.buy or 0) > 0 then data.vendor[itemId] = item.buy / (item.stack or 1) end
    end
    ns.D = data
    return data
end

-- 345 reagents/products referenced by recipes have no embedded item record. Ask the client
-- for those names; it answers from its item cache and may not know an item it has never seen.
local function clientItemName(itemId)
    local lookup = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(lookup) ~= "function" then return nil end
    local ok, name = pcall(lookup, itemId)
    if ok and type(name) == "string" and name ~= "" then return name end
    return nil
end

function ns.HasItemName(data, itemId)
    local item = data["items"][itemId]
    if item and item.name then return true end
    return clientItemName(itemId) ~= nil
end

function ns.ItemName(data, itemId)
    local item = data["items"][itemId]
    if item and item.name then return item.name end
    return clientItemName(itemId) or ("Item " .. itemId)
end

-- Whether a recipe is sold for gold by a vendor this faction can reach, judged from the
-- acquisition text. Vendor-sold entries read "<Kind> <price>: <vendor>, <zone>[ (A|H)]; ..."
-- (Pattern/Plans/Formula/Schematic/Recipe) or just "Vendor". Reputation, quest, drop and
-- currency sources ("Schematic for 45 Merchant's Favor: ...") do not match.
function ns.VendorAccess(source, faction)
    if type(source) ~= "string" then return false, nil end
    if string.lower(source) == "vendor" then return true, nil end
    local vendors = string.match(source, "^%a+ %d[%dgsc ]*: (.+)$")
    if not vendors then return false, nil end
    local mine = (faction == "Horde" and "H") or (faction == "Alliance" and "A") or nil
    if not mine then return true, nil end
    -- A truncated list ("... and 2 more") hides vendors we cannot judge; assume one is reachable.
    if string.find(vendors, " and %d+ more") then return true, nil end
    for vendor in string.gmatch(vendors .. ";", "%s*(.-)%s*;") do
        local tag = string.match(vendor, "%((%a)%)$")
        if vendor ~= "" and (not tag or tag == mine) then return true, nil end
    end
    return false, "sold only by the other faction's vendors"
end

-- The acquisition text with the other faction's vendors left out, for showing to the player.
-- "Recipe 8s: A, Loch Modan (A); B, Duskwood; C, The Barrens (H)" reads, for Horde,
-- "Recipe 8s: B, Duskwood; C, The Barrens". Text without faction tags is returned unchanged.
function ns.SourceForFaction(source, faction)
    if type(source) ~= "string" then return source end
    local mine = (faction == "Horde" and "H") or (faction == "Alliance" and "A") or nil
    if not mine or not string.find(source, "%([AH]%)") then return source end
    local head, list = string.match(source, "^(.-: )(.+)$")
    if not head then head, list = "", source end
    local more = string.match(list, "( and %d+ more)$") or ""
    if more ~= "" then list = string.sub(list, 1, #list - #more) end
    local kept, total = {}, 0
    list = string.gsub(list, " or ", "; ")
    for vendor in string.gmatch(list .. ";", "%s*(.-)%s*;") do
        if vendor ~= "" then
            total = total + 1
            local tag = string.match(vendor, "%((%a)%)$")
            if not tag or tag == mine then
                table.insert(kept, (string.gsub(vendor, "%s*%(%a%)$", "")))
            end
        end
    end
    if #kept == 0 then return source end
    return head .. table.concat(kept, "; ") .. more
end

-- Whether trainers teach a recipe, judged from the acquisition text ("Trainer, 50c, learn at 15").
-- Forever also has a teaching item for many trainer recipes; having one does not mean the
-- recipe has to be bought.
function ns.TrainerTaught(recipe)
    -- Read from a trainer's window in this game: nothing says it more surely.
    if recipe and recipe.seen then return true end
    local source = recipe and recipe.source
    return type(source) == "string" and string.find(string.lower(source), "^trainer") ~= nil
end

-- Trainer learn ranks ---------------------------------------------------------
-- The server decides the skill a trainer asks for a recipe; the client's tables do not hold
-- it. The shipped ranks are second-hand (some are marked unconfirmed), so whatever a trainer
-- window in the game shows replaces them. Kept in the saved variables, account-wide.

-- The recipe a trainer service teaches, or nil when the name fits none, or several that
-- cannot be told apart.
function ns.TrainerRecipe(prof, name)
    local found, taught = {}, {}
    for _, recipe in ipairs(ns.D and ns.D.by_prof[prof] or {}) do
        if recipe.name == name then
            table.insert(found, recipe)
            if ns.TrainerTaught(recipe) then table.insert(taught, recipe) end
        end
    end
    if #found == 1 then return found[1] end
    -- Namesakes: only the one already known to be trainer-taught can be meant.
    if #taught == 1 then return taught[1] end
    return nil
end

local function wholeRank(value)
    if type(value) ~= "number" or value < 1 or value > ns.MAX_SKILL then return nil end
    return math.floor(value)
end

-- Put the ranks read from trainer windows over the shipped ones. `seen` is
-- spell -> { rank = n }. What was shipped is kept in recipe.shipped.
function ns.ApplyTrainerRanks(seen)
    if not ns.D or type(seen) ~= "table" then return 0 end
    local applied = 0
    for spell, entry in pairs(seen) do
        local rank = type(entry) == "table" and wholeRank(entry.rank) or nil
        for _, recipe in ipairs(rank and ns.D.by_spell[tonumber(spell) or 0] or {}) do
            if recipe.shipped == nil then
                recipe.shipped = { learn = recipe.learn, learnSrc = recipe.learnSrc, unconfirmed = recipe.unconfirmed, auto = recipe.auto }
            end
            recipe.learn, recipe.learnSrc, recipe.approx, recipe.unconfirmed, recipe.seen = rank, "Trainer (read in game)", false, nil, true
            -- A recipe that comes with the profession needs no skill; a trainer asking for some teaches it.
            if rank > 1 then recipe.auto = false end
            applied = applied + 1
        end
    end
    return applied
end

-- `services` is what one trainer window lists: { name =, skill =, rank = } each. Stores the
-- ranks in `store` and returns how many are new or changed, and how many of those differ
-- from what the planner was using.
function ns.RecordTrainerRanks(store, services, npc, now)
    local fresh, differ, changed = 0, 0, {}
    if not ns.D or type(store) ~= "table" then return fresh, differ, changed end
    for _, service in ipairs(services or {}) do
        local rank = wholeRank(service.rank)
        if rank and type(service.name) == "string" and type(service.skill) == "string" and ns.D.by_prof[service.skill] then
            local recipe = ns.TrainerRecipe(service.skill, service.name)
            -- A rank past the point where the recipe turns grey is some other recipe's.
            if recipe and not ((recipe.grey or 0) > 0 and rank > recipe.grey) then
                local old = store[recipe.spell]
                if type(old) ~= "table" or old.rank ~= rank then
                    fresh = fresh + 1
                    if recipe.learn ~= rank then
                        differ = differ + 1
                        table.insert(changed, { name = recipe.name, rank = rank, was = recipe.learn, spell = recipe.spell })
                    end
                end
                store[recipe.spell] = { rank = rank, npc = npc, at = now }
            end
        end
    end
    return fresh, differ, changed
end

-- A trainer that does not offer a recipe ------------------------------------
-- A shipped rank that no trainer has confirmed can be wrong in a way that matters: the recipe
-- may be taught at a higher skill than the planner thinks. A trainer window that lists other
-- recipes of the profession but not this one, for a character whose skill is already at the
-- shipped rank, shows the rank is too low. The recipe is kept out of routes (ns.Explain) until
-- a trainer lists it. Kept in the saved variables, account-wide:
-- trainerMissing[spell] = { npc = trainer name, skill = character skill, at = time }.

-- "A", "A and B", "A, B and C", "A, B, C and 2 more": three names at most.
function ns.NameList(names)
    local count = #names
    if count <= 1 then return names[1] or "" end
    if count <= 3 then return table.concat(names, ", ", 1, count - 1) .. " and " .. names[count] end
    return names[1] .. ", " .. names[2] .. ", " .. names[3] .. " and " .. (count - 3) .. " more"
end

-- A recipe the character being played learned a moment ago (NEW_RECIPE_LEARNED). TradeSkillMaster only finds
-- out when the profession window is next opened; until then the route would still say to buy or learn it.
-- Kept for the session: by the next login TSM has it, or the profession was dropped.
ns.learnedNow = {}
function ns.NoteLearned(spell)
    local id = ns.profile and ns.profile.currentId
    if not id or type(spell) ~= "number" then return end
    ns.learnedNow[id] = ns.learnedNow[id] or {}
    ns.learnedNow[id][spell] = true
end

-- Whether TSM says the character being played already knows the recipe.
function ns.PlayedKnows(spell)
    local profile = ns.profile
    local id = profile and profile.currentId
    local char = id and profile.chars and profile.chars[id] or nil
    if not char then return false end
    if ns.learnedNow[id] and ns.learnedNow[id][spell] then return true end
    local name = char.name or string.match(id, "^(.-) %-") or id
    local craft = profile.crafts and profile.crafts[spell] or nil
    return type(craft) == "table" and type(craft.players) == "table" and craft.players[name] == true
end

-- `listed` is every service one trainer window lists: { name =, skill = } (no skill line when the
-- service asks for none). `skills` is profession -> the played character's skill, `knows` a
-- function(spell) -> boolean, `check` false when the window may be hiding recipes (a type
-- filter is off). Recipes the window lists leave `store`; with `check`, the unconfirmed trainer
-- recipes of the profession the window teaches that the character could learn at its skill but
-- the window does not list are put in. Returns the recipes newly put in (or put in again for a
-- different trainer or skill) and how many were taken out.
function ns.RecordTrainerMissing(store, listed, npc, skills, knows, now, check)
    local added, cleared = {}, 0
    if not ns.D or type(store) ~= "table" or type(listed) ~= "table" then return added, cleared end
    local named, loose = {}, {}
    for _, service in ipairs(listed) do
        if type(service.name) == "string" then
            if type(service.skill) == "string" then
                named[service.skill] = named[service.skill] or {}
                named[service.skill][service.name] = true
            else
                -- A service that asks for no skill does not say which profession it belongs to.
                loose[service.name] = true
            end
        end
    end
    local function lists(recipe)
        return loose[recipe.name] == true or (named[recipe.prof] ~= nil and named[recipe.prof][recipe.name] == true)
    end
    for spell in pairs(store) do
        for _, recipe in ipairs(ns.D.by_spell[tonumber(spell) or 0] or {}) do
            if lists(recipe) then
                store[spell] = nil
                cleared = cleared + 1
                break
            end
        end
    end
    if not check then return added, cleared end
    -- The profession is the one the window's services tie to a recipe, as the rank read does.
    local taught = {}
    for _, service in ipairs(listed) do
        if type(service.skill) == "string" and type(service.name) == "string" and ns.D.by_prof[service.skill]
            and ns.TrainerRecipe(service.skill, service.name) then
            taught[service.skill] = true
        end
    end
    local professions = {}
    for prof in pairs(taught) do table.insert(professions, prof) end
    table.sort(professions)
    for _, prof in ipairs(professions) do
        local skill = type(skills) == "table" and skills[prof] or nil
        if type(skill) == "number" then
            for _, recipe in ipairs(ns.D.by_prof[prof]) do
                if ns.TrainerTaught(recipe) and recipe.unconfirmed == true
                    and type(recipe.learn) == "number" and recipe.learn <= skill
                    and not lists(recipe) and not (type(knows) == "function" and knows(recipe.spell)) then
                    local old = store[recipe.spell]
                    if type(old) ~= "table" or old.npc ~= npc or old.skill ~= skill then
                        store[recipe.spell] = { npc = npc, skill = skill, at = now }
                        table.insert(added, recipe)
                    end
                end
            end
        end
    end
    return added, cleared
end

-- The record of a recipe a trainer did not offer, or nil. `store` defaults to the saved one.
function ns.TrainerMissingEntry(spell, store)
    if store == nil then store = ns.DB and ns.DB.trainerMissing or nil end
    local entry = type(store) == "table" and store[spell] or nil
    if type(entry) == "table" then return entry end
    return nil
end

local function missingWho(entry)
    return type(entry.npc) == "string" and entry.npc ~= "" and entry.npc or nil
end

-- Why such a recipe is out of the routes; the planner and the Recipes tab show this one text.
function ns.TrainerMissingReason(entry)
    local skill = tonumber(entry.skill)
    return (missingWho(entry) or "A trainer") .. " did not offer it" .. (skill and (" at skill " .. skill) or "")
        .. ". It returns when a trainer lists it."
end

-- The same, short, for the status column of the Recipes tab.
function ns.TrainerMissingStatus(entry)
    local skill = tonumber(entry.skill)
    local who = missingWho(entry)
    return "Not offered" .. (who and (" by " .. who) or "") .. (skill and (" at skill " .. skill) or "")
end

-- The Learn line of a recipe that trainers teach, with the skill the planner is really using in
-- place of the one in the shipped text ("Trainer, 2s, learn at ~50" -> "Trainer, 2s, from skill
-- 50 (not confirmed yet)"). nil for any other source: those keep their text.
function ns.TrainerLearnText(source, learn, learnSrc, unconfirmed, spell)
    if type(source) ~= "string" or not string.find(string.lower(source), "^trainer") or type(learn) ~= "number" then return nil end
    local text = string.gsub(source, ",%s*learn at ~?%d+", "")
    text = text .. ", from skill " .. learn
    if learnSrc == "Trainer (read in game)" then
        local read = ns.DB and type(ns.DB.trainerRanks) == "table" and ns.DB.trainerRanks[spell] or nil
        local npc = type(read) == "table" and type(read.npc) == "string" and read.npc ~= "" and read.npc or nil
        return text .. " (read from " .. (npc or "a trainer") .. ")"
    end
    if unconfirmed then return text .. " (not confirmed yet)" end
    return text
end

local function isDiscolored(recipe)
    return string.find(recipe.name, "Discolored Healing Potion", 1, true) ~= nil
end

function ns.NewContext(req, profile, prices)
    if not ns.D then ns.PrepareData() end
    local ctx = {
        D = ns.D, req = req, profile = profile, prices = prices,
        prof = req.prof or "Alchemy", char = req.char,
        ahmode = req.ahMode == "min" and "min" or "median",
        credit = req.credit or "vendor",
        patterns = req.patterns == "buyable" and "buyable" or "known",
        ahPatterns = req.patterns == "buyable",
        vendorPatterns = req.vendorPatterns ~= false,
        -- Vendor recipes sold one at a time are used unless the player turns them off.
        avoidLimited = req.limitedPatterns == false,
        seen = req.vendorSeen or (ns.DB and ns.DB.vendorSeen) or nil,
        trainerMissing = req.trainerMissing or (ns.DB and ns.DB.trainerMissing) or nil,
        faction = req.faction or (profile and profile.faction) or nil,
        cooldowns = req.cooldowns == true, stations = req.stations == true,
        discolored = req.discolored == true, useStock = req.useStock ~= false,
        altStock = req.altStock == true, strict = req.strictCheapest ~= false,
        -- A kept route (see ns.BuildPlan): the recipe for each stretch of skill is fixed, only counts and costs move.
        lock = type(req.lock) == "table" and type(req.lock.steps) == "table" and req.lock or nil,
        known = {}, stock = {}, held = {}, exclude = {}, unitCache = {},
    }
    if not ctx.D.by_prof[ctx.prof] then error("Unknown profession: " .. tostring(ctx.prof)) end
    if ctx.credit ~= "none" and ctx.credit ~= "vendor" and ctx.credit ~= "ah" then ctx.credit = "vendor" end
    for _, spell in ipairs(req.exclude or {}) do ctx.exclude[tonumber(spell)] = true end
    if profile then
        local char = ctx.char and profile.chars[ctx.char]
        if char then
            local baseName = char.name or string.match(ctx.char, "^(.-) %-") or ctx.char
            for spell, craft in pairs(profile.crafts or {}) do
                if craft.players and craft.players[baseName] then ctx.known[tonumber(spell)] = true end
            end
            for spell in pairs(ns.learnedNow[ctx.char] or {}) do ctx.known[spell] = true end
            -- What the character holds, whatever the stock option says: a recipe item bought for the
            -- route is not bought, or charged, a second time.
            for itemId, quantity in pairs(char.stock or {}) do ctx.held[tonumber(itemId) or itemId] = quantity end
            ctx.money = char.money
            local profession = char.profs and char.profs[ctx.prof]
            if profession and (profession.maxLevel or 0) > 0 then ctx.maxLevel = profession.maxLevel end
        end
        if ctx.useStock then
            if ctx.altStock then
                for _, other in pairs(profile.chars or {}) do
                    for itemId, quantity in pairs(other.stock or {}) do
                        local numericId = tonumber(itemId) or itemId
                        ctx.stock[numericId] = (ctx.stock[numericId] or 0) + quantity
                    end
                end
            elseif char then
                for itemId, quantity in pairs(char.stock or {}) do
                    local numericId = tonumber(itemId) or itemId
                    ctx.stock[numericId] = quantity
                end
            end
        end
    end
    return ctx
end

function ns.UnitCost(ctx, itemId)
    local cached = ctx.unitCache[itemId]
    if cached then return cached[1], cached[2] end
    local vendor = ctx.D.vendor[itemId]
    local ah = ctx.prices and ctx.prices.ah(itemId, ctx.ahmode) or nil
    local result
    if vendor and (not ah or vendor <= ah) then
        result = { vendor, "Vendor" }
    elseif ah then
        result = { ah, "AH" }
    else
        result = { nil, nil }
    end
    ctx.unitCache[itemId] = result
    return result[1], result[2]
end

function ns.SellValue(ctx, itemId, quantity)
    local item = ctx.D["items"][itemId]
    local vendor = (item and item.sell or 0) * quantity
    if ctx.credit == "none" then return 0, "none" end
    if ctx.credit == "vendor" then return vendor, "vendor" end
    local record = ctx.prices and ctx.prices.rec(itemId) or nil
    if record and (record.med or 0) >= 200 and (record.spd or 0) >= 3 then
        return 0.95 * record.med * quantity, "AH"
    end
    return vendor, "vendor"
end

function ns.Explain(ctx, recipe)
    if recipe.prof ~= ctx.prof then return nil, "other profession" end
    if ctx.exclude[recipe.spell] then return nil, "avoided by you" end
    if (recipe.cooldown or 0) > 0 and not ctx.cooldowns then return nil, "has a cooldown (option off)" end
    if recipe.focus and not ns.BASIC_FOCUS[recipe.focus] and not ctx.stations then
        return nil, "needs " .. recipe.focus .. " (option off)"
    end
    local known = ctx.known[recipe.spell] == true
    if isDiscolored(recipe) and not (known or ctx.discolored) then
        return nil, "needs the Silverpine quests (option off)"
    end
    if recipe.auto then return { via = "auto" }, nil end
    if known then return { via = "known" }, nil end
    local gone = ctx.trainerMissing and ctx.trainerMissing[recipe.spell]
    if type(gone) == "table" then return nil, ns.TrainerMissingReason(gone) end
    if recipe.learn == nil then return nil, "learn rank unknown" end
    if #(recipe.teachItems or {}) == 0 or ns.TrainerTaught(recipe) then return { via = "trainer" }, nil end
    for _, itemId in ipairs(recipe.teachItems) do
        if (ctx.held[itemId] or 0) > 0 then return { via = "pattern", pattern = { itemId, 0 }, acquisition = "Owned" }, nil end
    end
    local bestItem, bestPrice, acquisition
    local vendorSold, vendorWhy = ns.VendorAccess(recipe.source, ctx.faction)
    local limitedSkipped = false
    if ctx.vendorPatterns and vendorSold then
        for _, itemId in ipairs(recipe.teachItems) do
            local item = ctx.D["items"][itemId]
            if ctx.avoidLimited and ns.VendorStock and ns.VendorStock(recipe.source, itemId, ctx.faction, ctx.seen) then
                limitedSkipped = true
            elseif item and (item.buy or 0) > 0 then
                local price = item.buy / (item.stack or 1)
                if not bestPrice or price < bestPrice then bestItem, bestPrice, acquisition = itemId, price, "Vendor" end
            end
        end
    end
    if ctx.ahPatterns then
        for _, itemId in ipairs(recipe.teachItems) do
            local price = ctx.prices and ctx.prices.ah(itemId, "median") or nil
            if price and (not bestPrice or price < bestPrice) then bestItem, bestPrice, acquisition = itemId, price, "AH" end
        end
    end
    if bestItem then return { via = "pattern", pattern = { bestItem, bestPrice }, acquisition = acquisition }, nil end
    if limitedSkipped then
        return nil, ctx.ahPatterns and "not on the AH; limited-stock vendor recipe (option off)" or "limited-stock vendor recipe (option off)"
    end
    if ctx.ahPatterns then
        if vendorWhy then return nil, "not on the AH; " .. vendorWhy end
        if vendorSold and not ctx.vendorPatterns then return nil, "not on the AH (vendor recipes off)" end
        return nil, "recipe not on the AH"
    end
    if vendorWhy then return nil, vendorWhy end
    if vendorSold then return nil, "vendor recipe (option off)" end
    return nil, "recipe you do not know (AH recipes off)"
end

function ns.CraftCost(ctx, recipe, stock)
    local buy, shadow = 0, 0
    for _, reagent in ipairs(recipe.reagents or {}) do
        local itemId, quantity = reagent.item, reagent.qty
        local have = math.min(stock[itemId] or 0, quantity)
        local need = quantity - have
        local unit = ns.UnitCost(ctx, itemId)
        if need > 0 then
            if not unit then return math.huge, math.huge, 0, math.huge end
            buy = buy + need * unit
        end
        if have > 0 and unit then shadow = shadow + have * unit * ns.STOCK_SHADOW end
    end
    local credit = 0
    for _, product in ipairs(recipe.products or {}) do
        local value = ns.SellValue(ctx, product.item, product.qty)
        credit = credit + value
    end
    return buy - credit, buy, credit, buy + shadow - credit
end

-- ns.CraftCost averaged over the next MIN_RUN crafts, for a recipe the route is not on yet. One leftover
-- material in the bags makes a single craft look nearly free; judged on that one craft the route left its
-- recipe for a full run of something worse (4 green Rough Sharpening Stone for one point, 45 to 46).
function ns.RunCost(ctx, recipe, stock)
    local net, buy, credit, effective = ns.CraftCost(ctx, recipe, stock)
    if effective == math.huge then return net, buy, credit, effective end
    local partly = false
    for _, reagent in ipairs(recipe.reagents or {}) do
        local have = stock[reagent.item] or 0
        if have > 0 and have < reagent.qty * ns.MIN_RUN then partly = true; break end
    end
    if not partly then return net, buy, credit, effective end
    local left = {}
    for _, reagent in ipairs(recipe.reagents or {}) do left[reagent.item] = stock[reagent.item] end
    local netSum, effectiveSum = 0, 0
    for _ = 1, ns.MIN_RUN do
        local oneNet, _, _, oneEffective = ns.CraftCost(ctx, recipe, left)
        netSum, effectiveSum = netSum + oneNet, effectiveSum + oneEffective
        for _, reagent in ipairs(recipe.reagents or {}) do
            local have = left[reagent.item] or 0
            left[reagent.item] = have - math.min(have, reagent.qty)
        end
    end
    return netSum / ns.MIN_RUN, buy, credit, effectiveSum / ns.MIN_RUN
end

-- Why a route cannot go past a skill level: every recipe that would still give a point there,
-- counted by the reason it is out. Returns text such as
-- "recipe not on the AH (158), learn rank unknown (39). Next to learn: Smelt Gold at 155".
function ns.StopReasons(ctx, skill, stock)
    local counts, order = {}, {}
    local unpriced, unpricedOrder = {}, {}
    local nextLearn, nextName
    local function add(reason)
        if not counts[reason] then
            counts[reason] = 0
            table.insert(order, reason)
        end
        counts[reason] = counts[reason] + 1
    end
    local function byCount(tally)
        return function(a, b)
            if tally[a] ~= tally[b] then return tally[a] > tally[b] end
            return tostring(a) < tostring(b)
        end
    end
    for _, recipe in ipairs(ctx.D.by_prof[ctx.prof]) do
        -- Profession rank spells sit in the recipe list with no materials; they are not crafts.
        local craft = recipe.auto or #(recipe.reagents or {}) > 0
        if craft and ns.SkillChance(recipe, skill) * (recipe.skillups or 1) > 0 then
            local availability, why = ns.Explain(ctx, recipe)
            if not availability then
                if recipe.focus and string.find(why, "^needs ") and not string.find(why, "Silverpine", 1, true) then
                    why = "needs a special station (option off)"
                end
                add(why)
            elseif availability.via ~= "known" and availability.via ~= "auto" and recipe.learn > skill then
                if not nextLearn or recipe.learn < nextLearn then nextLearn, nextName = recipe.learn, recipe.name end
                add("cannot be learned yet")
            else
                add("materials have no price")
                for _, reagent in ipairs(recipe.reagents or {}) do
                    local short = reagent.qty - math.min(stock and stock[reagent.item] or 0, reagent.qty)
                    if short > 0 and not ns.UnitCost(ctx, reagent.item) then
                        if not unpriced[reagent.item] then
                            unpriced[reagent.item] = 0
                            table.insert(unpricedOrder, reagent.item)
                        end
                        unpriced[reagent.item] = unpriced[reagent.item] + 1
                    end
                end
            end
        end
    end
    if #order == 0 then return "no recipe gives skill at this level" end
    table.sort(order, byCount(counts))
    local parts = {}
    for index = 1, math.min(4, #order) do
        table.insert(parts, order[index] .. " (" .. counts[order[index]] .. ")")
    end
    local text = table.concat(parts, ", ")
    if #unpricedOrder > 0 then
        table.sort(unpricedOrder, byCount(unpriced))
        local names = {}
        for index = 1, math.min(3, #unpricedOrder) do
            table.insert(names, ns.ItemName(ctx.D, unpricedOrder[index]))
        end
        text = text .. ". No price for: " .. table.concat(names, ", ")
        if #unpricedOrder > 3 then text = text .. " and " .. (#unpricedOrder - 3) .. " more" end
    end
    if nextLearn then text = text .. ". Next to learn: " .. nextName .. " at " .. nextLearn end
    return text
end

local function closeStep(items, step, skill)
    if step then
        step.endSkill = skill
        table.insert(items, step)
    end
end

local NO_STOCK = {}

-- Is `top` enough better than the recipe the route is on to leave it? Ten percent cheaper per point; when both
-- cost nothing, ten percent cheaper at full price; when both pay for themselves even then, a ten percent
-- better skill-up chance. Without the last two a recipe that sold for more than it cost was ridden down to a
-- 25% chance (113 Handstitched Leather Vests for 67 points) while an orange one that also paid sat unused.
local function clearlyBetter(top, entry)
    if top.rank < entry.rank - 0.10 * entry.rank - 1e-9 then return true end
    if entry.rank > 0 or top.rank > 0 then return false end
    if top.fullRank < entry.fullRank - 0.10 * entry.fullRank - 1e-9 then return true end
    if entry.fullRank > 0 or top.fullRank > 0 then return false end
    return entry.expectedPoints < 0.90 * top.expectedPoints - 1e-9
end

-- The stretch of a kept route that covers `skill`, and the stretch after it.
local function lockedPart(lock, skill)
    for index, part in ipairs(lock.steps) do
        if skill >= part.s - 1e-9 and skill < part.e - 1e-9 then return part, lock.steps[index + 1] end
    end
end

local function entryFor(scored, spell)
    for _, entry in ipairs(scored) do
        if entry.spell == spell then return entry end
    end
end

function ns.PlanRoute(ctx, fromSkill, toSkill)
    local stock = {}
    for itemId, quantity in pairs(ctx.stock) do stock[itemId] = quantity end
    local candidates = {}
    for _, recipe in ipairs(ctx.D.by_prof[ctx.prof]) do
        local availability = ns.Explain(ctx, recipe)
        if availability then table.insert(candidates, { recipe = recipe, availability = availability }) end
    end
    local caps = {}
    for _, cap in ipairs({ 75, 150, 225 }) do
        if fromSkill <= cap and cap < toSkill and (not ctx.maxLevel or ctx.maxLevel <= cap) then table.insert(caps, cap) end
    end
    local capIndex = 1
    local items, warnings, boughtPatterns = {}, {}, {}
    local current, step
    local run, crafts, skill = 0, 0, fromSkill + 0.0
    local stoppedAt
    if caps[capIndex] == fromSkill then
        table.insert(items, { type = "note", at = fromSkill, text = ns.CAP_NOTES[fromSkill] })
        capIndex = capIndex + 1
    end
    while skill < toSkill - 1e-9 and crafts < 20000 do
        local integerSkill = math.floor(skill + 1e-9)
        local scored = {}
        local hasDecentChance = false
        for _, candidate in ipairs(candidates) do
            local recipe, availability = candidate.recipe, candidate.availability
            if (availability.via == "known" or availability.via == "auto") or recipe.learn <= integerSkill then
                local expectedPoints = ns.SkillChance(recipe, integerSkill) * recipe.skillups
                if expectedPoints > 0 then
                    local cost = (current and current.recipe.spell == recipe.spell) and ns.CraftCost or ns.RunCost
                    local net, _, _, effective = cost(ctx, recipe, stock)
                    if effective ~= math.huge then
                        local patternCost = 0
                        if availability.pattern and not boughtPatterns[recipe.spell] then
                            local span = math.max(1, math.min(toSkill, recipe.grey) - integerSkill)
                            patternCost = availability.pattern[2] / math.max(1, span / math.max(expectedPoints, 0.3))
                        end
                        local base = ctx.strict and net or effective
                        local perCraft = base + patternCost
                        local entry = {
                            score = perCraft / expectedPoints, grey = recipe.grey,
                            yellow = recipe.yellow, spell = recipe.spell, recipe = recipe,
                            availability = availability, expectedPoints = expectedPoints, perCraft = perCraft,
                            net = net, effective = effective,
                        }
                        -- A craft that pays for itself (own stock is free, or the product sells for more than
                        -- it costs) ranks as free, no better. A negative cost divided by a smaller skill-up
                        -- chance is more negative, which made the worse chance win and sent routes back to a
                        -- recipe that was turning green.
                        entry.rank = math.max(entry.score, 0)
                        -- Among crafts that cost nothing, the one that would be cheapest per point at full
                        -- price goes first: it spends the least of what is in the bags, and the route is the
                        -- same one whether the materials are owned or still to buy.
                        entry.fullRank = entry.rank
                        if entry.rank <= 0 then
                            local full = ns.CraftCost(ctx, recipe, NO_STOCK)
                            entry.fullRank = math.max((full + patternCost) / expectedPoints, 0)
                        end
                        table.insert(scored, entry)
                        if expectedPoints >= ns.MIN_CHANCE then hasDecentChance = true end
                    end
                end
            end
        end
        if #scored == 0 then stoppedAt = integerSkill; break end
        local filtered = scored
        if hasDecentChance then
            -- Low-chance grinds are skipped while a normal recipe exists, unless the grind is far cheaper per
            -- point. Dropping them whatever the price made a route buy a 6g recipe for its last four points.
            local bestDecent = math.huge
            for _, entry in ipairs(scored) do
                if entry.expectedPoints >= ns.MIN_CHANCE and entry.rank < bestDecent then bestDecent = entry.rank end
            end
            filtered = {}
            for _, entry in ipairs(scored) do
                local keep = entry.expectedPoints >= ns.MIN_CHANCE
                if not keep and bestDecent > 0 and entry.expectedPoints >= ns.GRIND_FLOOR then
                    -- The grind is judged at full price: materials already owned must not make a nearly grey
                    -- recipe look free, or the route would burn the bags on it.
                    local full = ns.CraftCost(ctx, entry.recipe, NO_STOCK)
                    local pattern = entry.perCraft - (ctx.strict and entry.net or entry.effective)
                    keep = math.max((full + pattern) / entry.expectedPoints, 0) < ns.GRIND_RATIO * bestDecent
                end
                if keep then table.insert(filtered, entry) end
            end
        end
        table.sort(filtered, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            if a.fullRank ~= b.fullRank then return a.fullRank < b.fullRank end
            -- Equal cost per point: the better skill-up chance (fewer crafts), then the cheaper craft.
            if a.expectedPoints ~= b.expectedPoints then return a.expectedPoints > b.expectedPoints end
            if a.perCraft ~= b.perCraft then return a.perCraft < b.perCraft end
            if a.grey ~= b.grey then return a.grey < b.grey end
            if a.yellow ~= b.yellow then return a.yellow < b.yellow end
            return a.spell < b.spell
        end)
        local top, pick = filtered[1], filtered[1]
        if not ctx.strict and current then
            for _, entry in ipairs(filtered) do
                if entry.spell == current.recipe.spell then
                    if run < ns.MIN_RUN or not clearlyBetter(top, entry) then pick = entry end
                    break
                end
            end
        end
        local part, nextPart
        if ctx.lock then part, nextPart = lockedPart(ctx.lock, skill) end
        if part then
            local kept = entryFor(scored, part.spell)
            -- A kept step ends on a fraction (63.4). Planned again from a whole skill inside that last
            -- fraction, its recipe may have just stopped giving skill; the next kept recipe takes over.
            if not kept and nextPart and part.e - skill < 1 then kept = entryFor(scored, nextPart.spell) end
            if kept then
                pick = kept
            elseif not ctx.lockBroken then
                -- Rounded as the steps on screen are: a stretch kept from 55.6 is shown as starting at 56.
                ctx.lockBroken = { skill = math.floor(skill + 0.5), spell = part.spell }
            end
        end
        local recipe, availability, expectedPoints = pick.recipe, pick.availability, pick.expectedPoints
        if not current or current.recipe.spell ~= recipe.spell then run = 0 end
        run = run + 1
        current = { recipe = recipe, availability = availability }
        if not step or step.spell ~= recipe.spell then
            closeStep(items, step, skill)
            local alternatives = {}
            for _, entry in ipairs(filtered) do
                if entry.spell ~= recipe.spell and #alternatives < 3 then
                    table.insert(alternatives, { spell = entry.spell, name = entry.recipe.name, score = entry.rank })
                end
            end
            step = {
                type = "step", spell = recipe.spell, recipeData = recipe, availability = availability,
                startSkill = skill, crafts = 0, use = {}, stockUsed = {}, buyCost = 0, credit = 0,
                patternCost = 0, colourStart = ns.Colour(recipe, integerSkill), score = pick.rank, alts = alternatives,
            }
            if availability.pattern and not boughtPatterns[recipe.spell] then
                boughtPatterns[recipe.spell] = availability.pattern
                step.patternCost = availability.pattern[2]
                step.patternItem = availability.pattern[1]
            end
        end
        local _, buy, credit = ns.CraftCost(ctx, recipe, stock)
        for _, reagent in ipairs(recipe.reagents or {}) do
            local itemId = reagent.item
            local have = stock[itemId] or 0
            local take = math.min(have, reagent.qty)
            if take > 0 then
                stock[itemId] = have - take
                step.stockUsed[itemId] = (step.stockUsed[itemId] or 0) + take
            end
            step.use[itemId] = (step.use[itemId] or 0) + reagent.qty
        end
        step.crafts = step.crafts + 1
        step.buyCost = step.buyCost + buy
        step.credit = step.credit + credit
        step.colourEnd = ns.Colour(recipe, integerSkill)
        skill = skill + expectedPoints
        crafts = crafts + 1
        local cap = caps[capIndex]
        if cap and skill >= cap then
            skill = cap + 0.0
            closeStep(items, step, skill)
            step = nil
            table.insert(items, { type = "note", at = cap, text = ns.CAP_NOTES[cap] })
            capIndex = capIndex + 1
            current, run = nil, 0
        end
    end
    if skill > toSkill then skill = toSkill + 0.0 end
    closeStep(items, step, skill)
    if stoppedAt then
        table.insert(warnings, "No usable recipe at skill " .. stoppedAt .. ". What still gives skill here is out: "
            .. ns.StopReasons(ctx, stoppedAt, stock) .. ".")
    end
    return items, skill, warnings, boughtPatterns
end

local function sortedMaterialIds(use)
    local ids = {}
    for itemId in pairs(use) do table.insert(ids, itemId) end
    table.sort(ids, function(a, b)
        if use[a] ~= use[b] then return use[a] > use[b] end
        return a < b
    end)
    return ids
end

local function buildPlanSingle(req, profile, prices)
    local ctx = ns.NewContext(req, profile, prices)
    local fromSkill = tonumber(req["from"]) or 1
    local toSkill = tonumber(req.to) or 75
    fromSkill, toSkill = math.floor(fromSkill), math.floor(toSkill)
    if fromSkill < 1 or toSkill > ns.MAX_SKILL or fromSkill >= toSkill then
        error("Skill range must be 1 to " .. ns.MAX_SKILL .. ", with From below To.")
    end
    local items, reached, warnings = ns.PlanRoute(ctx, fromSkill, toSkill)
    -- What ns.BuildPlan needs to keep this route: each recipe with the exact stretch of skill it covers.
    local routeLock = { search = ctx.strict and "strict" or "legacy", steps = {} }
    for _, item in ipairs(items) do
        if item.type == "step" then
            table.insert(routeLock.steps, { spell = item.spell, s = item.startSkill, e = item.endSkill })
        end
    end
    local outSteps, totalNeed, totalStock, patternRows = {}, {}, {}, {}
    local spendPatterns, totalCredit, totalCrafts, previousEnd = 0, 0, 0, fromSkill
    local lastStep
    for _, item in ipairs(items) do if item.type == "step" then lastStep = item end end
    for _, item in ipairs(items) do
        if item.type == "note" then
            table.insert(outSteps, { type = "note", at = item.at, text = item.text })
        else
            local recipe = item.recipeData
            local startSkill = previousEnd
            local endSkill = math.floor((item == lastStep and reached or item.endSkill) + 0.5)
            endSkill = math.max(endSkill, startSkill)
            previousEnd = endSkill
            local materials = {}
            for _, itemId in ipairs(sortedMaterialIds(item.use)) do
                local quantity = item.use[itemId]
                local own = item.stockUsed[itemId] or 0
                local buy = quantity - own
                local unit, sourceName = ns.UnitCost(ctx, itemId)
                table.insert(materials, {
                    item = itemId, name = ns.ItemName(ctx.D, itemId), qty = quantity, own = own, buy = buy,
                    unit = unit and math.floor(unit + 0.5) or nil, src = buy == 0 and "Own stock" or sourceName,
                })
                totalNeed[itemId] = (totalNeed[itemId] or 0) + quantity
                totalStock[itemId] = (totalStock[itemId] or 0) + own
            end
            local stepCost = item.buyCost + item.patternCost - item.credit
            totalCredit = totalCredit + item.credit
            totalCrafts = totalCrafts + item.crafts
            spendPatterns = spendPatterns + item.patternCost
            local product = recipe.products and recipe.products[1] or nil
            local pattern
            if item.patternItem then
                pattern = { item = item.patternItem, name = ns.ItemName(ctx.D, item.patternItem), price = math.floor(item.patternCost + 0.5), src = item.availability.acquisition or "AH" }
                if pattern.src == "Vendor" and ns.VendorStock then
                    pattern.stock = ns.VendorStock(recipe.source, item.patternItem, ctx.faction, ctx.seen)
                end
                table.insert(patternRows, pattern)
            end
            local alternatives = {}
            for _, alternative in ipairs(item.alts) do
                table.insert(alternatives, { spell = alternative.spell, name = alternative.name, delta = math.floor(alternative.score - item.score + 0.5) })
            end
            -- What to do with the crafted items: how the plan counts them, and what the other
            -- outlet would pay, so the player can see where the sell-back comes from.
            local sell
            if product then
                local made = item.crafts * product.qty
                local data = ctx.D["items"][product.item]
                local record = ctx.prices and ctx.prices.rec(product.item) or nil
                local _, how = ns.SellValue(ctx, product.item, product.qty)
                sell = {
                    how = how, made = made,
                    vendor = math.floor((data and data.sell or 0) * made + 0.5),
                    ah = record and (record.med or 0) >= 200 and math.floor(0.95 * record.med * made + 0.5) or nil,
                    perDay = record and record.spd or 0,
                }
            end
            table.insert(outSteps, {
                type = "step", sell = sell, ["from"] = startSkill, to = endSkill, recipe = recipe.name, spell = recipe.spell,
                crafts = item.crafts, safeCrafts = item.crafts,
                band = item.colourStart == item.colourEnd and item.colourStart or (item.colourStart .. " to " .. item.colourEnd),
                via = item.availability.via, learn = recipe.learn, approx = recipe.approx, learnSrc = recipe.learnSrc,
                -- The learn rank is second-hand and has not been read from a trainer in this game.
                unconfirmed = recipe.unconfirmed and item.availability.via ~= "known" and item.availability.via ~= "auto" or nil,
                learnWas = recipe.learnWas,
                source = recipe.source, yields = product and product.qty or 0,
                product = product and ns.ItemName(ctx.D, product.item) or nil,
                productItem = product and product.item or nil,
                tools = recipe.tools, focus = recipe.focus, mats = materials, pattern = pattern,
                cost = math.floor(stepCost + 0.5), credit = math.floor(item.credit + 0.5),
                pay = math.floor(item.buyCost + item.patternCost + 0.5),
                yellow = recipe.yellow, mid = recipe.mid, grey = recipe.grey,
                q = product and (ctx.D["items"][product.item] or {}).q or 1,
                perPoint = math.floor(stepCost / math.max(1, endSkill - startSkill) + 0.5), alts = alternatives,
            })
        end
    end
    local safeNeed = {}
    if req.simulate then safeNeed = ns.SimulateRoute(ctx, outSteps) end
    local shopping, spendMaterials, thinSupply = {}, 0, 0
    for itemId, need in pairs(totalNeed) do
        local own = totalStock[itemId] or 0
        local buy = need - own
        local unit, sourceName = ns.UnitCost(ctx, itemId)
        local cost = unit and buy > 0 and buy * unit or 0
        spendMaterials = spendMaterials + cost
        local record = ctx.prices and ctx.prices.rec(itemId) or nil
        local safeQuantity = math.max(need, safeNeed[itemId] or need)
        local safeBuy = math.max(buy, safeQuantity - (ctx.stock[itemId] or 0))
        local row = {
            item = itemId, name = ns.ItemName(ctx.D, itemId), need = need, own = own, buy = buy,
            unit = unit and math.floor(unit + 0.5) or nil, src = buy == 0 and "Own stock" or sourceName,
            cost = math.floor(cost + 0.5), q = (ctx.D["items"][itemId] or {}).q or 1,
            safeBuy = safeBuy, safeCost = unit and safeBuy > 0 and math.floor(safeBuy * unit + 0.5) or 0,
        }
        row.named = ns.HasItemName(ctx.D, itemId)
        if record and sourceName == "AH" then row.listed = record.qty end
        -- Supply check: the price assumes the whole quantity can be bought at market value.
        -- Fewer listings than units needed means the real cost will be higher (or the item is camped).
        if buy > 0 and sourceName == "AH" and record and record.qty and record.qty < buy then
            local listed = math.floor(record.qty)
            row.thin = true
            if listed <= 0 then
                row.warn = "thin supply: none listed at the last scan, " .. buy .. " needed"
            else
                row.warn = "thin supply: " .. listed .. " listed at the last scan, " .. buy .. " needed"
            end
            thinSupply = thinSupply + 1
        end
        table.insert(shopping, row)
    end
    for _, pattern in ipairs(patternRows) do
        -- A recipe item the character already holds is not on the list to buy.
        if pattern.src ~= "Owned" then
            table.insert(shopping, {
                item = pattern.item, name = pattern.name, need = 1, own = 0, buy = 1, unit = pattern.price,
                src = pattern.src or "AH", cost = pattern.price, pattern = true, safeBuy = 1, safeCost = pattern.price,
                q = (ctx.D["items"][pattern.item] or {}).q or 1, named = ns.HasItemName(ctx.D, pattern.item),
            })
        end
    end
    table.sort(shopping, function(a, b) if a.cost ~= b.cost then return a.cost > b.cost end return a.name < b.name end)
    local spend = spendMaterials + spendPatterns
    local wallet
    if ctx.money then
        local cumulative, affordable = 0, math.floor(reached + 0.5)
        for _, step in ipairs(outSteps) do
            if step.type == "step" then
                local nextCumulative = cumulative + step.pay
                if nextCumulative > ctx.money then
                    local span = nextCumulative - cumulative
                    affordable = span > 0 and step["from"] + math.floor((step.to - step["from"]) * (ctx.money - cumulative) / span) or step["from"]
                    break
                end
                cumulative = nextCumulative
            end
        end
        wallet = { money = ctx.money, affordableTo = affordable, enough = ctx.money >= spend }
    end
    local buyAH, buyVendor, safeSpend, safeCrafts, stockUsed = 0, 0, 0, 0, 0
    for _, row in ipairs(shopping) do
        if row.src == "AH" then buyAH = buyAH + row.cost end
        if row.src == "Vendor" then buyVendor = buyVendor + row.cost end
        safeSpend = safeSpend + row.safeCost
    end
    for _, step in ipairs(outSteps) do if step.type == "step" then safeCrafts = safeCrafts + step.safeCrafts end end
    for _, quantity in pairs(totalStock) do stockUsed = stockUsed + quantity end
    if ctx.prof == "Enchanting" then table.insert(warnings, "Enchants need an item to enchant; its cost is not counted. Rods are tools.") end
    -- A recipe with no materials (Disenchant) still uses up an item the planner cannot price.
    local unpricedInput, warned = {}, {}
    for _, recipe in ipairs(ctx.D.by_prof[ctx.prof]) do
        if #(recipe.reagents or {}) == 0 then unpricedInput[recipe.spell] = recipe.name end
    end
    for _, step in ipairs(outSteps) do
        local name = step.type == "step" and unpricedInput[step.spell]
        if name and not warned[name] then
            warned[name] = true
            table.insert(warnings, name .. " uses up an item each time. Those items are not costed, so this step costs more than shown; press Avoid on it to plan without it.")
        end
    end
    local excluded = {}
    for _, recipe in ipairs(ctx.D.by_prof[ctx.prof]) do
        if ctx.exclude[recipe.spell] then table.insert(excluded, { spell = recipe.spell, name = recipe.name }) end
    end
    return {
        profession = ctx.prof, ["from"] = fromSkill, to = toSkill, reached = math.floor(reached + 0.5),
        steps = outSteps, shopping = shopping,
        tsmString = ns.TSMShoppingString and ns.TSMShoppingString(shopping, req.simulate == true) or "",
        summary = {
            crafts = totalCrafts, spend = math.floor(spend + 0.5), sellBack = math.floor(totalCredit + 0.5),
            net = math.floor(spend - totalCredit + 0.5), spendPatterns = math.floor(spendPatterns + 0.5),
            stockUsed = stockUsed, buyAH = math.floor(buyAH + 0.5), buyVendor = math.floor(buyVendor + 0.5),
            safeSpend = math.floor(safeSpend + 0.5), safeCrafts = safeCrafts, thinSupply = thinSupply,
        },
        wallet = wallet, excluded = excluded, warnings = warnings,
        lock = routeLock, lockBroken = ctx.lockBroken,
        options = { stock = ctx.useStock and next(ctx.stock) ~= nil, char = ctx.char, strictCheapest = ctx.strict,
            vendorPatterns = ctx.vendorPatterns, ahPatterns = ctx.ahPatterns },
        prices = { source = prices and prices.source or "Vendor only" },
    }
end

ns.BuildPlanSingle = buildPlanSingle

local SEARCH_TEXT = { strict = "cheapest per skill point", legacy = "fewest recipe changes" }

-- req.lock (the `lock` of an earlier plan) keeps that route: the same recipes over the same stretches of skill.
-- Bags, gold and skill then only move the counts and the costs. Where a kept recipe can no longer be used the
-- planner chooses freely for that stretch and reports it in plan.lockBroken = { skill, spell, name }.
function ns.BuildPlan(req, profile, prices)
    if type(req.lock) == "table" and type(req.lock.steps) == "table" then
        local keptRequest = {}
        for key, value in pairs(req) do keptRequest[key] = value end
        local legacy = req.lock.search == "legacy"
        keptRequest.strictCheapest = not legacy
        local plan = buildPlanSingle(keptRequest, profile, prices)
        plan.options.strictCheapest = req.strictCheapest ~= false
        plan.options.routeSearch = SEARCH_TEXT[legacy and "legacy" or "strict"]
        plan.locked = true
        if plan.lockBroken then
            -- plan.lock stays the route as it now is, for the caller to keep from here on.
            local rows = ns.D.by_spell[plan.lockBroken.spell]
            plan.lockBroken.name = rows and rows[1] and rows[1].name or nil
        else
            plan.lock = req.lock
        end
        return plan
    end
    local strictPlan = buildPlanSingle(req, profile, prices)
    if req.strictCheapest == false then return strictPlan end
    local legacyRequest = {}
    for key, value in pairs(req) do legacyRequest[key] = value end
    legacyRequest.strictCheapest = false
    local legacyPlan = buildPlanSingle(legacyRequest, profile, prices)
    -- Two routes are built. The one with fewer recipe changes is shown unless the per-point route gets further
    -- or costs at least 5% less. A route that pays for itself counts as free: crafting more of something that
    -- sells is not a cheaper way to level.
    local strictCost, legacyCost = math.max(strictPlan.summary.net, 0), math.max(legacyPlan.summary.net, 0)
    local useLegacy
    if strictPlan.reached ~= legacyPlan.reached then
        useLegacy = legacyPlan.reached > strictPlan.reached
    elseif strictCost > 0 or legacyCost > 0 then
        useLegacy = not (strictCost < ns.SWAP_MARGIN * legacyCost - 1e-9)
    else
        -- Both pay for themselves: the one that needs less gold up front.
        useLegacy = not (strictPlan.summary.spend < ns.SWAP_MARGIN * legacyPlan.summary.spend - 1e-9)
    end
    if useLegacy then
        legacyPlan.options.strictCheapest = true
        legacyPlan.options.routeSearch = SEARCH_TEXT.legacy
        return legacyPlan
    end
    strictPlan.options.routeSearch = SEARCH_TEXT.strict
    return strictPlan
end

function ns.SimulateRoute(ctx, steps)
    local legs = {}
    for _, step in ipairs(steps) do
        if step.type == "step" then
            local recipe
            for _, candidate in ipairs(ctx.D.by_prof[ctx.prof]) do
                if candidate.spell == step.spell then recipe = candidate; break end
            end
            if recipe then table.insert(legs, { recipe = recipe, ["from"] = step["from"], to = step.to, expected = step.crafts, step = step }) end
        end
    end
    local runs, seed = 120, 7
    local perLeg, perItem = {}, {}
    for index = 1, #legs do perLeg[index] = {} end
    local function random()
        seed = (seed * 16807) % 2147483647
        return seed / 2147483647
    end
    for run = 1, runs do
        local needed = {}
        for index, leg in ipairs(legs) do
            local count, skill = 0, leg["from"]
            while skill < leg.to and count < 5000 do
                local chance = ns.SkillChance(leg.recipe, skill)
                if chance <= 0 then break end
                count = count + 1
                if chance >= 1 or random() < chance then skill = skill + leg.recipe.skillups end
            end
            if leg.to <= leg["from"] then count = leg.expected end
            perLeg[index][run] = count
            for _, reagent in ipairs(leg.recipe.reagents or {}) do
                needed[reagent.item] = (needed[reagent.item] or 0) + reagent.qty * count
            end
        end
        for itemId, quantity in pairs(needed) do
            if not perItem[itemId] then perItem[itemId] = {} end
            perItem[itemId][run] = quantity
        end
    end
    local function p90(values)
        table.sort(values)
        return #values > 0 and values[math.floor(0.9 * (#values - 1)) + 1] or 0
    end
    for index, leg in ipairs(legs) do leg.step.safeCrafts = math.max(leg.expected, p90(perLeg[index])) end
    local safeNeed = {}
    for itemId, values in pairs(perItem) do
        for run = 1, runs do values[run] = values[run] or 0 end
        safeNeed[itemId] = p90(values)
    end
    return safeNeed
end

local function itemQuality(data, itemId)
    local item = data["items"][itemId]
    return item and item.q or 1
end

function ns.BuildRecipes(req, profile, prices)
    local ctx = ns.NewContext(req, profile, prices)
    local skill = math.floor(tonumber(req.skill or req["from"]) or 1)
    local rows = {}
    for _, recipe in ipairs(ctx.D.by_prof[ctx.prof]) do
        local availability, why = ns.Explain(ctx, recipe)
        local net, buy = ns.CraftCost(ctx, recipe, {})
        local expectedPoints = ns.SkillChance(recipe, skill) * recipe.skillups
        local product = recipe.products and recipe.products[1] or nil
        local learnable = availability and (availability.via == "known" or availability.via == "auto" or recipe.learn <= skill)
        local reagents = {}
        for _, reagent in ipairs(recipe.reagents or {}) do
            table.insert(reagents, { name = ns.ItemName(ctx.D, reagent.item), qty = reagent.qty })
        end
        table.insert(rows, {
            spell = recipe.spell, name = recipe.name, learn = recipe.learn, yellow = recipe.yellow,
            item = product and product.item or nil,
            mid = recipe.mid, grey = recipe.grey, via = availability and availability.via or nil, why = why,
            pattern = availability and availability.pattern and math.floor(availability.pattern[2] + 0.5) or nil,
            owned = availability and availability.acquisition == "Owned" or nil,
            limited = availability and availability.acquisition == "Vendor" and ns.VendorStock ~= nil
                and ns.VendorStock(recipe.source, availability.pattern[1], ctx.faction, ctx.seen) ~= nil or nil,
            q = product and itemQuality(ctx.D, product.item) or 1,
            mats = buy ~= math.huge and math.floor(buy + 0.5) or nil,
            net = net ~= math.huge and math.floor(net + 0.5) or nil,
            perPoint = expectedPoints > 0 and net ~= math.huge and learnable and math.floor(net / expectedPoints + 0.5) or nil,
            colour = ns.Colour(recipe, skill), now = learnable and expectedPoints > 0 or false,
            reagents = reagents, focus = recipe.focus, cooldown = (recipe.cooldown or 0) > 0,
            source = recipe.source, learnSrc = recipe.learnSrc,
            unconfirmed = recipe.unconfirmed or nil, learnWas = recipe.learnWas,
        })
    end
    table.sort(rows, function(a, b)
        local aLearn, bLearn = a.learn or a.yellow, b.learn or b.yellow
        if aLearn ~= bLearn then return aLearn < bLearn end
        if a.yellow ~= b.yellow then return a.yellow < b.yellow end
        return a.name < b.name
    end)
    return { profession = ctx.prof, skill = skill, rows = rows, prices = { source = prices and prices.source or "Vendor only" } }
end

function ns.BuildSuggest(req, profile, prices)
    local ctx = ns.NewContext(req, profile, prices)
    ctx.useStock, ctx.stock = false, {}
    local skill = math.floor(tonumber(req.skill or req["from"]) or 1)
    local rows, count = {}, 0
    for _, recipe in ipairs(ctx.D.by_prof[ctx.prof]) do
        local availability = ns.Explain(ctx, recipe)
        if availability and availability.via ~= "pattern"
            and (availability.via == "known" or availability.via == "auto" or recipe.learn <= skill)
            and recipe.products and recipe.products[1] and not recipe.enchant then
            local materialCost, priced = 0, true
            for _, reagent in ipairs(recipe.reagents or {}) do
                local unit = ns.UnitCost(ctx, reagent.item)
                if not unit then priced = false; break end
                materialCost = materialCost + unit * reagent.qty
            end
            if priced then
                local product = recipe.products[1]
                local record = ctx.prices and ctx.prices.rec(product.item) or nil
                local item = ctx.D["items"][product.item]
                local vendor = (item and item.sell or 0) * product.qty
                local median, soldPerDay = record and record.med or 0, record and record.spd or 0
                local net, how = vendor, "vendor"
                if record and median >= 200 then net, how = 0.95 * median * product.qty, "AH" end
                local margin = net - materialCost
                local expectedPoints = ns.SkillChance(recipe, skill) * recipe.skillups
                if margin > 0 then
                    count = count + 1
                    table.insert(rows, {
                        recipe = recipe.name, spell = recipe.spell, product = ns.ItemName(ctx.D, product.item), yields = product.qty,
                        item = product.item, q = itemQuality(ctx.D, product.item),
                        mats = math.floor(materialCost + 0.5), sell = math.floor(net + 0.5), sellHow = how,
                        margin = math.floor(margin + 0.5), perDay = math.floor(soldPerDay * 10 + 0.5) / 10,
                        listed = record and record.qty or 0,
                        score = math.floor(margin * math.min(soldPerDay, 20) + 0.5),
                        colour = ns.Colour(recipe, skill), levels = expectedPoints > 0,
                        chance = math.floor(math.min(expectedPoints, 1) * 100 + 0.5) / 100,
                        via = availability.via, both = expectedPoints > 0 and soldPerDay >= 1,
                        source = recipe.source,
                    })
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.margin ~= b.margin then return a.margin > b.margin end
        return a.recipe < b.recipe
    end)
    local top = {}
    for index = 1, math.min(40, #rows) do top[index] = rows[index] end
    return { profession = ctx.prof, skill = skill, rows = top, prices = { source = prices and prices.source or "Vendor only" }, count = count }
end

function ns.BuildOverview(req, profile, prices)
    local rows = {}
    if not profile then return { rows = rows } end
    for charId, char in pairs(profile.chars or {}) do
        for profession, values in pairs(char.profs or {}) do
            if ns.D.by_prof[profession] then
                local level = math.max(1, values.level or 0)
                if level < ns.MAX_SKILL then
                    local target = math.min(ns.MAX_SKILL, (math.floor(level / 75) + 1) * 75)
                    local request = {}
                    for key, value in pairs(req) do request[key] = value end
                    request.char, request.prof, request["from"], request.to, request.exclude = charId, profession, level, target, {}
                    local ok, plan = pcall(ns.BuildPlan, request, profile, prices)
                    if ok then
                        table.insert(rows, {
                            char = char.name or string.match(charId, "^(.-) %-") or charId, charId = charId,
                            prof = profession, ["from"] = level, to = target, reached = plan.reached,
                            spend = plan.summary.spend, net = plan.summary.net,
                        })
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b) if a.char ~= b.char then return a.char < b.char end return a.prof < b.prof end)
    return { rows = rows }
end

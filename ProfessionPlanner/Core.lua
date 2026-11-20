local addonName, ns = ...

ns.MAX_SKILL = 300
ns.MIN_RUN = 4
ns.MIN_CHANCE = 0.25
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
    local mid = recipe.mid or ((recipe.yellow + recipe.grey) / 2.0)
    if skill < recipe.yellow then return "orange" end
    if skill < mid then return "yellow" end
    if skill < recipe.grey then return "green" end
    return "grey"
end

function ns.PrepareData()
    local raw = ns.RawData
    local data = { build = raw.build, items = raw["items"], recipes = raw.recipes, by_prof = {}, vendor = {} }
    for _, recipe in ipairs(data.recipes) do
        recipe.mid = (recipe.yellow + recipe.grey) / 2.0
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
    local source = recipe and recipe.source
    return type(source) == "string" and string.find(string.lower(source), "^trainer") ~= nil
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
        faction = req.faction or (profile and profile.faction) or nil,
        cooldowns = req.cooldowns == true, stations = req.stations == true,
        discolored = req.discolored == true, useStock = req.useStock ~= false,
        altStock = req.altStock == true, strict = req.strictCheapest ~= false,
        known = {}, stock = {}, exclude = {}, unitCache = {},
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
    if recipe.learn == nil then return nil, "learn rank unknown" end
    if #(recipe.teachItems or {}) == 0 or ns.TrainerTaught(recipe) then return { via = "trainer" }, nil end
    local bestItem, bestPrice, acquisition
    local vendorSold, vendorWhy = ns.VendorAccess(recipe.source, ctx.faction)
    if ctx.vendorPatterns and vendorSold then
        for _, itemId in ipairs(recipe.teachItems) do
            local item = ctx.D["items"][itemId]
            if item and (item.buy or 0) > 0 then
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
                    local net, _, _, effective = ns.CraftCost(ctx, recipe, stock)
                    if effective ~= math.huge then
                        local patternCost = 0
                        if availability.pattern and not boughtPatterns[recipe.spell] then
                            local span = math.max(1, math.min(toSkill, recipe.grey) - integerSkill)
                            patternCost = availability.pattern[2] / math.max(1, span / math.max(expectedPoints, 0.3))
                        end
                        local base = ctx.strict and net or effective
                        local entry = {
                            score = (base + patternCost) / expectedPoints, grey = recipe.grey,
                            yellow = recipe.yellow, spell = recipe.spell, recipe = recipe,
                            availability = availability, expectedPoints = expectedPoints,
                        }
                        table.insert(scored, entry)
                        if expectedPoints >= ns.MIN_CHANCE then hasDecentChance = true end
                    end
                end
            end
        end
        if #scored == 0 then stoppedAt = integerSkill; break end
        local filtered = scored
        if hasDecentChance then
            filtered = {}
            for _, entry in ipairs(scored) do
                if entry.expectedPoints >= ns.MIN_CHANCE then table.insert(filtered, entry) end
            end
        end
        table.sort(filtered, function(a, b)
            if a.score ~= b.score then return a.score < b.score end
            if a.grey ~= b.grey then return a.grey < b.grey end
            if a.yellow ~= b.yellow then return a.yellow < b.yellow end
            return a.spell < b.spell
        end)
        local top, pick = filtered[1], filtered[1]
        if not ctx.strict and current then
            for _, entry in ipairs(filtered) do
                if entry.spell == current.recipe.spell then
                    if run < ns.MIN_RUN or not (top.score < entry.score - 0.10 * math.abs(entry.score) - 1e-9) then pick = entry end
                    break
                end
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
                    table.insert(alternatives, { spell = entry.spell, name = entry.recipe.name, score = entry.score })
                end
            end
            step = {
                type = "step", spell = recipe.spell, recipeData = recipe, availability = availability,
                startSkill = skill, crafts = 0, use = {}, stockUsed = {}, buyCost = 0, credit = 0,
                patternCost = 0, colourStart = ns.Colour(recipe, integerSkill), score = pick.score, alts = alternatives,
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
                table.insert(patternRows, pattern)
            end
            local alternatives = {}
            for _, alternative in ipairs(item.alts) do
                table.insert(alternatives, { spell = alternative.spell, name = alternative.name, delta = math.floor(alternative.score - item.score + 0.5) })
            end
            table.insert(outSteps, {
                type = "step", ["from"] = startSkill, to = endSkill, recipe = recipe.name, spell = recipe.spell,
                crafts = item.crafts, safeCrafts = item.crafts,
                band = item.colourStart == item.colourEnd and item.colourStart or (item.colourStart .. " to " .. item.colourEnd),
                via = item.availability.via, learn = recipe.learn, approx = recipe.approx, learnSrc = recipe.learnSrc,
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
        table.insert(shopping, {
            item = pattern.item, name = pattern.name, need = 1, own = 0, buy = 1, unit = pattern.price,
            src = pattern.src or "AH", cost = pattern.price, pattern = true, safeBuy = 1, safeCost = pattern.price,
            q = (ctx.D["items"][pattern.item] or {}).q or 1, named = ns.HasItemName(ctx.D, pattern.item),
        })
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
        options = { stock = ctx.useStock and next(ctx.stock) ~= nil, char = ctx.char, strictCheapest = ctx.strict,
            vendorPatterns = ctx.vendorPatterns, ahPatterns = ctx.ahPatterns },
        prices = { source = prices and prices.source or "Vendor only" },
    }
end

function ns.BuildPlan(req, profile, prices)
    local strictPlan = buildPlanSingle(req, profile, prices)
    if req.strictCheapest == false then return strictPlan end
    local legacyRequest = {}
    for key, value in pairs(req) do legacyRequest[key] = value end
    legacyRequest.strictCheapest = false
    local legacyPlan = buildPlanSingle(legacyRequest, profile, prices)
    local target = tonumber(req.to) or 75
    local useLegacy = false
    if strictPlan.reached < target and legacyPlan.reached > strictPlan.reached then
        useLegacy = true
    elseif legacyPlan.reached == strictPlan.reached and legacyPlan.summary.net < strictPlan.summary.net then
        useLegacy = true
    end
    if useLegacy then
        legacyPlan.options.strictCheapest = true
        legacyPlan.options.routeSearch = "cheapest completed route"
        return legacyPlan
    end
    strictPlan.options.routeSearch = "strict net gold per expected skill point"
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
            q = product and itemQuality(ctx.D, product.item) or 1,
            mats = buy ~= math.huge and math.floor(buy + 0.5) or nil,
            net = net ~= math.huge and math.floor(net + 0.5) or nil,
            perPoint = expectedPoints > 0 and net ~= math.huge and learnable and math.floor(net / expectedPoints + 0.5) or nil,
            colour = ns.Colour(recipe, skill), now = learnable and expectedPoints > 0 or false,
            reagents = reagents, focus = recipe.focus, cooldown = (recipe.cooldown or 0) > 0,
            source = recipe.source, learnSrc = recipe.learnSrc,
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
                        recipe = recipe.name, product = ns.ItemName(ctx.D, product.item), yields = product.qty,
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

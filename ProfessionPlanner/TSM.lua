local addonName, ns = ...

-- TSM integration. Two surfaces are used:
--   * TSM_API (public, documented): prices and listed counts through GetCustomPriceValue.
--   * TradeSkillMasterDB (TSM's own SavedVariables, read-only): roster, gold, stock and
--     scanned recipes. The key layout below matches TSM 4.15.x; it is internal to TSM and
--     is kept in this one file so a TSM change needs a fix in one place only.

local function splitCharacterKey(key)
    local name, suffix = key:match("^(.-) %- (.+)$")
    return name or key, suffix or ""
end

local function addStock(target, rows)
    if type(rows) ~= "table" then return end
    for itemString, quantity in pairs(rows) do
        if type(itemString) == "string" and type(quantity) == "number" then
            local itemId = tonumber(itemString:match("^i:(%d+)"))
            if itemId then target[itemId] = (target[itemId] or 0) + quantity end
        end
    end
end

function ns.CharacterId(current)
    if not current or not current.name or not current.faction or not current.realm then return nil end
    return current.name .. " - " .. current.faction .. " - " .. current.realm
end

local function sameFirstName(name, first)
    return first ~= nil and (name == first or name:sub(1, #first + 1) == first .. " ")
end

-- Which of TSM's "Faction - Realm" groups the logged-in character belongs to, and which
-- character in it they are. TSM does not always file characters under the realm name the
-- client reports: on WoW Forever it uses the ruleset ("Normal", "Hardcore", ...) and adds
-- the surname to the character name. So the character is looked up by name first, and the
-- realm names in `current.realms` are only used when the name alone does not settle it.
-- `found` maps "Name - Faction - Realm" to true for every character TSM has.
function ns.TSMScope(found, current)
    if not current or not current.faction then return nil, nil end
    local lead = current.faction .. " - "
    local exact, loose, any = {}, {}, {}
    local exactCount, looseCount, anyCount = 0, 0, 0
    for charId in pairs(found) do
        local name, suffix = splitCharacterKey(charId)
        if suffix:sub(1, #lead) == lead then
            if not any[suffix] then any[suffix] = true; anyCount = anyCount + 1 end
            if current.name and name == current.name then
                if not exact[suffix] then exact[suffix] = charId; exactCount = exactCount + 1 end
            elseif sameFirstName(name, current.first or current.name) then
                if loose[suffix] == nil then looseCount = looseCount + 1; loose[suffix] = charId else loose[suffix] = false end
            end
        end
    end
    local hinted = {}
    for _, realm in ipairs(current.realms or { current.realm }) do
        if type(realm) == "string" and realm ~= "" then table.insert(hinted, lead .. realm) end
    end
    local function settle(matches, count)
        if count == 1 then
            local suffix, charId = next(matches)
            return suffix, charId or nil
        end
        for _, suffix in ipairs(hinted) do
            if matches[suffix] ~= nil then return suffix, matches[suffix] or nil end
        end
        return nil
    end
    local suffix, charId = settle(exact, exactCount)
    if suffix then return suffix, charId end
    suffix, charId = settle(loose, looseCount)
    if suffix then return suffix, charId end
    for _, candidate in ipairs(hinted) do
        if any[candidate] then return candidate, nil end
    end
    if anyCount == 1 then return (next(any)), nil end
    return hinted[1], nil
end

function ns.ReadTSMProfile(db, current)
    local profile = { chars = {}, crafts = {}, suffixes = {}, faction = current and current.faction or nil }
    if type(db) ~= "table" then return profile end
    local found = {}
    for key, professions in pairs(db) do
        local charId = type(key) == "string" and key:match("^s@(.+)@internalData@playerProfessions$") or nil
        if charId and type(professions) == "table" then found[charId] = true end
    end
    local currentSuffix, currentId = ns.TSMScope(found, current)
    profile.scope = currentSuffix
    for key, professions in pairs(db) do
        local charId = type(key) == "string" and key:match("^s@(.+)@internalData@playerProfessions$") or nil
        if charId and type(professions) == "table" then
            local name, suffix = splitCharacterKey(charId)
            if not currentSuffix or suffix == currentSuffix then
                local base = "s@" .. charId .. "@internalData@"
                local money = db[base .. "money"]
                local char = { name = name, suffix = suffix, profs = {}, stock = {}, onAuction = {},
                    money = type(money) == "number" and money or nil }
                for profession, values in pairs(professions) do
                    if type(values) == "table" then
                        char.profs[profession] = {
                            level = tonumber(values.level) or 0,
                            maxLevel = tonumber(values.maxLevel) or 0,
                            skillId = values.skillId,
                            secondary = values.isSecondary == true,
                        }
                    end
                end
                -- Usable crafting stock is what the character can actually pick up: bags, bank, mail.
                -- Items posted on the auction house are for sale and are tracked separately.
                addStock(char.stock, db[base .. "bagQuantity"])
                addStock(char.stock, db[base .. "bankQuantity"])
                addStock(char.stock, db[base .. "mailQuantity"])
                addStock(char.onAuction, db[base .. "auctionQuantity"])
                profile.chars[charId] = char
                profile.suffixes[suffix] = true
            end
        end
    end
    if currentId and profile.chars[currentId] then profile.currentId = currentId end
    for key, crafts in pairs(db) do
        local suffix = type(key) == "string" and key:match("^f@(.+)@internalData@crafts$") or nil
        if suffix and profile.suffixes[suffix] and type(crafts) == "table" then
            for craftKey, craft in pairs(crafts) do
                local spell = type(craftKey) == "string" and tonumber(craftKey:match("^c:(%d+)")) or nil
                if spell and type(craft) == "table" then
                    local entry = profile.crafts[spell]
                    if not entry then
                        entry = { prof = craft.profession, name = craft.name, players = {} }
                        profile.crafts[spell] = entry
                    end
                    if type(craft.players) == "table" then
                        for player in pairs(craft.players) do entry.players[player] = true end
                    end
                end
            end
        end
    end
    return profile
end

-- Characters sorted by name, for stable menus and defaults.
function ns.SortedCharacters(profile)
    local list = {}
    for charId, char in pairs(profile and profile.chars or {}) do
        table.insert(list, { value = charId, label = char.name or charId })
    end
    table.sort(list, function(a, b) if a.label ~= b.label then return a.label < b.label end return a.value < b.value end)
    return list
end

-- How many recipes of a profession TSM has scanned for a character. Zero means the
-- profession window has not been opened with TSM loaded, so known recipes are unknown.
function ns.ScannedRecipeCount(profile, charId, profession)
    local char = profile and profile.chars[charId]
    if not char then return 0 end
    local count = 0
    for _, craft in pairs(profile.crafts or {}) do
        if craft.prof == profession and craft.players[char.name] then count = count + 1 end
    end
    return count
end

local function sourceValue(api, source, itemString)
    if not api or type(api.GetCustomPriceValue) ~= "function" then return nil end
    -- Dot call on purpose: TSM_API rejects colon calls. pcall because TSM raises on bad input.
    local ok, value = pcall(api.GetCustomPriceValue, source, itemString)
    if ok and type(value) == "number" and value == value then return value end
    return nil
end

local function priceValue(api, source, itemString)
    local value = sourceValue(api, source, itemString)
    if value and value > 0 then return value end
    return nil
end

function ns.NewTSMPriceProvider(api)
    local provider = { source = "My TSM", cache = {}, lookups = 0, hits = 0 }
    function provider.rec(itemId)
        local cached = provider.cache[itemId]
        if cached ~= nil then return cached or nil end
        local itemString = "i:" .. itemId
        local med = priceValue(api, "DBMarket", itemString)
            or priceValue(api, "DBRecent", itemString)
            or priceValue(api, "DBHistorical", itemString)
            or priceValue(api, "DBRegionMarketAvg", itemString)
        local minb = priceValue(api, "DBMinBuyout", itemString)
        local record
        provider.lookups = provider.lookups + 1
        if med or minb then
            provider.hits = provider.hits + 1
            record = {
                med = med or 0, minb = minb or 0,
                -- Auctions listed on this realm at the last TSM scan; nil when TSM has no count.
                qty = sourceValue(api, "DBNumAuctions", itemString),
                spd = priceValue(api, "DBRegionSoldPerDay", itemString) or 0,
            }
        end
        provider.cache[itemId] = record or false
        return record
    end
    function provider.ah(itemId, mode)
        local record = provider.rec(itemId)
        if not record then return nil end
        if mode == "min" and record.minb > 0 then return record.minb end
        if record.med > 0 then return record.med end
        if record.minb > 0 then return record.minb end
        return nil
    end
    return provider
end

function ns.NewTablePriceProvider(records)
    local provider = { source = "Test prices", records = records or {} }
    function provider.rec(itemId)
        return provider.records[itemId]
    end
    function provider.ah(itemId, mode)
        local record = provider.rec(itemId)
        if not record then return nil end
        if mode == "min" and (record.minb or 0) > 0 then return record.minb end
        if (record.med or 0) > 0 then return record.med end
        if (record.minb or 0) > 0 then return record.minb end
        return nil
    end
    return provider
end

-- A paste-ready TSM Shopping filter: one exact search per auction-house purchase, capped at
-- the quantity to buy ("/x40" is TSM's max-quantity filter, so the scan stops offering more
-- once that many are bought). Vendor items and owned stock are left out. Items without a
-- known name are searched by item string, which TSM also accepts.
function ns.TSMShoppingString(rows, useSpare)
    local terms = {}
    for _, row in ipairs(rows or {}) do
        local quantity = useSpare and row.safeBuy or row.buy
        if not quantity or quantity < (row.buy or 0) then quantity = row.buy end
        quantity = math.ceil(quantity or 0)
        if quantity > 0 and row.src == "AH" then
            local term
            if row.named == false and row.item then
                term = "i:" .. row.item
            else
                term = row.name .. "/exact"
            end
            table.insert(terms, term .. "/x" .. quantity)
        end
    end
    return table.concat(terms, ";")
end

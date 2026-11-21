local addonName, ns = ...

ns.VERSION = "1.10.0"

-- Option keys that are restored from the saved variables. Character, profession and skill
-- range are restored separately because they depend on who is logged in.
local OPTION_KEYS = { "strictCheapest", "patterns", "vendorPatterns", "limitedPatterns", "useStock", "altStock", "ahMode", "credit",
    "cooldowns", "stations", "discolored", "simulate", "bothOnly" }

local function currentCharacter()
    -- These need the "player" unit token; called bare they raise a usage error.
    local first, surname
    if UnitName then first, surname = UnitName("player") end
    local realm = GetRealmName and GetRealmName() or nil
    local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    if type(first) ~= "string" or first == "" then first = nil end
    if type(realm) ~= "string" or realm == "" then realm = nil end
    if faction ~= "Horde" and faction ~= "Alliance" then faction = nil end
    -- WoW Forever characters have a surname, and TSM files them as "First Surname".
    local name = first
    if first and type(surname) == "string" and surname ~= "" then
        local constants = rawget(_G, "Constants")
        local group = type(constants) == "table" and constants.CharacterNameSeparatorConsts or nil
        local separator = type(group) == "table" and group.CHARACTERNAME_SURNAME_SEPARATOR or nil
        name = first .. (type(separator) == "string" and separator or " ") .. surname
    end
    -- TSM on WoW Forever groups characters by ruleset instead of by realm name.
    local realms = {}
    local rules, enum = rawget(_G, "C_GameRules"), rawget(_G, "Enum")
    local kinds = type(enum) == "table" and enum.GameRule or nil
    if type(rules) == "table" and type(rules.IsGameRuleActive) == "function" and type(kinds) == "table" then
        local function active(rule)
            if kinds[rule] == nil then return false end
            local ok, on = pcall(rules.IsGameRuleActive, kinds[rule])
            return ok and on == true
        end
        local roleplay, pvp = active("RPRuleset"), active("PvPRuleset")
        if active("HardcoreRuleset") then table.insert(realms, "Hardcore")
        elseif roleplay and pvp then table.insert(realms, "Roleplay PvP")
        elseif roleplay then table.insert(realms, "Roleplay")
        elseif pvp then table.insert(realms, "PvP")
        else table.insert(realms, "Normal") end
    end
    if realm then table.insert(realms, realm) end
    return { name = name, first = first, realm = realm, realms = realms, faction = faction }
end

-- The logged-in character's profession levels straight from the game, which is always
-- current; TSM's copy can lag behind while crafting. Names are matched in English.
function ns.ReadLiveSkills()
    local skills = {}
    local count, info = rawget(_G, "GetNumSkillLines"), rawget(_G, "GetSkillLineInfo")
    if type(count) ~= "function" or type(info) ~= "function" then return skills end
    local ok, total = pcall(count)
    if not ok or type(total) ~= "number" then return skills end
    for index = 1, total do
        local fine, name, _, _, rank, _, _, maxRank = pcall(info, index)
        if fine and type(name) == "table" then name, rank, maxRank = name.name, name.rank, name.maxRank end
        if fine and type(name) == "string" and type(rank) == "number" and ns.D and ns.D.by_prof[name] then
            skills[name] = { level = rank, maxLevel = type(maxRank) == "number" and maxRank or 0 }
        end
    end
    return skills
end

local function applyLiveSkills()
    local profile = ns.profile
    local char = profile and profile.currentId and profile.chars[profile.currentId] or nil
    if not char then return end
    for name, live in pairs(ns.ReadLiveSkills()) do
        local known = char.profs[name]
        if known then
            known.level = live.level
            if live.maxLevel > 0 then known.maxLevel = live.maxLevel end
        else
            char.profs[name] = { level = live.level, maxLevel = live.maxLevel }
        end
    end
end

-- Re-reads everything that comes from TSM. TSM keeps its saved-variable table live, so
-- calling this when the window opens picks up current bags, bank, mail, gold and skill.
function ns.RefreshTSM()
    ns.current = currentCharacter()
    local api = rawget(_G, "TSM_API")
    ns.profile = ns.ReadTSMProfile(rawget(_G, "TradeSkillMasterDB"), ns.current)
    if type(api) == "table" and type(api.GetCustomPriceValue) == "function" then
        ns.prices = ns.NewTSMPriceProvider(api)
    else
        ns.prices = nil
    end
    if ns.D then applyLiveSkills() end
    return ns.profile, ns.prices
end

local function restoreRequest()
    local profile = ns.profile
    local saved = ns.DB.settings.request
    if type(saved) ~= "table" then saved = {} end
    local request = ns.DefaultRequest(profile)
    for _, key in ipairs(OPTION_KEYS) do
        if saved[key] ~= nil and type(saved[key]) == type(request[key]) then request[key] = saved[key] end
    end
    -- The logged-in character wins. If TSM does not know it yet, fall back to the last one used.
    if not profile.currentId and saved.char and profile.chars[saved.char] then
        request.char = saved.char
        request.prof = ns.BestProfession(profile.chars[saved.char]) or request.prof
    end
    request["from"], request.to = 1, 0
    -- Same character as last session: keep the profession and range they were planning.
    if saved.char == request.char and type(saved.prof) == "string" and ns.D.by_prof[saved.prof] then
        request.prof = saved.prof
        request["from"] = tonumber(saved["from"]) or 1
        request.to = tonumber(saved.to) or 0
    end
    request.exclude = {}
    local excluded = ns.DB.settings.exclude
    if type(excluded) == "table" then
        for _, spell in ipairs(excluded) do
            if tonumber(spell) then table.insert(request.exclude, tonumber(spell)) end
        end
    end
    ns.request = request
    -- The starting skill always comes from the character when TSM knows it.
    ns.SyncRequest(true)
    return request
end

function ns.Initialize()
    local saved = rawget(_G, "ProfessionPlannerDB")
    if type(saved) ~= "table" then saved = {} end
    if type(saved.settings) ~= "table" then saved.settings = {} end
    if type(saved.ticks) ~= "table" then saved.ticks = {} end
    ProfessionPlannerDB = saved
    ns.DB = saved
    if not ns.D then ns.PrepareData() end
    ns.RefreshTSM()
    restoreRequest()
end

function ns.Toggle()
    if not ns.DB then ns.Initialize() end
    if ns.UI and ns.UI.frame:IsShown() then
        ns.UI.frame:Hide()
        return
    end
    ns.RefreshTSM()
    ns.SyncRequest(false)
    local frame = ns.CreateUI()
    ns.RefreshUI()
    frame:Show()
end

-- Keep the open window in step with the game: skill gained, items crafted or bought, a
-- recipe learned. Events come in bursts while crafting, so wait for a quiet moment and
-- redraw once. Nothing is done while the window is closed; opening it reads everything.
local updateQueued = false
function ns.LiveUpdate()
    if updateQueued then return end
    local timer = rawget(_G, "C_Timer")
    if type(timer) ~= "table" or type(timer.After) ~= "function" then return end
    updateQueued = true
    timer.After(1, function()
        updateQueued = false
        if not (ns.UI and ns.UI.frame and ns.UI.frame:IsShown()) then return end
        if ns.DB and ns.DB.settings.liveUpdate == false then return end
        ns.RefreshTSM()
        ns.SyncRequest(false)
        ns.liveRedraw = true
        local ok, problem = pcall(ns.RefreshUI)
        ns.liveRedraw = false
        if not ok then error(problem, 0) end
    end)
end
local LIVE_EVENTS = { SKILL_LINES_CHANGED = true, BAG_UPDATE_DELAYED = true, NEW_RECIPE_LEARNED = true, PLAYER_MONEY = true }

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
for event in pairs(LIVE_EVENTS) do events:RegisterEvent(event) end
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("TRAINER_SHOW")
events:RegisterEvent("MERCHANT_UPDATE")
-- Tracking. Registered one by one so a client without one of them still loads the addon.
for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "CHAT_MSG_SKILL" }) do pcall(events.RegisterEvent, events, event) end
events:SetScript("OnEvent", function(_, event, name, second, third)
    if event == "ADDON_LOADED" then
        if name == addonName then ns.Initialize() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- (unit, cast id, spell id); tracking must never get in the way of a cast.
        if name == "player" then pcall(ns.RecordCraft, type(third) == "number" and third or second) end
    elseif event == "CHAT_MSG_SKILL" then
        pcall(ns.ScanSkills)
    elseif LIVE_EVENTS[event] then
        if event == "SKILL_LINES_CHANGED" then pcall(ns.ScanSkills) end
        if ns.DB then pcall(ns.LiveUpdate) end
    elseif event == "TRAINER_SHOW" then
        pcall(ns.ArrivedAtVendor)
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        -- Never let a problem here interfere with the vendor window.
        pcall(ns.ScanMerchant)
        if event == "MERCHANT_SHOW" then pcall(ns.ArrivedAtVendor) end
    elseif event == "PLAYER_LOGIN" then
        -- Character, realm and TSM's data are all reliable by now; read them again.
        if not ns.DB then
            ns.Initialize()
        else
            ns.RefreshTSM()
            restoreRequest()
        end
        pcall(ns.ScanSkills)
    end
end)

SLASH_PROFESSIONPLANNER1 = "/pp"
SLASH_PROFESSIONPLANNER2 = "/profplan"
SLASH_PROFESSIONPLANNER3 = "/professionplanner"
SlashCmdList.PROFESSIONPLANNER = function(message)
    -- "/pp go <place>" and "/pp stop" belong to the travel arrow; anything else opens the window.
    if type(message) == "string" and message ~= "" and ns.Travel and ns.Travel.Slash(message) then return end
    ns.Toggle()
end

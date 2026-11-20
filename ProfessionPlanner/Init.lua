local addonName, ns = ...

ns.VERSION = "1.4.2"

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

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_UPDATE")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == addonName then ns.Initialize() end
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
    end
end)

SLASH_PROFESSIONPLANNER1 = "/pp"
SLASH_PROFESSIONPLANNER2 = "/profplan"
SLASH_PROFESSIONPLANNER3 = "/professionplanner"
SlashCmdList.PROFESSIONPLANNER = function() ns.Toggle() end

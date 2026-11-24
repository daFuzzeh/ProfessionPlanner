local addonName, ns = ...

-- The window is drawn entirely from flat colour blocks and text, so it needs no Blizzard
-- frame template and no art files of its own. Icons come from the game's own icon set.
-- Scroll rows are recycled. Client calls used here are ones that addons shipped for this
-- client (TradeSkillMaster, Zygor, RestedXP) already rely on.

local PROFESSIONS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Cooking", "First Aid", "Mining" }
local SECONDARY = { Cooking = true, ["First Aid"] = true, Fishing = true }
local TABS = { "Route", "Shopping", "Recipes", "Profit", "Stats" }
local ICONS = "Interface\\Icons\\"
local PROFESSION_ICON = {
    Alchemy = "Trade_Alchemy", Blacksmithing = "Trade_BlackSmithing", Enchanting = "Trade_Engraving",
    Engineering = "Trade_Engineering", Leatherworking = "Trade_LeatherWorking", Tailoring = "Trade_Tailoring",
    Cooking = "INV_Misc_Food_15", ["First Aid"] = "Spell_Holy_SealOfSacrifice", Mining = "Trade_Mining",
}

-- Layout
local FRAME_W, FRAME_H = 1040, 700
local HEADER_H, FOOTER_H, SIDE_W = 38, 26, 196
local MAIN_X = SIDE_W + 14
local MAIN_W = FRAME_W - MAIN_X - 14
local CONTENT_W = MAIN_W - 12
local SCROLL_TOP = 218
local COPY_H = 62

-- Palette
local C = {
    bg = { 0.055, 0.060, 0.075 }, header = { 0.035, 0.038, 0.048 }, side = { 0.043, 0.047, 0.060 },
    panel = { 0.095, 0.103, 0.125 }, panelAlt = { 0.078, 0.085, 0.104 }, raised = { 0.145, 0.155, 0.185 },
    line = { 0.19, 0.205, 0.245 }, text = { 0.93, 0.93, 0.90 }, dim = { 0.63, 0.66, 0.72 }, faint = { 0.44, 0.47, 0.53 },
    accent = { 1.00, 0.78, 0.26 }, accentDark = { 0.50, 0.38, 0.12 }, good = { 0.38, 0.84, 0.47 },
    warn = { 1.00, 0.62, 0.26 }, bad = { 0.95, 0.38, 0.36 }, info = { 0.40, 0.66, 0.95 },
}
local BAND = { orange = { 1.00, 0.50, 0.25 }, yellow = { 1.00, 0.92, 0.20 }, green = { 0.30, 0.78, 0.30 }, grey = { 0.50, 0.50, 0.50 } }
local QUALITY = { [0] = { 0.62, 0.62, 0.62 }, { 0.95, 0.95, 0.95 }, { 0.12, 1.00, 0.00 }, { 0.20, 0.55, 1.00 }, { 0.72, 0.36, 0.98 }, { 1.00, 0.50, 0.00 } }

local function hex(colour)
    return string.format("|cff%02x%02x%02x", math.floor(colour[1] * 255 + 0.5), math.floor(colour[2] * 255 + 0.5), math.floor(colour[3] * 255 + 0.5))
end
local DONE = "|r"

local function flag(key, group, label, hint, default)
    return { key = key, group = group, label = label, hint = hint,
        get = function(request) if request[key] == nil then return default end return request[key] == true end,
        set = function(request, on) request[key] = on end }
end

local OPTIONS = {
    flag("strictCheapest", "Route", "Cheapest gold per point", "Pick every step by lowest net gold per expected skill point.", true),
    flag("simulate", "Route", "Bad-luck spare", "Show how many extra materials an unlucky run of skill-ups needs.", true),
    flag("cooldowns", "Route", "Allow cooldown recipes", "Use recipes that can only be made once per cooldown.", false),
    flag("stations", "Route", "Allow special stations", "Use recipes that need a special forge, anvil or similar.", false),
    flag("discolored", "Route", "Silverpine quest recipe", "Include Discolored Healing Potion, taught by a quest.", false),
    flag("vendorPatterns", "Recipes to buy", "Buy vendor recipes", "Use a recipe sold by a vendor when that makes the route cheaper.", true),
    flag("limitedPatterns", "Recipes to buy", "Buy limited-stock recipes", "Use vendor recipes sold one at a time, which may be sold out or camped.", true),
    { key = "ahPatterns", group = "Recipes to buy", label = "Buy AH recipes", hint = "Use a recipe listed on the auction house when that makes the route cheaper.",
        get = function(request) return request.patterns == "buyable" end,
        set = function(request, on) request.patterns = on and "buyable" or "known" end },
    flag("useStock", "Materials", "Use my stock", "Count materials in this character's bags, bank and mail.", true),
    flag("altStock", "Materials", "Use my alts' stock", "Also count materials held by your other characters.", false),
    { key = "minimumBuyout", group = "Prices", label = "Price at minimum buyout", hint = "Use the lowest listing instead of TSM's market value.",
        get = function(request) return request.ahMode == "min" end,
        set = function(request, on) request.ahMode = on and "min" or "median" end },
    { key = "ahCredit", group = "Prices", label = "Sell crafts on the AH", hint = "Value what you craft at its auction price instead of its vendor price.",
        get = function(request) return request.credit == "ah" end,
        set = function(request, on) request.credit = on and "ah" or "vendor" end },
    flag("bothOnly", "Profit tab", "Only recipes that also give skill", "Hide profitable recipes that no longer give skill-ups.", false),
}

local function copyTable(value)
    local result = {}
    for key, item in pairs(value or {}) do result[key] = item end
    return result
end

-- Next trainer cap above a skill level (75, 150, 225, 300).
function ns.NextCap(level)
    local target = math.min(ns.MAX_SKILL, (math.floor(level / 75) + 1) * 75)
    return math.max(target, math.min(ns.MAX_SKILL, level + 1))
end

-- The profession to show for a character: the preferred one if they have it, otherwise
-- their first primary profession, otherwise a secondary one.
function ns.BestProfession(char, preferred)
    if not char or not char.profs then return nil end
    if preferred and char.profs[preferred] and ns.D.by_prof[preferred] then return preferred end
    local names = {}
    for name, values in pairs(char.profs) do
        if ns.D.by_prof[name] then
            local secondary = (type(values) == "table" and values.secondary) or SECONDARY[name]
            table.insert(names, { name = name, rank = secondary and 1 or 0 })
        end
    end
    table.sort(names, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.name < b.name end)
    return names[1] and names[1].name or nil
end

function ns.DefaultRequest(profile)
    local charId = profile and profile.currentId or nil
    if not charId then
        local sorted = ns.SortedCharacters(profile)
        charId = sorted[1] and sorted[1].value or nil
    end
    local char = charId and profile.chars[charId] or nil
    local profession = ns.BestProfession(char) or "Alchemy"
    local level = 1
    if char and char.profs and char.profs[profession] then
        level = math.max(1, math.min(ns.MAX_SKILL - 1, math.floor(tonumber(char.profs[profession].level) or 1)))
    end
    return {
        char = charId, prof = profession, ["from"] = level, to = ns.NextCap(level),
        strictCheapest = true, patterns = "known", vendorPatterns = true, limitedPatterns = true, useStock = true, altStock = false,
        ahMode = "median", credit = "vendor", cooldowns = false, stations = false,
        discolored = false, simulate = true, bothOnly = false, exclude = {},
    }
end

function ns.ClampRange(request)
    local from = math.floor(tonumber(request["from"]) or 1)
    from = math.max(1, math.min(ns.MAX_SKILL - 1, from))
    local to = math.floor(tonumber(request.to) or 0)
    if to <= from or to > ns.MAX_SKILL then to = ns.NextCap(from) end
    request["from"], request.to = from, to
end

-- Keep the request pointed at a real character and profession, and read the starting skill
-- from the character. `force` re-reads it even if the level has not changed since last time,
-- which is what a login, a character/profession change or "Refresh" wants; without it a
-- From value typed by hand survives until the character actually gains skill.
function ns.SyncRequest(force)
    local request, profile = ns.request, ns.profile
    if not request then return end
    if profile and not (request.char and profile.chars[request.char]) then
        request.char = ns.DefaultRequest(profile).char
        force = true
    end
    if not ns.D.by_prof[request.prof] then request.prof, force = "Alchemy", true end
    local char = profile and request.char and profile.chars[request.char] or nil
    local values = char and char.profs and char.profs[request.prof] or nil
    local level = values and tonumber(values.level) or nil
    if level and (force or level ~= request.syncedLevel) then
        request["from"] = level
        request.syncedLevel = level
    end
    ns.ClampRange(request)
end

function ns.Money(copper)
    if type(copper) ~= "number" then return "?" end
    local negative = copper < 0
    copper = math.floor(math.abs(copper) + 0.5)
    local gold, silver, rest = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
    local text
    if gold > 0 then text = string.format("%dg %ds %dc", gold, silver, rest)
    elseif silver > 0 then text = string.format("%ds %dc", silver, rest)
    else text = string.format("%dc", rest) end
    return negative and ("-" .. text) or text
end

-- Money for the screen: the two largest units only, with the unit letters in coin colours.
local GOLD, SILVER, COPPER = "|cffffd24a", "|cffc9ced6", "|cffe08a4c"
function ns.Coins(copper)
    if type(copper) ~= "number" then return "-" end
    local negative = copper < 0
    copper = math.floor(math.abs(copper) + 0.5)
    local gold, silver, rest = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
    local text
    if gold > 0 then
        text = gold .. GOLD .. "g" .. DONE
        if silver > 0 then text = text .. " " .. silver .. SILVER .. "s" .. DONE end
    elseif silver > 0 then
        text = silver .. SILVER .. "s" .. DONE
        if rest > 0 then text = text .. " " .. rest .. COPPER .. "c" .. DONE end
    else
        text = rest .. COPPER .. "c" .. DONE
    end
    return negative and ("-" .. text) or text
end

function ns.SetTick(spell, checked)
    if not ns.DB then return end
    ns.DB.ticks = ns.DB.ticks or {}
    ns.DB.ticks[tostring(spell)] = checked and true or nil
end

function ns.ToggleAvoid(spell)
    ns.request.exclude = ns.request.exclude or {}
    local found
    for index, value in ipairs(ns.request.exclude) do
        if value == spell then found = index; break end
    end
    if found then table.remove(ns.request.exclude, found) else table.insert(ns.request.exclude, spell) end
    if ns.DB then ns.DB.settings.exclude = copyTable(ns.request.exclude) end
    -- Avoiding a recipe re-chooses only its stretch of the kept route; allowing one again plans afresh.
    if found then ns.freshPlan = true else ns.quietBreak = true end
    local ok, problem = pcall(ns.RefreshUI)
    ns.quietBreak = nil
    if not ok then error(problem, 0) end
end

-- The route is chosen when the player asks for a plan and is then kept: what is bought, crafted or gained
-- afterwards moves the counts and the costs, not the recipes. (Buying the shopping list used to reshuffle the
-- route, because everything in the bags counts as free.) The kept route belongs to one character, profession,
-- target and set of options: change any of those, or press Plan, and the planner chooses again.
local ROUTE_KEYS = { "char", "prof", "to", "strictCheapest", "patterns", "vendorPatterns", "limitedPatterns", "useStock",
    "altStock", "ahMode", "credit", "cooldowns", "stations", "discolored", "bothOnly" }
ns.KEEP_SECONDS = 12 * 3600

function ns.RouteKey(request)
    local parts = {}
    for _, key in ipairs(ROUTE_KEYS) do table.insert(parts, tostring(request[key])) end
    return table.concat(parts, "|")
end

-- Things the player has to know before trusting the numbers on screen.
function ns.Notices()
    local notes = {}
    local request, profile, prices = ns.request, ns.profile, ns.prices
    if not prices then
        table.insert(notes, "TradeSkillMaster is not loaded, so only vendor prices are known and most routes stop early. Enable TSM and run its Desktop App.")
    elseif (prices.lookups or 0) > 0 and (prices.hits or 0) == 0 then
        table.insert(notes, "TSM has no auction prices yet. Start the TSM Desktop App, let it sync, then /reload or press Refresh.")
    end
    local char = profile and request and request.char and profile.chars[request.char] or nil
    if not char then
        table.insert(notes, "TSM has no profession data for this realm and faction yet. Open a profession window once with TSM loaded, then press Refresh. Until then, set From and To by hand.")
    elseif request then
        local values = char.profs and char.profs[request.prof] or nil
        local name = char.name or request.char
        if not values then
            table.insert(notes, name .. " has not learned " .. request.prof .. " according to TSM, so From is not read from the character.")
        else
            if (tonumber(values.level) or 0) >= ns.MAX_SKILL then
                table.insert(notes, name .. " is already at " .. ns.MAX_SKILL .. " " .. request.prof .. ".")
            end
            if ns.ScannedRecipeCount(profile, request.char, request.prof) == 0 then
                table.insert(notes, "TSM has not scanned " .. name .. "'s " .. request.prof .. " recipes. Open the " .. request.prof .. " window once so recipes already known are not priced as purchases.")
            end
        end
    end
    return notes
end

-- Widgets ---------------------------------------------------------------------
local W = {}

function W.fill(frame, layer, colour, alpha)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(colour[1], colour[2], colour[3], alpha or 1)
    return texture
end

-- A one-pixel line along one edge of a frame.
function W.edge(frame, side, colour, alpha, layer)
    local texture = frame:CreateTexture(nil, layer or "BORDER")
    texture:SetColorTexture(colour[1], colour[2], colour[3], alpha or 1)
    if side == "TOP" or side == "BOTTOM" then
        texture:SetPoint(side .. "LEFT", 0, 0)
        texture:SetPoint(side .. "RIGHT", 0, 0)
        texture:SetHeight(1)
    else
        texture:SetPoint("TOP" .. side, 0, 0)
        texture:SetPoint("BOTTOM" .. side, 0, 0)
        texture:SetWidth(1)
    end
    return texture
end

function W.border(frame, colour, alpha)
    W.edge(frame, "TOP", colour, alpha); W.edge(frame, "BOTTOM", colour, alpha)
    W.edge(frame, "LEFT", colour, alpha); W.edge(frame, "RIGHT", colour, alpha)
end

function W.font(label, size)
    local path, _, flags = label:GetFont()
    if type(path) == "string" then label:SetFont(path, size, type(flags) == "string" and flags or "") end
end

function W.text(parent, size, colour, value, layer)
    local label = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontHighlight")
    W.font(label, size or 12)
    colour = colour or C.text
    label:SetTextColor(colour[1], colour[2], colour[3])
    label:SetJustifyH("LEFT")
    label:SetText(value or "")
    return label
end

function W.tooltip(widget, title, body)
    widget.tipTitle, widget.tipBody = title, body
    widget:SetScript("OnEnter", function(self)
        local tip = rawget(_G, "GameTooltip")
        if not tip or not self.tipTitle then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:SetText(self.tipTitle, 1, 0.82, 0.3)
        if self.tipBody then tip:AddLine(self.tipBody, 0.9, 0.9, 0.9, true) end
        tip:Show()
    end)
    widget:SetScript("OnLeave", function()
        local tip = rawget(_G, "GameTooltip")
        if tip then tip:Hide() end
    end)
end

-- style: "primary" (gold), "ghost" (text only) or nil (raised grey)
function W.button(parent, text, width, height, style, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height or 22)
    local colour = style == "primary" and C.accent or C.raised
    button.bg = W.fill(button, "BACKGROUND", colour, style == "ghost" and 0 or 1)
    button.glow = W.fill(button, "HIGHLIGHT", { 1, 1, 1 }, style == "primary" and 0.18 or 0.08)
    if style ~= "primary" and style ~= "ghost" then W.border(button, C.line, 1) end
    button.label = W.text(button, 11, style == "primary" and { 0.10, 0.08, 0.03 } or C.text, text)
    button.label:SetPoint("CENTER", 0, 0)
    function button.SetLabel(self, value) self.label:SetText(value) end
    if callback then button:SetScript("OnClick", callback) end
    return button
end

-- A square that shows a filled mark when on. `check.onChange(checked)` runs after each click.
function W.check(parent, size)
    local check = CreateFrame("Button", nil, parent)
    check:SetSize(size, size)
    W.fill(check, "BACKGROUND", C.header)
    W.border(check, C.faint, 1)
    W.fill(check, "HIGHLIGHT", { 1, 1, 1 }, 0.10)
    local mark = check:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    mark:Hide()
    check.mark, check.checked = mark, false
    function check.SetChecked(self, on)
        self.checked = on and true or false
        if self.checked then self.mark:Show() else self.mark:Hide() end
    end
    function check.GetChecked(self) return self.checked end
    check:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if self.onChange then self.onChange(self.checked) end
    end)
    return check
end

function W.edit(parent, width, height, justify)
    local edit = CreateFrame("EditBox", nil, parent)
    edit:SetSize(width, height or 22)
    edit:SetAutoFocus(false)
    local font = rawget(_G, "GameFontHighlight")
    if font then edit:SetFontObject(font) end
    edit:SetTextInsets(6, 6, 0, 0)
    if justify and edit.SetJustifyH then edit:SetJustifyH(justify) end
    W.fill(edit, "BACKGROUND", C.header)
    W.border(edit, C.line, 1)
    edit:SetText("")
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return edit
end

-- The game's icon for an item, or a question mark if the client cannot say.
function W.itemIcon(itemId)
    local lookup = rawget(_G, "GetItemInfoInstant")
    local api = rawget(_G, "C_Item")
    if type(api) == "table" and type(api.GetItemInfoInstant) == "function" then lookup = api.GetItemInfoInstant end
    if itemId and type(lookup) == "function" then
        local ok, _, _, _, _, icon = pcall(lookup, itemId)
        if ok and icon then return icon end
    end
    return ICONS .. "INV_Misc_QuestionMark"
end

local function cursorY()
    local read = rawget(_G, "GetCursorPosition")
    if type(read) ~= "function" then return 0 end
    local _, y = read()
    local scale = UIParent:GetEffectiveScale()
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    return (y or 0) / scale
end

-- A clipped, wheel-scrolled area with a slim bar. The caller says how tall the visible part
-- and the content are, so nothing depends on the client reporting sizes of anchored frames.
function W.scroll(parent, width)
    local area = { offset = 0, view = 100, total = 100 }
    area.frame = CreateFrame("ScrollFrame", nil, parent)
    area.content = CreateFrame("Frame", nil, area.frame)
    area.content:SetSize(width, 100)
    area.frame:SetScrollChild(area.content)
    area.track = CreateFrame("Frame", nil, parent)
    area.track:SetWidth(6)
    area.track:SetPoint("TOPLEFT", area.frame, "TOPRIGHT", 5, 0)
    area.track:SetPoint("BOTTOMLEFT", area.frame, "BOTTOMRIGHT", 5, 0)
    W.fill(area.track, "BACKGROUND", C.header)
    area.thumb = CreateFrame("Button", nil, area.track)
    area.thumb:SetSize(6, 24)
    W.fill(area.thumb, "BACKGROUND", C.faint)
    W.fill(area.thumb, "HIGHLIGHT", C.accent, 0.6)
    local function thumbHeight() return math.max(24, area.view * area.view / math.max(1, area.total)) end
    function area.Update()
        local range = math.max(0, area.total - area.view)
        if area.offset > range then area.offset = range end
        if area.offset < 0 then area.offset = 0 end
        area.frame:SetVerticalScroll(area.offset)
        if range <= 0 then area.thumb:Hide(); return end
        local height = thumbHeight()
        area.thumb:SetHeight(height)
        area.thumb:ClearAllPoints()
        area.thumb:SetPoint("TOPLEFT", area.track, "TOPLEFT", 0, -(area.view - height) * area.offset / range)
        area.thumb:Show()
    end
    function area.SetOffset(value) area.offset = value; area.Update() end
    function area.SetExtent(view, total)
        area.view, area.total = view, math.max(view, total)
        area.content:SetHeight(area.total)
        area.Update()
    end
    area.frame:EnableMouseWheel(true)
    area.frame:SetScript("OnMouseWheel", function(_, delta) area.SetOffset(area.offset - delta * 54) end)
    local function drag()
        local grip = area.grip
        if not grip then return end
        local travel = area.view - thumbHeight()
        if travel <= 0 then return end
        area.SetOffset(grip.offset + (grip.y - cursorY()) * (area.total - area.view) / travel)
    end
    area.thumb:SetScript("OnMouseDown", function(self)
        area.grip = { y = cursorY(), offset = area.offset }
        self:SetScript("OnUpdate", drag)
    end)
    area.thumb:SetScript("OnMouseUp", function(self) area.grip = nil; self:SetScript("OnUpdate", nil) end)
    area.thumb:SetScript("OnHide", function(self) area.grip = nil; self:SetScript("OnUpdate", nil) end)
    return area
end

local openList
function W.dropdown(parent, width, onPick)
    local drop = { rows = {}, values = {} }
    drop.list = CreateFrame("Frame", nil, parent)
    drop.button = W.button(parent, "", width, 24, nil, function()
        if drop.list:IsShown() then drop.list:Hide(); return end
        if openList and openList ~= drop.list then openList:Hide() end
        openList = drop.list
        drop.list:Show()
    end)
    drop.button.label:ClearAllPoints()
    drop.button.label:SetPoint("LEFT", 8, 0)
    drop.button.label:SetWidth(width - 30)
    drop.button.label:SetWordWrap(false)
    drop.caret = W.text(drop.button, 10, C.dim, "v")
    drop.caret:SetPoint("RIGHT", -8, 0)
    drop.list:SetFrameStrata("FULLSCREEN_DIALOG")
    drop.list:SetPoint("TOPLEFT", drop.button, "BOTTOMLEFT", 0, -2)
    drop.list:SetSize(width, 24)
    drop.list:EnableMouse(true)
    W.fill(drop.list, "BACKGROUND", C.panel)
    W.border(drop.list, C.line, 1)
    drop.list:Hide()
    function drop.SetValues(values)
        drop.values = values
        for index, value in ipairs(values) do
            local row = drop.rows[index]
            if not row then
                row = W.button(drop.list, "", width - 2, 24, "ghost", nil)
                row:SetPoint("TOPLEFT", drop.list, "TOPLEFT", 1, -1 - (index - 1) * 24)
                row.label:ClearAllPoints()
                row.label:SetPoint("LEFT", 8, 0)
                drop.rows[index] = row
            end
            row:SetLabel(value.label)
            row:SetScript("OnClick", function()
                drop.list:Hide()
                onPick(value.value, value.label)
            end)
            row:Show()
        end
        for index = #values + 1, #drop.rows do drop.rows[index]:Hide() end
        drop.list:SetSize(width, math.max(1, #values) * 24 + 2)
    end
    function drop.SetText(text) drop.button:SetLabel(text) end
    return drop
end

-- Window ------------------------------------------------------------------------

local function selectProfession(name)
    local request = ns.request
    request.prof = name
    request["from"], request.to = 1, 0
    ns.SyncRequest(true)
    ns.RefreshUI()
end

local function buildHeader(ui, frame)
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    W.fill(header, "BACKGROUND", C.header)
    W.edge(header, "BOTTOM", C.line, 1)
    local mark = header:CreateTexture(nil, "ARTWORK")
    mark:SetSize(3, 18)
    mark:SetPoint("LEFT", 12, 0)
    mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    local title = W.text(header, 14, C.accent, "Profession Planner")
    title:SetPoint("LEFT", 22, 0)
    local version = W.text(header, 10, C.faint, ns.VERSION or "")
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)

    local close = W.button(header, "x", 26, 24, "ghost", function() frame:Hide() end)
    close:SetPoint("RIGHT", -8, 0)
    W.tooltip(close, "Close", "Also closes with Escape or /pp.")
    ui.optionsButton = W.button(header, "Options", 78, 24, nil, function() ns.ToggleOptions() end)
    ui.optionsButton:SetPoint("RIGHT", close, "LEFT", -8, 0)
    ui.refreshButton = W.button(header, "Refresh", 78, 24, nil, function()
        ns.RefreshTSM()
        ns.SyncRequest(true)
        ns.RefreshUI()
    end)
    ui.refreshButton:SetPoint("RIGHT", ui.optionsButton, "LEFT", -6, 0)
    W.tooltip(ui.refreshButton, "Refresh", "Read prices, stock, gold and skill from TradeSkillMaster again.")
    ui.overviewButton = W.button(header, "All characters", 110, 24, nil, function() ns.ShowOverview() end)
    ui.overviewButton:SetPoint("RIGHT", ui.refreshButton, "LEFT", -6, 0)
    W.tooltip(ui.overviewButton, "All characters", "What each character's next trainer cap would cost.")
end

local function buildSidebar(ui, frame)
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", 0, -HEADER_H)
    side:SetPoint("BOTTOMLEFT", 0, FOOTER_H)
    side:SetWidth(SIDE_W)
    W.fill(side, "BACKGROUND", C.side)
    W.edge(side, "RIGHT", C.line, 1)
    local charTitle = W.text(side, 10, C.faint, "CHARACTER")
    charTitle:SetPoint("TOPLEFT", 12, -14)
    ui.charDrop = W.dropdown(side, SIDE_W - 24, function(value)
        local request = ns.request
        request.char = value
        local char = ns.profile and ns.profile.chars[value]
        if char and not (char.profs and char.profs[request.prof]) then
            request.prof = ns.BestProfession(char) or request.prof
        end
        request["from"], request.to = 1, 0
        ns.SyncRequest(true)
        ns.RefreshUI()
    end)
    ui.charDrop.button:SetPoint("TOPLEFT", 12, -30)
    ui.gold = W.text(side, 11, C.dim, "")
    ui.gold:SetPoint("TOPLEFT", 12, -62)
    ui.gold:SetWidth(SIDE_W - 24)

    local profTitle = W.text(side, 10, C.faint, "PROFESSIONS")
    profTitle:SetPoint("TOPLEFT", 12, -92)
    ui.profRows, ui.profOrder = {}, {}
    local index = 0
    for _, name in ipairs(PROFESSIONS) do
        if ns.D.by_prof[name] then
            local row = CreateFrame("Button", nil, side)
            row:SetSize(SIDE_W - 1, 38)
            row:SetPoint("TOPLEFT", 0, -108 - index * 40)
            index = index + 1
            row.selected = W.fill(row, "BACKGROUND", C.panel)
            row.bar = row:CreateTexture(nil, "BORDER")
            row.bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            row.bar:SetPoint("TOPLEFT", 0, 0)
            row.bar:SetPoint("BOTTOMLEFT", 0, 0)
            row.bar:SetWidth(3)
            W.fill(row, "HIGHLIGHT", { 1, 1, 1 }, 0.05)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(24, 24)
            row.icon:SetPoint("LEFT", 12, 0)
            row.icon:SetTexture(ICONS .. (PROFESSION_ICON[name] or "INV_Misc_QuestionMark"))
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.label = W.text(row, 12, C.text, name)
            row.label:SetPoint("TOPLEFT", 44, -6)
            row.level = W.text(row, 11, C.dim, "")
            row.level:SetPoint("TOPRIGHT", -10, -7)
            row.level:SetJustifyH("RIGHT")
            row.track = row:CreateTexture(nil, "ARTWORK")
            row.track:SetColorTexture(C.raised[1], C.raised[2], C.raised[3], 1)
            row.track:SetSize(SIDE_W - 56, 3)
            row.track:SetPoint("TOPLEFT", 44, -26)
            row.meter = row:CreateTexture(nil, "OVERLAY")
            row.meter:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            row.meter:SetSize(1, 3)
            row.meter:SetPoint("TOPLEFT", 44, -26)
            row.profession = name
            row:SetScript("OnClick", function(self) selectProfession(self.profession) end)
            ui.profRows[name] = row
            table.insert(ui.profOrder, row)
        end
    end
    -- Normally only the character's own professions are listed; this shows the rest, for
    -- planning one not learned yet.
    ui.allProfs = W.button(side, "", SIDE_W - 24, 22, nil, function()
        ns.DB.settings.allProfessions = not ns.DB.settings.allProfessions
        ns.RefreshUI()
    end)
    ui.profNote = W.text(side, 10, C.faint, "")
    ui.profNote:SetWidth(SIDE_W - 24)
    ui.profNote:SetJustifyH("LEFT")
    ui.profNote:SetWordWrap(true)
end

local function buildControls(ui, frame)
    ui.title = W.text(frame, 18, C.text, "")
    ui.title:SetPoint("TOPLEFT", MAIN_X, -HEADER_H - 12)
    ui.subtitle = W.text(frame, 11, C.dim, "")
    ui.subtitle:SetPoint("TOPLEFT", MAIN_X, -HEADER_H - 36)
    ui.subtitle:SetWidth(430)
    ui.subtitle:SetWordWrap(false)

    local function applyRange()
        local request = ns.request
        request["from"] = tonumber(ui.fromEdit:GetText()) or request["from"]
        request.to = tonumber(ui.toEdit:GetText()) or request.to
        ui.fromEdit:ClearFocus()
        ui.toEdit:ClearFocus()
        ns.freshPlan = true
        ns.RefreshUI()
    end
    local right = -14
    ui.planButton = W.button(frame, "Plan", 64, 26, "primary", applyRange)
    ui.planButton:SetPoint("TOPRIGHT", right, -HEADER_H - 14)
    W.tooltip(ui.planButton, "Plan", "Choose the route again from what you have now. Until you press it the route stays as it is: buying, crafting and skill gained only update the counts and the costs.")
    ui.maxButton = W.button(frame, "To 300", 58, 26, nil, function()
        ns.request.to = ns.MAX_SKILL
        ns.RefreshUI()
    end)
    ui.maxButton:SetPoint("TOPRIGHT", right - 72, -HEADER_H - 14)
    W.tooltip(ui.maxButton, "To 300", "Plan from the starting skill all the way to 300.")
    ui.capButton = W.button(frame, "Next cap", 68, 26, nil, function()
        ns.request.to = ns.NextCap(ns.request["from"])
        ns.RefreshUI()
    end)
    ui.capButton:SetPoint("TOPRIGHT", right - 136, -HEADER_H - 14)
    W.tooltip(ui.capButton, "Next cap", "Plan to the next trainer cap: 75, 150, 225 or 300.")
    ui.toEdit = W.edit(frame, 50, 26, "CENTER")
    ui.toEdit:SetPoint("TOPRIGHT", right - 214, -HEADER_H - 14)
    local toLabel = W.text(frame, 11, C.dim, "to")
    toLabel:SetPoint("RIGHT", ui.toEdit, "LEFT", -8, 0)
    ui.fromEdit = W.edit(frame, 50, 26, "CENTER")
    ui.fromEdit:SetPoint("TOPRIGHT", right - 292, -HEADER_H - 14)
    local fromLabel = W.text(frame, 11, C.dim, "Skill")
    fromLabel:SetPoint("RIGHT", ui.fromEdit, "LEFT", -8, 0)
    ui.fromEdit:SetScript("OnEnterPressed", applyRange)
    ui.toEdit:SetScript("OnEnterPressed", applyRange)

    -- Skill bar: earned, planned and (if the route stops short) missing.
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetSize(MAIN_W, 10)
    bar:SetPoint("TOPLEFT", MAIN_X, -HEADER_H - 62)
    W.fill(bar, "BACKGROUND", C.panel)
    ui.bar = { frame = bar, caps = {} }
    for _, key in ipairs({ "earned", "planned", "missing" }) do
        local segment = bar:CreateTexture(nil, "ARTWORK")
        segment:SetHeight(10)
        ui.bar[key] = segment
    end
    ui.bar.earned:SetColorTexture(C.accentDark[1], C.accentDark[2], C.accentDark[3], 1)
    ui.bar.planned:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    ui.bar.missing:SetColorTexture(C.bad[1], C.bad[2], C.bad[3], 0.55)
    for _, cap in ipairs({ 75, 150, 225, 300 }) do
        local x = math.floor(MAIN_W * cap / ns.MAX_SKILL + 0.5)
        if cap < ns.MAX_SKILL then
            local tick = bar:CreateTexture(nil, "OVERLAY")
            tick:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 1)
            tick:SetSize(2, 10)
            tick:SetPoint("TOPLEFT", x - 1, 0)
        end
        local label = W.text(bar, 10, C.faint, tostring(cap))
        label:SetWidth(40)
        label:SetJustifyH("RIGHT")
        label:SetPoint("TOPRIGHT", bar, "TOPLEFT", x, -13)
        ui.bar.caps[cap] = label
    end

    -- Summary cards
    ui.cards = {}
    local keys = { "reach", "net", "perPoint", "spend", "sellBack", "crafts" }
    local titles = { reach = "REACHES", net = "NET COST", perPoint = "PER SKILL POINT", spend = "YOU SPEND", sellBack = "SELL-BACK", crafts = "CRAFTS" }
    local gap = 8
    local width = math.floor((MAIN_W - gap * (#keys - 1)) / #keys)
    for index, key in ipairs(keys) do
        local card = CreateFrame("Frame", nil, frame)
        card:SetSize(width, 52)
        card:SetPoint("TOPLEFT", MAIN_X + (index - 1) * (width + gap), -HEADER_H - 90)
        W.fill(card, "BACKGROUND", C.panel)
        card.caption = W.text(card, 9, C.faint, titles[key])
        card.caption:SetPoint("TOPLEFT", 10, -9)
        card.value = W.text(card, 15, C.text, "")
        card.value:SetPoint("TOPLEFT", 10, -25)
        card.value:SetWidth(width - 16)
        card.value:SetWordWrap(false)
        ui.cards[key] = card
    end

    -- Tabs
    ui.tabs = {}
    local x = MAIN_X
    for _, name in ipairs(TABS) do
        local tab = W.button(frame, name, 74, 28, "ghost", function() ns.ShowTab(name) end)
        tab:SetPoint("TOPLEFT", x, -HEADER_H - 150)
        tab.under = tab:CreateTexture(nil, "ARTWORK")
        tab.under:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        tab.under:SetPoint("BOTTOMLEFT", 0, 0)
        tab.under:SetPoint("BOTTOMRIGHT", 0, 0)
        tab.under:SetHeight(2)
        W.font(tab.label, 12)
        ui.tabs[name] = tab
        x = x + 77
    end
    -- Which recipes the route may buy: the options changed most often, so they sit here
    -- as well as in the Options panel.
    ui.chips = {}
    local chipX = -14
    for _, chip in ipairs({ { "ahPatterns", "AH recipes", 92 }, { "limitedPatterns", "Limited stock", 100 }, { "vendorPatterns", "Vendor recipes", 112 } }) do
        local definition
        for _, option in ipairs(OPTIONS) do if option.key == chip[1] then definition = option end end
        local button = W.button(frame, chip[2], chip[3], 22, nil, function()
            definition.set(ns.request, not definition.get(ns.request))
            ns.RefreshUI()
        end)
        button:SetPoint("TOPRIGHT", chipX, -HEADER_H - 152)
        W.tooltip(button, definition.label, definition.hint .. " Click to turn on or off.")
        button.definition = definition
        ui.chips[chip[1]] = button
        chipX = chipX - chip[3] - 6
    end
    local chipLabel = W.text(frame, 10, C.faint, "ROUTE MAY BUY")
    chipLabel:SetPoint("TOPRIGHT", chipX - 4, -HEADER_H - 158)
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    rule:SetSize(MAIN_W, 1)
    rule:SetPoint("TOPLEFT", MAIN_X, -HEADER_H - 178)
end

local function buildOptions(ui, frame)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -HEADER_H - 4)
    W.fill(panel, "BACKGROUND", C.panel)
    W.border(panel, C.accentDark, 1)
    local title = W.text(panel, 13, C.accent, "Options")
    title:SetPoint("TOPLEFT", 14, -12)
    local done = W.button(panel, "Done", 60, 22, nil, function() panel:Hide() end)
    done:SetPoint("TOPRIGHT", -12, -8)
    ui.options = {}
    local y, group = -40, nil
    for _, definition in ipairs(OPTIONS) do
        if definition.group ~= group then
            group = definition.group
            local heading = W.text(panel, 9, C.faint, string.upper(group))
            heading:SetPoint("TOPLEFT", 14, y - 4)
            y = y - 22
        end
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(332, 34)
        row:SetPoint("TOPLEFT", 6, y)
        W.fill(row, "HIGHLIGHT", { 1, 1, 1 }, 0.05)
        row.box = W.check(row, 16)
        row.box:SetPoint("TOPLEFT", 8, -4)
        row.label = W.text(row, 12, C.text, definition.label)
        row.label:SetPoint("TOPLEFT", 34, -3)
        row.hint = W.text(row, 10, C.dim, definition.hint)
        row.hint:SetPoint("TOPLEFT", 34, -18)
        row.hint:SetWidth(294)
        row.hint:SetWordWrap(false)
        local function changed(checked)
            definition.set(ns.request, checked)
            ns.RefreshUI()
        end
        row.box.onChange = changed
        row:SetScript("OnClick", function(self)
            self.box:SetChecked(not self.box.checked)
            changed(self.box.checked)
        end)
        function row.SetChecked(self, on) self.box:SetChecked(on) end
        ui.options[definition.key] = row
        y = y - 34
    end
    panel:SetSize(344, -y + 10)
    panel:Hide()
    ui.optionsPanel = panel
end

function ns.ToggleOptions()
    local ui = ns.UI
    if not ui then return end
    if ui.optionsPanel:IsShown() then ui.optionsPanel:Hide() else ui.optionsPanel:Show() end
end

function ns.CreateUI()
    if ns.UI and ns.UI.frame then return ns.UI.frame end
    local frame = CreateFrame("Frame", "ProfessionPlannerFrame", UIParent)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    W.fill(frame, "BACKGROUND", C.bg, 0.97)
    W.border(frame, C.line, 1)
    local special = rawget(_G, "UISpecialFrames")
    if type(special) == "table" then table.insert(special, "ProfessionPlannerFrame") end

    local ui = { frame = frame, pools = {}, created = 0, activeTab = "Route", currentPlan = nil }
    ns.UI = ui
    frame:SetScript("OnHide", function()
        if openList then openList:Hide() end
        if ui.optionsPanel then ui.optionsPanel:Hide() end
    end)
    buildHeader(ui, frame)
    buildSidebar(ui, frame)
    buildControls(ui, frame)

    ui.area = W.scroll(frame, CONTENT_W)
    ui.area.frame:SetPoint("TOPLEFT", MAIN_X, -SCROLL_TOP)
    ui.area.frame:SetPoint("BOTTOMRIGHT", -26, FOOTER_H + 8)
    ui.scroll, ui.content = ui.area.frame, ui.area.content

    -- Footer
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    footer:SetHeight(FOOTER_H)
    W.fill(footer, "BACKGROUND", C.header)
    W.edge(footer, "TOP", C.line, 1)
    ui.status = W.text(footer, 10, C.dim, "")
    ui.status:SetPoint("LEFT", 12, 0)
    ui.status:SetWidth(700)
    ui.status:SetWordWrap(false)
    local hint = W.text(footer, 10, C.faint, "/pp opens and closes this window")
    hint:SetPoint("RIGHT", -12, 0)

    -- TSM buy list, shown under the Shopping tab only.
    local copy = CreateFrame("Frame", nil, frame)
    copy:SetSize(MAIN_W, COPY_H - 8)
    copy:SetPoint("BOTTOMLEFT", MAIN_X, FOOTER_H + 8)
    W.fill(copy, "BACKGROUND", C.panel)
    ui.copyLabel = W.text(copy, 10, C.dim, "")
    ui.copyLabel:SetPoint("TOPLEFT", 10, -6)
    ui.copyLabel:SetWidth(MAIN_W - 20)
    ui.copyLabel:SetWordWrap(false)
    ui.copyBox = W.edit(copy, MAIN_W - 150, 24)
    ui.copyBox:SetMaxLetters(0)
    ui.copyBox:SetPoint("BOTTOMLEFT", 10, 6)
    ui.copyButton = W.button(copy, "Select buy list", 120, 24, "primary", function() ns.SelectShopping() end)
    ui.copyButton:SetPoint("BOTTOMRIGHT", -10, 6)
    ui.copyBar = copy

    buildOptions(ui, frame)
    frame:Hide()
    return frame
end

function ns.SelectShopping()
    local ui = ns.UI
    if not ui or not ui.currentPlan then return end
    ui.copyBox:SetText(ui.currentPlan.tsmString or "")
    ui.copyBox:SetFocus()
    ui.copyBox:HighlightText()
end

-- Scroll rows -------------------------------------------------------------------

local function acquire(ui, kind, factory)
    local pool = ui.pools[kind]
    if not pool then
        pool = { used = 0 }
        ui.pools[kind] = pool
    end
    pool.used = pool.used + 1
    local widget = pool[pool.used]
    if not widget then
        widget = factory()
        pool[pool.used] = widget
        ui.created = ui.created + 1
    end
    widget:ClearAllPoints()
    widget:Show()
    return widget
end

local function releaseAll(ui)
    for _, pool in pairs(ui.pools) do
        for index = 1, pool.used do pool[index]:Hide() end
        pool.used = 0
    end
end

-- Places text at (x, y) in the scroll content and returns its height. Wrapped text grows
-- downwards; single-line text is cut off at `width` by the client.
local function put(ui, x, y, width, value, size, colour, justify, wrap)
    local label = acquire(ui, "text", function()
        local created = ui.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        created:SetJustifyV("TOP")
        return created
    end)
    size, colour = size or 11, colour or C.text
    W.font(label, size)
    label:SetTextColor(colour[1], colour[2], colour[3])
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(wrap and true or false)
    label:SetWidth(width)
    label:SetPoint("TOPLEFT", ui.content, "TOPLEFT", x, y)
    label:SetText(value or "")
    local height = wrap and label:GetStringHeight() or 0
    if not height or height < size + 1 then height = size + 1 end
    return math.ceil(height), label
end

local function block(ui, kind, x, y, width, height, colour, alpha)
    local layer = kind == "bg" and "BACKGROUND" or "ARTWORK"
    local texture = acquire(ui, kind, function() return ui.content:CreateTexture(nil, layer) end)
    texture:SetColorTexture(colour[1], colour[2], colour[3], alpha or 1)
    texture:SetSize(math.max(1, width), math.max(1, height))
    texture:SetPoint("TOPLEFT", ui.content, "TOPLEFT", x, y)
    return texture
end

local function rowButton(ui, x, y, label, callback, width)
    local button = acquire(ui, "button", function() return W.button(ui.content, "", 58, 22, nil, nil) end)
    button:SetSize(width or 58, 22)
    button:SetPoint("TOPLEFT", ui.content, "TOPLEFT", x, y)
    button:SetLabel(label)
    button:SetScript("OnClick", callback)
    return button
end

local function rowTick(ui, x, y, spell)
    local check = acquire(ui, "tick", function()
        local created = W.check(ui.content, 18)
        W.tooltip(created, "Done", "Tick a step off as you finish it. Ticks are remembered.")
        return created
    end)
    check:SetPoint("TOPLEFT", ui.content, "TOPLEFT", x, y)
    check:SetChecked(ns.DB ~= nil and ns.DB.ticks ~= nil and ns.DB.ticks[tostring(spell)] == true)
    check.onChange = function(checked) ns.SetTick(spell, checked) end
    check.spell = spell
    return check
end

-- Shift-click on an item does what a shift-click on an item anywhere in the game does: it
-- hands the item's link to whatever is listening. With TSM's Browse tab open at the auction
-- house that starts an exact search for the item; with a chat box open it links the item.
function ns.LinkItem(itemId, name)
    if not itemId then return false end
    local link
    local info = rawget(_G, "GetItemInfo")
    if type(info) == "function" then
        local ok, _, found = pcall(info, itemId)
        if ok and type(found) == "string" then link = found end
    end
    link = link or ("|cffffffff|Hitem:" .. itemId .. "::::::::|h[" .. tostring(name or itemId) .. "]|h|r")
    local insert = rawget(_G, "ChatEdit_InsertLink")
    local handled = false
    if type(insert) == "function" then
        local ok, result = pcall(insert, link)
        handled = ok and result and true or false
    end
    if not handled then
        local chat = rawget(_G, "DEFAULT_CHAT_FRAME")
        if chat and chat.AddMessage then
            chat:AddMessage("|cffffc842Profession Planner:|r nothing took the item. Open TradeSkillMaster's Browse tab at the auction house, then shift-click again.")
        end
    end
    return handled
end

local function say(text)
    local chat = rawget(_G, "DEFAULT_CHAT_FRAME")
    if chat and chat.AddMessage then chat:AddMessage("|cffffc842Profession Planner:|r " .. text) end
end

-- The game's ids for the professions (its skill lines; the recipe data is built from the same ids).
local SKILL_LINES = { Alchemy = 171, Blacksmithing = 164, Cooking = 185, Enchanting = 333, Engineering = 202,
    ["First Aid"] = 129, Leatherworking = 165, Mining = 186, Tailoring = 197 }

-- What the game's profession window shows right now: whether it is up, and the recipe (spell
-- id) on its page, nil when the window cannot say.
local function professionWindow()
    local frame = rawget(_G, "ProfessionsFrame")
    if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return false, nil end
    local ok, shown = pcall(frame.IsShown, frame)
    if not ok or not shown then return false, nil end
    local page = frame.CraftingPage
    local form = type(page) == "table" and page.SchematicForm or nil
    if type(form) == "table" and type(form.GetRecipeInfo) == "function" then
        local fine, info = pcall(form.GetRecipeInfo, form)
        if fine and type(info) == "table" then return true, tonumber(info.recipeID) end
    end
    return true, nil
end

-- Whether the character being played knows the recipe: true, false, or nil when the game cannot say.
local function knowsRecipe(spell)
    local answer
    for _, name in ipairs({ "IsPlayerSpell", "IsSpellKnown" }) do
        local check = rawget(_G, name)
        if type(check) == "function" then
            local ok, known = pcall(check, spell)
            if ok and known then return true end
            if ok then answer = false end
        end
    end
    return answer
end

-- A plain click on a recipe opens the game's profession window at that recipe, the way a click
-- on a tracked recipe does in the game's own interface: C_TradeSkillUI.OpenRecipe asks the game
-- and the profession window answers by turning to the recipe. Calls that open windows or cast
-- can be limited to the moment the game is handling a click, so the call is made here, inside
-- the click, and never from a timer; only the look afterwards waits, and it speaks up in chat
-- when the window did not follow.
local opening = 0
function ns.OpenRecipe(spell, name, profession)
    spell = tonumber(spell)
    if not spell then return false end
    local label = tostring(name or ("recipe " .. spell))
    opening = opening + 1
    local mine = opening
    -- The route on screen may be another character's.
    local live = ns.ReadLiveSkills()
    if profession and next(live) ~= nil and not live[profession] then
        say("the character you are playing has not learned " .. profession .. ", so there is no window to open for " .. label .. ".")
        return false
    end
    local api = rawget(_G, "C_TradeSkillUI")
    local openRecipe = type(api) == "table" and api.OpenRecipe or nil
    local openProfession = type(api) == "table" and api.OpenTradeSkill or nil
    -- The window's code is loaded on first use; the game's recipe tracker loads it the same way before it asks.
    local load = rawget(_G, "ProfessionsFrame_LoadUI")
    if rawget(_G, "ProfessionsFrame") == nil and type(load) == "function" then pcall(load) end
    local asked, refused
    if type(openRecipe) == "function" then
        local ok, why = pcall(openRecipe, spell)
        if ok then asked = "recipe" else refused = tostring(why) end
    end
    local line = SKILL_LINES[profession or ""]
    if not asked and type(openProfession) == "function" and line then
        local ok, opened = pcall(openProfession, line)
        if ok and opened ~= false then asked = "profession" elseif not ok then refused = refused or tostring(opened) end
    end
    if not asked then
        local missing = type(openRecipe) ~= "function" and type(openProfession) ~= "function"
        say("could not open " .. label .. " from here"
            .. (missing and ": this game client has no call for it (C_TradeSkillUI.OpenRecipe and OpenTradeSkill are both missing)" or "")
            .. (refused and (": the game said " .. refused) or "")
            .. ". Open " .. (profession or "the profession") .. " yourself and pick it in the list.")
        return false
    end
    local timer = rawget(_G, "C_Timer")
    if type(timer) ~= "table" or type(timer.After) ~= "function" then return true end
    local function look(last)
        if mine ~= opening then return end                     -- a later click took over
        local shown, showing = professionWindow()
        if shown and showing == spell then return end           -- it worked: nothing to say
        if not last then timer.After(1.5, function() look(true) end); return end
        if not shown then
            say("asked the game to open " .. label .. ", but no profession window appeared. Open " .. (profession or "the profession") .. " yourself and pick it in the list.")
        elseif asked == "profession" then
            say("opened " .. (profession or "the profession") .. ", but "
                .. (refused and ("the game would not turn to the recipe (it said " .. refused .. ")")
                    or "this game client has no call to turn to a recipe (C_TradeSkillUI.OpenRecipe is missing)")
                .. ". Pick " .. label .. " in the list.")
        elseif showing ~= nil then
            say("the profession window is open but did not turn to " .. label
                .. (knowsRecipe(spell) == false and ": this character has not learned it yet." or ". Pick it in the list."))
        end
    end
    timer.After(0.5, function() look(false) end)
    return true
end

-- A plain click on something the planner can make opens its recipe; a shift-click on any item
-- hands on its link, as before.
local function itemClick(self)
    local shift = rawget(_G, "IsShiftKeyDown")
    if type(shift) == "function" and shift() then ns.LinkItem(self.item, self.name)
    elseif self.spell then ns.OpenRecipe(self.spell, self.recipe or self.name, self.prof) end
end

local OPEN_HINT = "Click to open this recipe in your profession window."

local function itemTip(self)
    local tip = rawget(_G, "GameTooltip")
    if not tip then return end
    tip:SetOwner(self, self.tipAnchor or "ANCHOR_RIGHT")
    local shown = self.item and pcall(tip.SetHyperlink, tip, "item:" .. self.item)
    if not shown then tip:SetText(self.name or "Unknown item", 1, 1, 1) end
    if self.spell then tip:AddLine(OPEN_HINT, 0.45, 0.78, 1) end
    tip:Show()
end

local function hideTip()
    local tip = rawget(_G, "GameTooltip")
    if tip then tip:Hide() end
end

-- An invisible click area over an item's name. Over a recipe's name (spell given) a plain click
-- opens the recipe and hovering shows what it makes.
local function rowHit(ui, x, y, width, height, itemId, name, spell, recipe, prof)
    local hit = acquire(ui, "hit", function()
        local created = CreateFrame("Button", nil, ui.content)
        created.tipAnchor = "ANCHOR_CURSOR"
        created:SetScript("OnClick", itemClick)
        created:SetScript("OnEnter", function(self) if self.spell then itemTip(self) end end)
        created:SetScript("OnLeave", function(self) if self.spell then hideTip() end end)
        return created
    end)
    hit:SetSize(width, height)
    hit:SetPoint("TOPLEFT", ui.content, "TOPLEFT", x, y)
    hit.item, hit.name, hit.spell, hit.recipe, hit.prof = itemId, name, spell, recipe, prof
    return hit
end

local function rowIcon(ui, x, y, size, itemId, name, spell, recipe, prof)
    local icon = acquire(ui, "icon", function()
        local created = CreateFrame("Button", nil, ui.content)
        created.art = created:CreateTexture(nil, "ARTWORK")
        created.art:SetAllPoints()
        created.art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        created:SetScript("OnEnter", itemTip)
        created:SetScript("OnLeave", hideTip)
        created:SetScript("OnClick", itemClick)
        return created
    end)
    icon:SetSize(size, size)
    icon:SetPoint("TOPLEFT", ui.content, "TOPLEFT", x, y)
    icon.item, icon.name, icon.spell, icon.recipe, icon.prof = itemId, name, spell, recipe, prof
    icon.art:SetTexture(W.itemIcon(itemId))
    return icon
end

-- A full-width message with a coloured bar down its left edge.
local function banner(ui, y, value, colour, reserve)
    local bg = block(ui, "bg", 0, y, CONTENT_W, 10, colour, 0.10)
    local bar = block(ui, "art", 0, y, 3, 10, colour, 1)
    local height = put(ui, 14, y - 8, CONTENT_W - 28 - (reserve or 0), value, 11, C.text, "LEFT", true) + 16
    if reserve then height = math.max(height, 34) end
    bg:SetHeight(height)
    bar:SetHeight(height)
    return y - height - 6
end

local function heading(ui, y, columns)
    for _, column in ipairs(columns) do
        put(ui, column.x, y - 4, column.w, column.title, 9, C.faint, column.right and "RIGHT" or "LEFT")
    end
    block(ui, "art", 0, y - 20, CONTENT_W, 1, C.line, 1)
    return y - 24
end

local function stripe(ui, y, height, index)
    if index % 2 == 0 then block(ui, "bg", 0, y, CONTENT_W, height, C.panelAlt, 1) end
end

local function bandColour(band)
    return BAND[string.match(band or "", "^(%a+)") or ""] or C.faint
end

local function renderRoute(ui, plan, y)
    local summary, request = plan.summary, ns.request
    -- One block for what could make the route cost more, one for plain facts about it.
    local cautions, facts = {}, {}
    if plan.wallet and not plan.wallet.enough then
        table.insert(cautions, "Gold on this character: " .. ns.Coins(plan.wallet.money) .. ". That covers this route to about skill " .. plan.wallet.affordableTo .. ".")
    end
    if (summary.thinSupply or 0) > 0 then
        table.insert(cautions, summary.thinSupply .. " material(s) have fewer auctions listed than this route needs, so the real cost will be higher. See the Shopping tab.")
    end
    for _, warning in ipairs(plan.warnings or {}) do table.insert(cautions, warning) end
    if (summary.spendPatterns or 0) > 0 then
        table.insert(facts, "The spend includes " .. ns.Coins(summary.spendPatterns) .. " for recipes to buy.")
    end
    if request.simulate and (summary.safeSpend or 0) > (summary.spend or 0) then
        table.insert(facts, string.format("With bad luck on skill-ups: up to %d crafts and %s spent.", summary.safeCrafts or summary.crafts, ns.Coins(summary.safeSpend)))
    end
    if #cautions > 0 then y = banner(ui, y, table.concat(cautions, "\n"), C.warn) end
    if #facts > 0 then y = banner(ui, y, table.concat(facts, "\n"), C.info) end
    local steps = 0
    for _, step in ipairs(plan.steps) do
        if step.type == "note" then
            -- Already trained past this cap: nothing to say.
            local char = ns.profile and ns.profile.chars[request.char] or nil
            local mine = char and char.profs and char.profs[request.prof] or nil
            local trained = mine and step.at and (tonumber(mine.maxLevel) or 0) > step.at
            if not trained then
                local faction = ns.profile and ns.profile.faction
                local cap = step.at or 0
                local trainers = ns.SortStops(ns.RankTrainers(request.prof, cap, faction))
                local text = "Trainer: " .. step.text
                if #trainers > 0 then
                    local named = {}
                    for index = 1, math.min(4, #trainers) do table.insert(named, ns.StopText(trainers[index])) end
                    text = text .. "\nTaught by: " .. table.concat(named, "; ")
                        .. (#trainers > 4 and (" and " .. (#trainers - 4) .. " more") or "") .. "."
                        .. "\nNot every trainer teaches this rank, whatever their title says."
                    local pinned = ns.pinned and ns.pinned.source == ("trainer:" .. request.prof .. ":" .. cap)
                    local top = y
                    y = banner(ui, y, text, C.accent, pinned and 190 or 112)
                    local prof = request.prof
                    rowButton(ui, CONTENT_W - 108, top - 6, "Show on map", function() ns.ShowTrainer(prof, cap, faction) end, 96)
                    if pinned then rowButton(ui, CONTENT_W - 186, top - 6, "Clear pin", function() ns.ClearPin() end, 72) end
                else
                    y = banner(ui, y, text, C.accent)
                end
            end
        else
            steps = steps + 1
            local top = y
            local bg = block(ui, "bg", 0, top, CONTENT_W, 10, C.panel, 1)
            local bar = block(ui, "art", 0, top, 3, 10, bandColour(step.band), 1)
            rowTick(ui, 14, top - 15, step.spell)
            rowIcon(ui, 42, top - 9, 30, step.productItem, step.product or step.recipe, step.spell, step.recipe, request.prof)
            local x, narrow = 84, CONTENT_W - 84 - 300
            local cy = top - 9
            local titleHeight, title = put(ui, x, cy, narrow, step.recipe, 13, QUALITY[step.q or 1] or C.text)
            -- The click area is as wide as the name, not the column, so empty space beside it stays inert.
            local titleWidth = title:GetStringWidth()
            if type(titleWidth) ~= "number" or titleWidth < 24 then titleWidth = narrow end
            rowHit(ui, x - 2, cy + 2, math.min(narrow, titleWidth + 6), titleHeight + 4, step.productItem, step.product or step.recipe,
                step.spell, step.recipe, request.prof)
            cy = cy - titleHeight - 4
            local crafts = step.crafts .. (step.crafts == 1 and " craft" or " crafts")
            if request.simulate and (step.safeCrafts or 0) > step.crafts then
                crafts = crafts .. ", " .. step.safeCrafts .. " if unlucky"
            end
            -- Far more crafts than points: say how many for each point.
            local points = step.to - step["from"]
            if points >= 1 and step.crafts >= 1.5 * points and step.crafts - points >= 3 then
                crafts = crafts .. string.format(", about %.1f crafts per point", step.crafts / points)
            end
            cy = cy - put(ui, x, cy, narrow, string.format("Skill %d - %d     %s     %s%s%s", step["from"], step.to, crafts,
                hex(bandColour(step.band)), tostring(step.band or ""), DONE), 11, C.dim) - 6
            -- right-hand figures and the avoid button
            -- A step that sells for more than it costs is shown as a gain, not a negative cost.
            local gain = (step.cost or 0) < 0
            put(ui, CONTENT_W - 296, top - 9, 110, ns.Coins(math.abs(step.cost or 0)), 12, gain and C.good or C.text, "RIGHT")
            put(ui, CONTENT_W - 296, top - 26, 110, gain and "step profit" or "step cost", 9, C.faint, "RIGHT")
            put(ui, CONTENT_W - 180, top - 8, 104, ns.Coins(math.abs(step.perPoint or 0)), 13, gain and C.good or C.accent, "RIGHT")
            put(ui, CONTENT_W - 180, top - 26, 104, gain and "earned per point" or "per point", 9, C.faint, "RIGHT")
            rowButton(ui, CONTENT_W - 66, top - 11, "Avoid", function() ns.ToggleAvoid(step.spell) end)
            local wide = CONTENT_W - x - 14
            local materials = {}
            for _, material in ipairs(step.mats or {}) do
                local entry = material.qty .. " x " .. material.name
                if (material.own or 0) > 0 then
                    entry = entry .. hex(C.good) .. " (have " .. material.own .. ", buy " .. material.buy .. ")" .. DONE
                end
                table.insert(materials, entry)
            end
            if #materials > 0 then cy = cy - put(ui, x, cy, wide, table.concat(materials, "     "), 11, C.text, "LEFT", true) - 4 end
            if step.pattern and step.pattern.src == "Owned" then
                cy = cy - put(ui, x, cy, wide, "You have " .. step.pattern.name .. ": use it to learn this recipe.", 11, C.good, "LEFT", true) - 4
            elseif step.pattern then
                local where = step.pattern.src == "Vendor" and "Buy from a vendor: " or "Buy on the AH: "
                cy = cy - put(ui, x, cy, wide, where .. step.pattern.name .. " for " .. ns.Coins(step.pattern.price), 11, C.accent, "LEFT", true) - 4
            end
            if step.sell and step.product then
                local sell, text = step.sell, nil
                local what = sell.made .. " x " .. step.product
                local rate = string.format("%.1f", sell.perDay or 0)
                if sell.how == "AH" then
                    text = "Sell on the AH: " .. what .. " for about " .. ns.Coins(sell.ah or 0) .. " after the cut (about " .. rate .. " sell a day)."
                    if sell.vendor > 0 then text = text .. " A vendor pays " .. ns.Coins(sell.vendor) .. "." end
                elseif sell.how == "vendor" then
                    if sell.vendor > 0 then text = "Sell to a vendor: " .. what .. " for " .. ns.Coins(sell.vendor) .. "."
                    else text = "Nothing counted for the " .. what .. ": a vendor pays nothing for it." end
                    -- Point out an AH price that clearly beats the vendor and actually sells.
                    if sell.ah and sell.ah > sell.vendor * 1.25 and (sell.perDay or 0) >= 1 then
                        text = text .. hex(C.good) .. " The AH pays about " .. ns.Coins(sell.ah) .. " (about " .. rate .. " sell a day)." .. DONE
                    end
                else
                    text = "Sell-back is not counted (see Options)."
                end
                cy = cy - put(ui, x, cy, wide, text, 11, C.dim, "LEFT", true) - 4
            end
            if step.pattern and step.pattern.stock then
                local clock = rawget(_G, "time")
                local text = ns.StockText(step.pattern.stock, type(clock) == "function" and clock() or nil)
                if step.without then text = text .. " " .. step.without end
                cy = cy - put(ui, x, cy, wide, text, 11, C.warn, "LEFT", true) - 4
            end
            if step.via ~= "known" and step.via ~= "auto" and (step.source or step.learnSrc) then
                local faction = ns.profile and ns.profile.faction
                local source = step.source or step.learnSrc
                -- A recipe to buy from a vendor gets a button that pins the vendor on the map.
                local mapped = step.pattern and step.pattern.src == "Vendor" and #ns.VendorStops(source, faction) > 0
                local pinnedHere = mapped and ns.pinned and ns.pinned.source == source
                local room = mapped and (wide - (pinnedHere and 182 or 104)) or wide
                -- A trainer recipe shows the skill the planner uses, not the one in the shipped text.
                local learnText = ns.TrainerLearnText(source, step.learn, step.learnSrc, step.unconfirmed, step.spell)
                local height = put(ui, x, cy, room, "Learn: " .. (learnText or ns.SourceWithCoords(source, faction)), 11, C.dim, "LEFT", true)
                if mapped then
                    rowButton(ui, x + wide - 96, cy + 4, "Show on map", function() ns.ShowVendor(source, faction) end, 96)
                    if pinnedHere then rowButton(ui, x + wide - 174, cy + 4, "Clear pin", function() ns.ClearPin() end, 72) end
                    height = math.max(height, 20)
                end
                cy = cy - height - 4
            end
            if step.unconfirmed then
                local text = "No trainer has been seen offering this at " .. tostring(step.learn) .. " yet"
                if step.learnWas then text = text .. " (older data said " .. tostring(step.learnWas) .. ")" end
                text = text .. ". Open a " .. tostring(request.prof) .. " trainer's window to check."
                cy = cy - put(ui, x, cy, wide, text, 10, C.dim, "LEFT", true) - 4
            end
            if step.alts and #step.alts > 0 then
                local alternatives = {}
                for _, alternative in ipairs(step.alts) do
                    table.insert(alternatives, alternative.name .. " (+" .. ns.Coins(math.max(0, alternative.delta)) .. ")")
                end
                cy = cy - put(ui, x, cy, wide, "If it is bought out, next cheapest per point: " .. table.concat(alternatives, ",  "), 10, C.faint, "LEFT", true) - 4
            end
            local height = math.max(48, top - cy + 6)
            bg:SetHeight(height)
            bar:SetHeight(height)
            y = top - height - 6
        end
    end
    if steps == 0 and not plan.failed then
        y = banner(ui, y, "No steps to show for skill " .. (plan["from"] or request["from"]) .. " to " .. (plan.to or request.to) .. ".", C.info)
    end
    return y
end

local SHOPPING_COLUMNS = {
    { key = "name", title = "ITEM", x = 40, w = 262 }, { key = "need", title = "NEED", x = 306, w = 52, right = true },
    { key = "own", title = "HAVE", x = 362, w = 52, right = true }, { key = "buy", title = "BUY", x = 418, w = 56, right = true },
    { key = "spare", title = "WITH SPARE", x = 474, w = 70, right = true }, { key = "src", title = "FROM", x = 558, w = 68 },
    { key = "unit", title = "EACH", x = 630, w = 82, right = true }, { key = "cost", title = "COST", x = 716, w = 84, right = true },
}

local function renderShopping(ui, plan, y)
    local summary, request = plan.summary, ns.request
    y = banner(ui, y, "Buy on the auction house: " .. ns.Coins(summary.buyAH or 0) .. "      Buy from vendors: " .. ns.Coins(summary.buyVendor or 0)
        .. "\nQuantities are what the route still needs after your own stock.", C.info)
    if #plan.shopping == 0 then return banner(ui, y, "Nothing to buy for this route.", C.good) end
    y = heading(ui, y, SHOPPING_COLUMNS)
    for index, row in ipairs(plan.shopping) do
        local note
        if row.warn then note = hex(C.warn) .. row.warn .. DONE end
        if row.named == false and row.src == "AH" then
            note = (note and (note .. "     ") or "") .. "The game has not seen this item yet, so it is searched by item ID."
        end
        local height = note and 44 or 26
        stripe(ui, y, height, index)
        rowIcon(ui, 10, y - 3, 20, row.item, row.name)
        local hasSpare = request.simulate and (row.safeBuy or 0) > row.buy
        local source = row.src or "no price"
        local sourceColour = source == "AH" and C.text or (source == "Vendor" and C.info or (source == "Own stock" and C.good or C.bad))
        put(ui, 40, y - 7, 262, row.name, 11, QUALITY[row.q or 1] or C.text)
        rowHit(ui, 34, y - 2, 268, 22, row.item, row.name)
        put(ui, 306, y - 7, 52, tostring(row.need), 11, C.dim, "RIGHT")
        put(ui, 362, y - 7, 52, tostring(row.own), 11, row.own > 0 and C.good or C.faint, "RIGHT")
        put(ui, 418, y - 7, 56, tostring(row.buy), 12, row.buy > 0 and C.text or C.faint, "RIGHT")
        put(ui, 474, y - 7, 70, hasSpare and tostring(row.safeBuy) or "-", 11, hasSpare and C.dim or C.faint, "RIGHT")
        put(ui, 558, y - 7, 68, source, 11, sourceColour)
        put(ui, 630, y - 7, 82, row.unit and ns.Coins(row.unit) or "-", 11, C.dim, "RIGHT")
        put(ui, 716, y - 7, 84, ns.Coins(row.cost), 11, C.text, "RIGHT")
        if note then put(ui, 40, y - 25, CONTENT_W - 54, note, 10, C.dim) end
        y = y - height
    end
    return y
end

local RECIPE_COLUMNS = {
    { title = "RECIPE", x = 40, w = 236 }, { title = "LEARN", x = 280, w = 44, right = true },
    { title = "YELLOW", x = 328, w = 50, right = true }, { title = "GREY", x = 382, w = 44, right = true },
    { title = "MATERIALS", x = 430, w = 88, right = true }, { title = "PER POINT", x = 522, w = 88, right = true },
    { title = "STATUS", x = 626, w = 100 },
}
local STATUS = { known = { "Known", "good" }, auto = { "Known", "good" }, trainer = { "Trainer", "text" }, pattern = { "Buy recipe", "accent" } }

local function renderRecipes(ui, plan, y)
    local request = ns.request
    local ok, result = pcall(ns.BuildRecipes, request, ns.profile, ns.prices)
    if not ok then return banner(ui, y, tostring(result), C.bad) end
    local rows = {}
    for _, row in ipairs(result.rows) do
        local starts = row.learn or row.yellow or 0
        if row.why == "avoided by you" or (starts <= request.to and (row.grey or 0) > request["from"]) then
            table.insert(rows, row)
        end
    end
    y = banner(ui, y, string.format("%d of %d %s recipes are useful between skill %d and %d. Change the skill range to see others.",
        #rows, #result.rows, request.prof, request["from"], request.to), C.info)
    y = heading(ui, y, RECIPE_COLUMNS)
    for index, row in ipairs(rows) do
        local avoided = row.why == "avoided by you"
        local status = STATUS[row.via or ""]
        local statusText, statusColour = status and status[1] or "Not available", status and C[status[2]] or C.faint
        if row.limited then statusText, statusColour = "Buy (limited)", C.warn end
        if row.owned then statusText, statusColour = "You have the recipe", C.good end
        if avoided then statusText, statusColour = "Avoided", C.warn end
        -- A trainer that did not offer the recipe: the status says which one and at what skill.
        local gone = not row.via and not avoided and row.why and ns.TrainerMissingEntry(row.spell, request.trainerMissing) or nil
        local statusWidth = 100
        if gone and row.why == ns.TrainerMissingReason(gone) then
            statusText, statusColour, statusWidth = ns.TrainerMissingStatus(gone), C.warn, CONTENT_W - 626 - 8
        end
        local note
        local learnText
        if not row.via and row.why and not avoided then note = row.why
        elseif row.source and row.via ~= "known" and row.via ~= "auto" then
            learnText = ns.TrainerLearnText(row.source, row.learn, row.learnSrc, row.unconfirmed, row.spell)
            note = learnText or ns.SourceForFaction(row.source, ns.profile and ns.profile.faction)
        end
        local unsure = row.unconfirmed and row.via and row.via ~= "known" and row.via ~= "auto"
        if unsure and not learnText then note = (note and (note .. "  ") or "") .. "Learn rank not confirmed in this game yet." end
        local nameColour = row.via and (BAND[row.colour or ""] or C.text) or C.faint
        local noteHeight = 0
        if note then noteHeight = put(ui, 40, y - 24, CONTENT_W - 120, note, 10, C.faint, "LEFT", true) + 4 end
        local height = 26 + noteHeight
        stripe(ui, y, height, index)
        rowIcon(ui, 10, y - 3, 20, row.item, row.name, row.spell, row.name, request.prof)
        put(ui, 40, y - 7, 236, row.name, 11, nameColour)
        rowHit(ui, 34, y - 2, 242, 22, row.item, row.name, row.spell, row.name, request.prof)
        put(ui, 280, y - 7, 44, tostring(row.learn or "-") .. (unsure and "?" or ""), 11, C.dim, "RIGHT")
        put(ui, 328, y - 7, 50, tostring(row.yellow or "-"), 11, C.dim, "RIGHT")
        put(ui, 382, y - 7, 44, tostring(row.grey or "-"), 11, C.dim, "RIGHT")
        put(ui, 430, y - 7, 88, row.mats and ns.Coins(row.mats) or "-", 11, C.dim, "RIGHT")
        put(ui, 522, y - 7, 88, row.perPoint and ns.Coins(row.perPoint) or "-", 11, row.perPoint and C.accent or C.faint, "RIGHT")
        put(ui, 626, y - 7, statusWidth, statusText, statusWidth > 100 and 10 or 11, statusColour)
        if avoided then
            rowButton(ui, CONTENT_W - 66, y - 2, "Allow", function() ns.ToggleAvoid(row.spell) end)
        elseif row.via then
            rowButton(ui, CONTENT_W - 66, y - 2, "Avoid", function() ns.ToggleAvoid(row.spell) end)
        end
        y = y - height
    end
    return y
end

local PROFIT_COLUMNS = {
    { title = "RECIPE", x = 40, w = 216 }, { title = "SELLS AS", x = 260, w = 138 }, { title = "SELL AT", x = 402, w = 54 },
    { title = "PROFIT EACH", x = 460, w = 92, right = true }, { title = "SOLD / DAY", x = 556, w = 72, right = true },
    { title = "SKILL-UP", x = 632, w = 64, right = true }, { title = "PROFIT / DAY", x = 700, w = 100, right = true },
}

local function renderProfit(ui, plan, y)
    local request = ns.request
    local ok, result = pcall(ns.BuildSuggest, request, ns.profile, ns.prices)
    if not ok then return banner(ui, y, tostring(result), C.bad) end
    local shown = {}
    for _, row in ipairs(result.rows) do
        if not request.bothOnly or row.both then table.insert(shown, row) end
    end
    if #shown == 0 then return banner(ui, y, "No recipe makes a profit at current prices with these options.", C.info) end
    y = banner(ui, y, "Recipes available at skill " .. request["from"] .. " that sell for more than their materials. Sell at: AH means the market price less the 5% cut; Vendor means the item has no usable AH price. Profit per day assumes you sell at most 20 a day.", C.info)
    y = heading(ui, y, PROFIT_COLUMNS)
    for index, row in ipairs(shown) do
        local note = row.source and row.via ~= "known" and row.via ~= "auto" and ns.SourceForFaction(row.source, ns.profile and ns.profile.faction) or nil
        local noteHeight = 0
        if note then noteHeight = put(ui, 40, y - 24, CONTENT_W - 54, note, 10, C.faint, "LEFT", true) + 4 end
        local height = 26 + noteHeight
        stripe(ui, y, height, index)
        rowIcon(ui, 10, y - 3, 20, row.item, row.product, row.spell, row.recipe, request.prof)
        local chance = math.floor(row.chance * 100 + 0.5)
        put(ui, 40, y - 7, 216, row.recipe, 11, BAND[row.colour or ""] or C.text)
        rowHit(ui, 34, y - 2, 222, 22, row.item, row.product, row.spell, row.recipe, request.prof)
        put(ui, 260, y - 7, 138, row.product, 11, QUALITY[row.q or 1] or C.dim)
        put(ui, 402, y - 7, 54, row.sellHow == "vendor" and "Vendor" or "AH", 11, row.sellHow == "vendor" and C.dim or C.info)
        put(ui, 460, y - 7, 92, ns.Coins(row.margin), 11, C.good, "RIGHT")
        put(ui, 556, y - 7, 72, string.format("%.1f", row.perDay), 11, C.dim, "RIGHT")
        put(ui, 632, y - 7, 64, chance > 0 and (chance .. "%") or "-", 11, chance > 0 and C.text or C.faint, "RIGHT")
        put(ui, 700, y - 7, 100, ns.Coins(row.score), 11, C.accent, "RIGHT")
        y = y - height
    end
    return y
end

local STATS_COLUMNS = {
    { title = "", x = 10, w = 100 }, { title = "POINTS", x = 114, w = 60, right = true }, { title = "CRAFTS", x = 178, w = 60, right = true },
    { title = "MATERIALS USED", x = 242, w = 100, right = true }, { title = "SELL-BACK", x = 346, w = 96, right = true },
    { title = "NET COST", x = 446, w = 90, right = true }, { title = "PER POINT", x = 540, w = 84, right = true },
    { title = "ON AVERAGE", x = 628, w = 84, right = true }, { title = "LUCK", x = 716, w = 84, right = true },
}
local STATS_RECIPES = {
    { title = "RECIPE (ALL TIME)", x = 40, w = 256 }, { title = "CRAFTS", x = 300, w = 60, right = true }, { title = "POINTS", x = 364, w = 60, right = true },
    { title = "EXPECTED", x = 428, w = 80, right = true }, { title = "LUCK", x = 512, w = 70, right = true },
    { title = "NET COST", x = 586, w = 100, right = true }, { title = "PER POINT", x = 690, w = 110, right = true },
}

local function luckText(luck)
    if not luck then return "-", C.faint end
    local percent = math.floor(luck * 100 + 0.5)
    return percent .. "%", (percent >= 100 and C.good) or (percent < 80 and C.warn) or C.text
end

local resetArmed
local function renderStats(ui, plan, y)
    local request = ns.request
    local char, prof = request.char or ns.StatsCharacter(), request.prof
    local session, total = ns.StatsFor(char, prof)
    local mine = char == ns.StatsCharacter()
    if not total and not session then
        resetArmed = nil
        return banner(ui, y, "Nothing tracked yet for " .. prof .. " on this character.\n"
            .. (mine and "Craft something and the numbers appear here. Tracking runs whether or not this window is open."
                or "Tracking only counts the character you are logged in on."), C.info)
    end
    local top = y
    y = banner(ui, y, "What your crafting actually cost. Gold is the value of the materials used and of what was made, at prices when crafted; recipes bought and training fees are not counted."
        .. "\nOn average: the cost per point with average luck. Luck: points gained against the average for those crafts; under 100% means an unlucky run.", C.info, 232)
    local armed = resetArmed == char .. "/" .. prof
    rowButton(ui, CONTENT_W - 222, top - 6, "Reset session", function()
        resetArmed = nil
        ns.ResetStats(char, prof, "session")
        ns.RenderUI()
    end, 96)
    rowButton(ui, CONTENT_W - 120, top - 6, armed and "Click to confirm" or "Reset all", function()
        if armed then
            resetArmed = nil
            ns.ResetStats(char, prof, "all")
        else
            resetArmed = char .. "/" .. prof
        end
        ns.RenderUI()
    end, 108)
    y = heading(ui, y, STATS_COLUMNS)
    local index = 0
    for _, entry in ipairs({ { "This session", session }, { "All time", total } }) do
        local record = entry[2]
        if record then
            index = index + 1
            stripe(ui, y, 26, index)
            local net, per, planned, luck = ns.StatsFigures(record)
            local luckLabel, luckColour = luckText(luck)
            put(ui, 10, y - 7, 100, entry[1], 11, C.text)
            put(ui, 114, y - 7, 60, tostring(record.points), 11, C.text, "RIGHT")
            put(ui, 178, y - 7, 60, tostring(record.crafts), 11, C.dim, "RIGHT")
            put(ui, 242, y - 7, 100, ns.Coins(record.mats), 11, C.dim, "RIGHT")
            put(ui, 346, y - 7, 96, ns.Coins(record.back), 11, C.dim, "RIGHT")
            put(ui, 446, y - 7, 90, ns.Coins(net), 11, C.text, "RIGHT")
            put(ui, 540, y - 7, 84, per and ns.Coins(per) or "-", 11, C.accent, "RIGHT")
            put(ui, 628, y - 7, 84, planned and ns.Coins(planned) or "-", 11, C.dim, "RIGHT")
            put(ui, 716, y - 7, 84, luckLabel, 11, luckColour, "RIGHT")
            y = y - 26
        end
    end
    local rows = {}
    for spell, record in pairs(total and total.recipes or {}) do
        if type(record) == "table" then table.insert(rows, { spell = spell, record = record }) end
    end
    if #rows == 0 then return y end
    table.sort(rows, function(a, b)
        if a.record.crafts ~= b.record.crafts then return a.record.crafts > b.record.crafts end
        return a.spell < b.spell
    end)
    y = heading(ui, y - 14, STATS_RECIPES)
    for position, entry in ipairs(rows) do
        local record, recipe = entry.record, ns.RecipeBySpell(entry.spell)
        local net, per, _, luck = ns.StatsFigures(record)
        local luckLabel, luckColour = luckText(luck)
        local product = recipe and recipe.products and recipe.products[1] and recipe.products[1].item or nil
        stripe(ui, y, 26, position)
        if product then rowIcon(ui, 10, y - 3, 20, product, recipe.name, entry.spell, recipe.name, recipe.prof) end
        put(ui, 40, y - 7, 256, recipe and recipe.name or ("Spell " .. tostring(entry.spell)), 11, C.text)
        put(ui, 300, y - 7, 60, tostring(record.crafts), 11, C.dim, "RIGHT")
        put(ui, 364, y - 7, 60, tostring(record.points), 11, C.text, "RIGHT")
        put(ui, 428, y - 7, 80, string.format("%.1f", record.expected), 11, C.dim, "RIGHT")
        put(ui, 512, y - 7, 70, luckLabel, 11, luckColour, "RIGHT")
        put(ui, 586, y - 7, 100, ns.Coins(net), 11, C.dim, "RIGHT")
        put(ui, 690, y - 7, 110, per and ns.Coins(per) or "-", 11, C.accent, "RIGHT")
        y = y - 26
    end
    return y
end

local RENDERERS = { Route = renderRoute, Shopping = renderShopping, Recipes = renderRecipes, Profit = renderProfit, Stats = renderStats }

function ns.RenderUI()
    local ui = ns.UI
    if not ui or not ui.currentPlan then return end
    local plan = ui.currentPlan
    releaseAll(ui)
    for name, tab in pairs(ui.tabs) do
        local active = name == ui.activeTab
        local colour = active and C.accent or C.dim
        tab.label:SetTextColor(colour[1], colour[2], colour[3])
        if active then tab.under:Show() else tab.under:Hide() end
    end
    local view = FRAME_H - SCROLL_TOP - FOOTER_H - 8
    ui.scroll:ClearAllPoints()
    ui.scroll:SetPoint("TOPLEFT", MAIN_X, -SCROLL_TOP)
    if ui.activeTab == "Shopping" then
        local search = plan.tsmString or ""
        ui.copyBox:SetText(search)
        if search == "" then
            ui.copyLabel:SetText("Nothing in this route needs the auction house.")
        else
            ui.copyLabel:SetText("Shift-click an item above to search for it in TSM (auction house open, Browse tab). For the whole list: Select buy list, Ctrl+C, paste into TSM's search.")
        end
        ui.copyBar:Show()
        view = view - COPY_H
        ui.scroll:SetPoint("BOTTOMRIGHT", -26, FOOTER_H + 8 + COPY_H)
    else
        ui.copyBar:Hide()
        ui.scroll:SetPoint("BOTTOMRIGHT", -26, FOOTER_H + 8)
    end
    local y = -2
    for _, note in ipairs(ns.Notices()) do y = banner(ui, y, note, C.warn) end
    y = (RENDERERS[ui.activeTab] or renderRoute)(ui, plan, y)
    ui.area.SetExtent(view, -y + 8)
end

function ns.ShowTab(name)
    local ui = ns.UI
    if not ui or not RENDERERS[name] then return end
    ui.activeTab = name
    ui.area.offset = 0
    ns.RenderUI()
end

local function failedPlan(request, message)
    return {
        reached = request["from"] or 0, to = request.to or 0, ["from"] = request["from"] or 0, failed = true,
        summary = { crafts = 0, spend = 0, sellBack = 0, net = 0, spendPatterns = 0, safeSpend = 0, safeCrafts = 0, thinSupply = 0, buyAH = 0, buyVendor = 0 },
        steps = {}, shopping = {}, warnings = { message }, tsmString = "", prices = {}, options = {},
    }
end

local function refreshSidebar(ui, request, char)
    ui.charDrop.SetValues(ns.SortedCharacters(ns.profile))
    ui.charDrop.SetText(char and (char.name or request.char) or "No TSM character data")
    if char and char.money then ui.gold:SetText("Gold  " .. ns.Coins(char.money)) else ui.gold:SetText("") end
    local known = 0
    for name in pairs(ui.profRows) do
        if char and char.profs and char.profs[name] then known = known + 1 end
    end
    -- With nothing recorded for the character there is nothing to narrow the list to.
    local all = known == 0 or (ns.DB and ns.DB.settings.allProfessions == true)
    local shown = 0
    for _, row in ipairs(ui.profOrder) do
        local mine = char and char.profs and char.profs[row.profession] ~= nil
        if all or mine or row.profession == request.prof then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -108 - shown * 40)
            row:Show()
            shown = shown + 1
        else
            row:Hide()
        end
    end
    local below = -108 - shown * 40 - 8
    ui.allProfs:ClearAllPoints()
    ui.profNote:ClearAllPoints()
    if known == 0 then
        ui.allProfs:Hide()
        ui.profNote:SetPoint("TOPLEFT", 12, below)
        ui.profNote:SetText("TradeSkillMaster has no professions for this character yet. Open each profession window once.")
        ui.profNote:Show()
    elseif known == #ui.profOrder then
        ui.allProfs:Hide(); ui.profNote:Hide()
    else
        ui.allProfs:SetPoint("TOPLEFT", 12, below)
        ui.allProfs.label:SetText(all and "Show only mine" or "Show all professions")
        ui.allProfs:Show(); ui.profNote:Hide()
    end
    for name, row in pairs(ui.profRows) do
        local values = char and char.profs and char.profs[name] or nil
        local level = values and math.max(0, math.min(ns.MAX_SKILL, tonumber(values.level) or 0)) or nil
        local active = name == request.prof
        if active then row.selected:Show(); row.bar:Show() else row.selected:Hide(); row.bar:Hide() end
        local colour = active and C.accent or (level and C.text or C.faint)
        row.label:SetTextColor(colour[1], colour[2], colour[3])
        row.level:SetText(level and tostring(level) or "")
        row.icon:SetAlpha(level and 1 or 0.35)
        if level and level > 0 then
            row.meter:SetWidth(math.max(1, (SIDE_W - 56) * level / ns.MAX_SKILL))
            row.meter:Show(); row.track:Show()
        else
            row.meter:Hide()
            if level then row.track:Show() else row.track:Hide() end
        end
    end
end

local function segment(texture, from, to)
    local left = math.floor(MAIN_W * from / ns.MAX_SKILL + 0.5)
    local width = math.floor(MAIN_W * to / ns.MAX_SKILL + 0.5) - left
    if width <= 0 then texture:Hide(); return end
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", left, 0)
    texture:SetWidth(width)
    texture:Show()
end

local function refreshSummary(ui, request, char, plan)
    local summary = plan.summary
    local name = char and (char.name or request.char) or nil
    ui.title:SetText(request.prof)
    local values = char and char.profs and char.profs[request.prof] or nil
    if name and values then
        ui.subtitle:SetText(name .. "    skill " .. (tonumber(values.level) or 0) .. " of " .. ns.MAX_SKILL)
    elseif name then
        ui.subtitle:SetText(name .. "    not learned")
    else
        ui.subtitle:SetText("Set the skill range by hand")
    end
    local from, to, reached = request["from"], request.to, plan.reached or request["from"]
    if from <= 1 then from = 0 end
    segment(ui.bar.earned, 0, from)
    segment(ui.bar.planned, from, math.max(from, math.min(reached, to)))
    segment(ui.bar.missing, math.max(from, math.min(reached, to)), to)
    local short = reached < to
    local points = math.max(1, reached - request["from"])
    ui.cards.reach.value:SetText((short and hex(C.bad) or hex(C.good)) .. reached .. DONE .. hex(C.dim) .. " of " .. to .. DONE)
    ui.cards.net.value:SetText(ns.Coins(summary.net))
    ui.cards.perPoint.value:SetText(summary.crafts > 0 and ns.Coins(summary.net / points) or "-")
    ui.cards.spend.value:SetText(ns.Coins(summary.spend))
    ui.cards.sellBack.value:SetText(ns.Coins(summary.sellBack))
    local outlet = request.credit == "ah" and "AH, ELSE VENDOR" or (request.credit == "none" and "NOT COUNTED" or "VENDOR")
    ui.cards.sellBack.caption:SetText("SELL-BACK (" .. outlet .. ")")
    ui.cards.crafts.value:SetText(tostring(summary.crafts))
end

function ns.RefreshUI()
    local ui = ns.UI
    if not ui then return end
    if not ns.request then ns.request = ns.DefaultRequest(ns.profile) end
    ns.DB = ns.DB or { settings = {}, ticks = {} }
    local request = ns.request
    request.exclude = request.exclude or {}
    ns.ClampRange(request)
    local saved = {}
    for key, value in pairs(request) do if key ~= "exclude" and key ~= "lock" then saved[key] = value end end
    ns.DB.settings.request = saved
    ns.DB.settings.exclude = copyTable(request.exclude)

    ui.fromEdit:SetText(string.format("%d", request["from"]))
    ui.toEdit:SetText(string.format("%d", request.to))
    local char = ns.profile and request.char and ns.profile.chars[request.char] or nil
    refreshSidebar(ui, request, char)
    for _, definition in ipairs(OPTIONS) do
        ui.options[definition.key]:SetChecked(definition.get(request) and true or false)
    end
    for _, chip in pairs(ui.chips) do
        local on = chip.definition.get(request) and true or false
        local fill, ink = on and C.accent or C.raised, on and { 0.10, 0.08, 0.03 } or C.dim
        chip.on = on
        chip.bg:SetColorTexture(fill[1], fill[2], fill[3], 1)
        chip.label:SetTextColor(ink[1], ink[2], ink[3])
    end

    -- One kept route per character and profession, so looking at another profession and coming back
    -- finds the route as it was left.
    local settings = ns.DB.settings
    if type(settings.locks) ~= "table" then settings.locks = {} end
    local slot = tostring(request.char) .. "|" .. tostring(request.prof)
    local key, kept = ns.RouteKey(request), settings.locks[slot]
    local clock = rawget(_G, "time")
    local now = type(clock) == "function" and clock() or 0
    local keep = not ns.freshPlan and type(kept) == "table" and type(kept.steps) == "table" and kept.key == key
        and now - (tonumber(kept.at) or 0) < ns.KEEP_SECONDS
    ns.freshPlan = nil
    request.lock = keep and kept or nil
    local ok, plan = pcall(ns.BuildPlan, request, ns.profile, ns.prices)
    if ok then
        if type(plan.lock) == "table" then
            plan.lock.key = key
            plan.lock.at = keep and tonumber(kept.at) or now
            settings.locks[slot] = plan.lock
            for other, lock in pairs(settings.locks) do
                if type(lock) ~= "table" or now - (tonumber(lock.at) or 0) >= ns.KEEP_SECONDS then settings.locks[other] = nil end
            end
        end
        local route = plan.options.routeSearch or "fewest recipe changes"
        if plan.locked then route = route .. ", kept until you press Plan" end
        ui.status:SetText("Prices: " .. (plan.prices.source or "Vendor only") .. "        Route: " .. route)
        local explained = plan.lockBroken and ns.routeExplained and ns.routeExplained[plan.lockBroken.spell]
        if explained then ns.routeExplained[plan.lockBroken.spell] = nil end
        if plan.locked and plan.lockBroken and not ns.quietBreak and not explained then
            say((plan.lockBroken.name or "A recipe") .. " is out, so the route was chosen again from skill "
                .. plan.lockBroken.skill .. " for that stretch. The rest is as planned.")
        end
    else
        local message = string.gsub(tostring(plan), "^.-:%d+: ", "")
        plan = failedPlan(request, message)
        ui.status:SetText("Planning failed")
    end
    -- For recipes that may be sold out, say what going without would cost (a few at most).
    -- These are extra plans, so a redraw caused by crafting reuses the last answers instead
    -- of working them out again on every craft.
    local checked = 0
    if not ns.liveRedraw or not ui.without then ui.without = {} end
    for _, step in ipairs(plan.steps) do
        if step.type == "step" and step.pattern and step.pattern.stock and ui.without[step.spell] then
            step.without = ui.without[step.spell]
        elseif step.type == "step" and step.pattern and step.pattern.stock and checked < 6 then
            checked = checked + 1
            local without = copyTable(request)
            without.exclude = copyTable(request.exclude)
            table.insert(without.exclude, step.spell)
            local fine, other = pcall(ns.BuildPlan, without, ns.profile, ns.prices)
            if fine and other.reached < plan.reached then
                step.without = "Without it the route stops at skill " .. other.reached .. "."
            elseif fine then
                local extra = other.summary.net - plan.summary.net
                step.without = extra > 0 and ("Without it the route costs " .. ns.Coins(extra) .. " more.") or "The route costs no more without it."
            end
            ui.without[step.spell] = step.without
        end
    end
    request.lock = nil
    ui.currentPlan = plan
    refreshSummary(ui, request, char, plan)
    ns.RenderUI()
end

-- All characters -----------------------------------------------------------------

local OVERVIEW_W, OVERVIEW_H = 720, 480

function ns.ShowOverview()
    local ui = ns.UI
    if not ui then return end
    if not ui.overview then
        local frame = CreateFrame("Frame", "ProfessionPlannerOverview", UIParent)
        frame:SetSize(OVERVIEW_W, OVERVIEW_H)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        frame:EnableMouse(true)
        W.fill(frame, "BACKGROUND", C.bg, 1)
        W.border(frame, C.accentDark, 1)
        local special = rawget(_G, "UISpecialFrames")
        if type(special) == "table" then table.insert(special, "ProfessionPlannerOverview") end
        local title = W.text(frame, 14, C.accent, "Cost to each character's next trainer cap")
        title:SetPoint("TOPLEFT", 16, -14)
        local hint = W.text(frame, 10, C.faint, "Click a row to plan it.")
        hint:SetPoint("TOPLEFT", 16, -34)
        local close = W.button(frame, "Close", 70, 24, nil, function() frame:Hide() end)
        close:SetPoint("TOPRIGHT", -12, -10)
        local titles = { { "CHARACTER", 12, 150 }, { "PROFESSION", 166, 130 }, { "SKILL", 300, 90 }, { "YOU SPEND", 394, 100, true },
            { "NET COST", 498, 100, true }, { "NOTE", 612, 80 } }
        for _, column in ipairs(titles) do
            local label = W.text(frame, 9, C.faint, column[1])
            label:SetWidth(column[3])
            label:SetJustifyH(column[4] and "RIGHT" or "LEFT")
            label:SetPoint("TOPLEFT", 12 + column[2], -58)
        end
        frame.area = W.scroll(frame, OVERVIEW_W - 36)
        frame.area.frame:SetPoint("TOPLEFT", 12, -76)
        frame.area.frame:SetPoint("BOTTOMRIGHT", -24, 12)
        frame.rows = {}
        frame.empty = W.text(frame.area.content, 11, C.dim, "")
        frame.empty:SetPoint("TOPLEFT", 12, -10)
        frame.empty:SetWidth(OVERVIEW_W - 60)
        ui.overview = frame
    end
    local frame = ui.overview
    local ok, result = pcall(ns.BuildOverview, ns.request, ns.profile, ns.prices)
    local rows = ok and result.rows or {}
    for index, data in ipairs(rows) do
        local row = frame.rows[index]
        if not row then
            row = CreateFrame("Button", nil, frame.area.content)
            row:SetSize(OVERVIEW_W - 36, 26)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 26)
            if index % 2 == 0 then W.fill(row, "BACKGROUND", C.panelAlt) end
            W.fill(row, "HIGHLIGHT", { 1, 1, 1 }, 0.07)
            row.cells = {}
            for cell, column in ipairs({ { 12, 150 }, { 166, 130 }, { 300, 90 }, { 394, 100, true }, { 498, 100, true }, { 612, 80 } }) do
                local label = W.text(row, 11, C.text, "")
                label:SetWidth(column[2])
                label:SetWordWrap(false)
                label:SetJustifyH(column[3] and "RIGHT" or "LEFT")
                label:SetPoint("LEFT", column[1], 0)
                row.cells[cell] = label
            end
            frame.rows[index] = row
        end
        local short = (data.reached or data.to) < data.to
        row.cells[1]:SetText(data.char)
        row.cells[2]:SetText(data.prof)
        row.cells[3]:SetText(data["from"] .. " -> " .. data.to)
        row.cells[4]:SetText(ns.Coins(data.spend))
        row.cells[5]:SetText(ns.Coins(data.net))
        row.cells[6]:SetText(short and (hex(C.warn) .. "stops at " .. data.reached .. DONE) or "")
        row:SetScript("OnClick", function()
            local request = ns.request
            request.char, request.prof = data.charId, data.prof
            request["from"], request.to = 1, 0
            ns.SyncRequest(true)
            frame:Hide()
            ns.RefreshUI()
        end)
        row:Show()
    end
    for index = #rows + 1, #frame.rows do frame.rows[index]:Hide() end
    if not ok then
        frame.empty:SetText("Could not build the overview: " .. tostring(result))
    elseif #rows == 0 then
        frame.empty:SetText("TSM has no profession roster for this realm and faction.")
    else
        frame.empty:SetText("")
    end
    frame.area.offset = 0
    frame.area.SetExtent(OVERVIEW_H - 88, #rows * 26 + 4)
    frame:Show()
end

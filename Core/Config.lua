local addonName, ns = ...

ns.defaults = {
    showStartupMessage = true,
    visibilityMode = "ALWAYS",
    visibility = {},
    showHandle = true,
    showTargetBuffs = true,
    showPartyBuffs = true,
    showPartyCoverage = true,
    thanksEnabled = false,
    thanksChannel = "WHISPER",
    thanksMessage = "Thanks for the {buff}!",
    showPetBuffs = false,
    showMinimap = true,
    ignoreBuffsInRestedAreas = false,
    minimapAngle = 225,
    palettePoint = { "CENTER", "CENTER", 0, -120 },
    settingsPoint = { "CENTER", "CENTER", 0, 0 },
    iconSize = 40,
    orientation = "VERTICAL",
    reminderPercent = { buff = 10, food = 10, scroll = 10, flask = 10, weapon = 10, buffBySpell = {}, item = {} },
    consumableAuras = {},
    excludedConsumables = {},
    excludedBuffs = {},
    categories = { food = true, scroll = true, flask = true, weapon = true },
    maxAlternatives = 3,
    expanded = {},
    preferred = {},
}

local function copyDefaults(destination, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(destination[key]) ~= "table" then destination[key] = {} end
            copyDefaults(destination[key], value)
        elseif destination[key] == nil then
            destination[key] = value
        end
    end
    return destination
end

local function validPoint(point)
    if type(point) ~= "table" then return false end
    local anchors = {
        TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
        RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
    }
    local x, y = tonumber(point[3]), tonumber(point[4])
    return anchors[point[1]] and anchors[point[2]] and x and y and x == x and y == y
end

function ns.InitConfig()
    BuffsmithDB = type(BuffsmithDB) == "table" and BuffsmithDB or {}
    BuffsmithDB = copyDefaults(BuffsmithDB, ns.defaults)
    if type(BuffsmithDB.categories) ~= "table" then BuffsmithDB.categories = {} end
    if type(BuffsmithDB.visibility) ~= "table" then BuffsmithDB.visibility = {} end
    if type(BuffsmithDB.expanded) ~= "table" then BuffsmithDB.expanded = {} end
    if type(BuffsmithDB.preferred) ~= "table" then BuffsmithDB.preferred = {} end
    if type(BuffsmithDB.reminderPercent) ~= "table" then BuffsmithDB.reminderPercent = {} end
    if type(BuffsmithDB.consumableAuras) ~= "table" then BuffsmithDB.consumableAuras = {} end
    if type(BuffsmithDB.excludedConsumables) ~= "table" then BuffsmithDB.excludedConsumables = {} end
    if type(BuffsmithDB.excludedBuffs) ~= "table" then BuffsmithDB.excludedBuffs = {} end
    if type(BuffsmithDB.reminderPercent.buffBySpell) ~= "table" then BuffsmithDB.reminderPercent.buffBySpell = {} end
    if type(BuffsmithDB.reminderPercent.item) ~= "table" then BuffsmithDB.reminderPercent.item = {} end
    -- showPalette and the Never visibility mode were two switches for one
    -- outcome. The saved value folds into the mode and stops being read.
    if BuffsmithDB.showPalette == false then BuffsmithDB.visibilityMode = "NEVER" end
    BuffsmithDB.showPalette = nil
    if BuffsmithDB.visibilityMode ~= "ALWAYS" and BuffsmithDB.visibilityMode ~= "NEVER" then BuffsmithDB.visibilityMode = "ALWAYS" end
    if type(BuffsmithDB.showHandle) ~= "boolean" then BuffsmithDB.showHandle = true end
    if type(BuffsmithDB.showTargetBuffs) ~= "boolean" then BuffsmithDB.showTargetBuffs = true end
    if type(BuffsmithDB.showPartyBuffs) ~= "boolean" then BuffsmithDB.showPartyBuffs = true end
    if type(BuffsmithDB.showPartyCoverage) ~= "boolean" then BuffsmithDB.showPartyCoverage = true end
    if type(BuffsmithDB.thanksEnabled) ~= "boolean" then BuffsmithDB.thanksEnabled = false end
    if BuffsmithDB.thanksChannel ~= "WHISPER" and BuffsmithDB.thanksChannel ~= "SAY" and BuffsmithDB.thanksChannel ~= "PARTY" then BuffsmithDB.thanksChannel = "WHISPER" end
    if type(BuffsmithDB.thanksMessage) ~= "string" or BuffsmithDB.thanksMessage == "" then BuffsmithDB.thanksMessage = "Thanks for the {buff}!" end
    BuffsmithDB.thanksMessage = BuffsmithDB.thanksMessage:gsub("[\r\n]+", " "):sub(1, 240)
    if type(BuffsmithDB.showPetBuffs) ~= "boolean" then BuffsmithDB.showPetBuffs = false end
    if type(BuffsmithDB.showStartupMessage) ~= "boolean" then BuffsmithDB.showStartupMessage = true end
    if type(BuffsmithDB.showMinimap) ~= "boolean" then BuffsmithDB.showMinimap = true end
    if type(BuffsmithDB.ignoreBuffsInRestedAreas) ~= "boolean" then BuffsmithDB.ignoreBuffsInRestedAreas = false end
    BuffsmithDB.scale = nil
    BuffsmithDB.iconSize = math.max(24, math.min(64, math.floor((tonumber(BuffsmithDB.iconSize) or 40) + 0.5)))
    if BuffsmithDB.orientation ~= "HORIZONTAL" and BuffsmithDB.orientation ~= "VERTICAL" then
        BuffsmithDB.orientation = "VERTICAL"
    end
    BuffsmithDB.minimapAngle = math.max(0, math.min(360, tonumber(BuffsmithDB.minimapAngle) or 225))
    BuffsmithDB.maxAlternatives = math.max(1, math.min(3,
        math.floor((tonumber(BuffsmithDB.maxAlternatives) or 3) + 0.5)))
    for _, category in ipairs({ "buff", "food", "scroll", "flask", "weapon" }) do
        BuffsmithDB.reminderPercent[category] = math.max(0, math.min(50,
            math.floor((tonumber(BuffsmithDB.reminderPercent[category]) or 10) + 0.5)))
    end
    if not validPoint(BuffsmithDB.palettePoint) then
        BuffsmithDB.palettePoint = { "CENTER", "CENTER", 0, -120 }
    end
    if not validPoint(BuffsmithDB.settingsPoint) then
        BuffsmithDB.settingsPoint = { "CENTER", "CENTER", 0, 0 }
    end
    ns.db = BuffsmithDB
    return ns.db
end

function ns.Set(key, value)
    ns.db[key] = value
    ns.RefreshAll()
end

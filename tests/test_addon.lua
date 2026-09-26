package.path = "./tests/hammercore/?.lua;" .. package.path
local wow = require("wow")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

-- Client APIs Buffsmith uses beyond the HammerCore harness, as plain stubs.
local function installClient()
    RegisterStateDriver, UnregisterStateDriver = function() end, function() end
    RegisterAttributeDriver = function() end
    SecureHandlerWrapScript = function() end
    GetSpecialization = function() return 1 end
    UnitClass = function() return "Paladin", "PALADIN" end
    UnitName = function() return "Tester" end
    UnitGUID = function(unit) return "guid-" .. tostring(unit) end
    UnitExists = function(unit) return unit == "player" end
    UnitIsUnit = function(a, b) return a == b end
    UnitIsPlayer = function() return true end
    UnitCanAssist = function() return true end
    UnitIsDeadOrGhost = function() return false end
    IsInGroup, IsInRaid, IsResting = function() return false end, function() return false end, function() return false end
    IsShiftKeyDown = function() return false end
    GetTime = function() return 100 end
    GetBindingKey, GetBindingText = function() return nil end, function(key) return key end
    SetBinding, SaveBindings, GetCurrentBindingSet = function() return true end, function() end, function() return 1 end
    GetWeaponEnchantInfo = function() return false end
    C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end }
    C_UnitAuras = { GetAuraDataByIndex = function() return nil end, GetUnitAuraBySpellID = function() return nil end }
    C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. id, iconID = 1 } end }
    C_SpellBook = { IsSpellKnown = function(id) return id == 465 or id == 19740 end }
    Enum = { SpellBookSpellBank = { Player = 0 } }
    C_ChatInfo = {}
    EmoteList, TextEmoteSpeechList = {}, {}
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    NUM_BAG_SLOTS = 4
end

-- Load Buffsmith exactly as a TOC lists it.
local function loadAddon(tocName, saved)
    wow.Install({ Buffsmith = { Version = "0.1.4-dev1", ["X-Buffsmith-Target"] = tocName:find("Camelot") and "Camelot" or nil } })
    installClient()
    BuffsmithDB = saved
    local ns = {}
    for line in io.lines(tocName) do
        local entry = line:gsub("\r", ""):gsub("\\", "/")
        if entry:match("%.xml$") then
            wow.LoadHammerCore(entry:match("^(.*)/[^/]+$"), "Buffsmith", ns)
        elseif entry:match("%.lua$") then
            assert(loadfile(entry))("Buffsmith", ns)
        end
    end
    local events = _G.BuffsmithEventFrame
    events.scripts.OnEvent(events, "ADDON_LOADED", "Buffsmith")
    events.scripts.OnEvent(events, "PLAYER_LOGIN")
    return ns
end

for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    -- An existing player's saved choices carry over to HammerCore.
    local ns = loadAddon(toc, { showStartupMessage = true, showMinimap = false, minimapAngle = 40,
        settingsPoint = { "TOPLEFT", "TOPLEFT", 10, -10 } })
    local HC = ns.HammerCore
    equal(wow.LastPrint(), "Buffsmith v0.1.4-dev1 loaded - type /buffsmith for settings, /buffsmith help for commands",
        toc .. ": standard login message")
    equal(HC.State().minimap, false, toc .. ": hidden minimap choice is kept")
    equal(HC.State().minimapAngle, 40, toc .. ": minimap position is kept")
    equal(HC.State().settingsPoint[3], 10, toc .. ": settings position is kept")
    equal(BuffsmithDB.showMinimap, nil, toc .. ": old minimap key is removed")
    equal(HC.Minimap.button:IsShown(), false, toc .. ": minimap stays hidden")

    for _, slash in ipairs({ "/buffsmith", "/bs", "/bsmith" }) do
        local found = false
        for index = 1, 3 do
            if _G["SLASH_BUFFSMITH" .. index] == slash then found = true end
        end
        equal(found, true, toc .. ": " .. slash .. " is registered")
    end

    SlashCmdList.BUFFSMITH("")
    equal(HC.Settings:IsShown(), true, toc .. ": the bare command opens settings")
    local names = {}
    for _, spec in ipairs(HC.Settings.order) do names[#names + 1] = spec.name end
    equal(table.concat(names, ","),
        "Visibility,Appearance,Buffs,Consumables,Ignored,Key Bindings,Thank You,Theme,Commands,Troubleshooting,About",
        toc .. ": rail order")
    local failures = {}
    for name, err in pairs(HC.Settings.errors) do failures[#failures + 1] = name .. ": " .. err end
    equal(table.concat(failures, "; "), "", toc .. ": every settings page builds")
    for _, spec in ipairs(HC.Settings.order) do
        HC.Settings:Show(spec.name)
        equal(HC.Settings.selected, spec.name, toc .. ": " .. spec.name .. " opens")
    end

    SlashCmdList.BUFFSMITH("toggle")
    equal(ns.db.visibilityMode, "NEVER", toc .. ": toggle hides the bar")
    SlashCmdList.BUFFSMITH("toggle")
    equal(ns.db.visibilityMode, "ALWAYS", toc .. ": toggle shows it again")
    SlashCmdList.BUFFSMITH("lock")
    equal(ns.db.showHandle, false, toc .. ": lock hides the handle")
    SlashCmdList.BUFFSMITH("unlock")
    equal(ns.db.showHandle, true, toc .. ": unlock shows it")
    ns.db.palettePoint = { "TOP", "TOP", 5, 5 }
    SlashCmdList.BUFFSMITH("reset position")
    equal(ns.db.palettePoint[1], "CENTER", toc .. ": reset position centres the bar")
    SlashCmdList.BUFFSMITH("scan")
    equal(wow.LastPrint(), "Buffsmith: bags scanned: food 0, scroll 0, flask 0, weapon 0", toc .. ": scan reports")
    SlashCmdList.BUFFSMITH("version")
    equal(wow.LastPrint():find(toc:find("Camelot") and "(WoW Forever)" or "(Retail)", 1, true) ~= nil, true,
        toc .. ": version names the client")
    SlashCmdList.BUFFSMITH("debug")
    equal(HC.Copy.frame.edit:GetText():find("Known self-buffs", 1, true) ~= nil, true,
        toc .. ": debug includes Buffsmith's report")

    -- The rail preview button and the preview command agree.
    HC.Settings:Show()
    equal(HC.Settings.railButton:GetText(), "Preview on screen", toc .. ": rail offers the preview")
    SlashCmdList.BUFFSMITH("preview")
    equal(HC.Settings.railButton:GetText(), "Hide preview", toc .. ": preview command updates the rail")

    wow.printed = {}
    SlashCmdList.BUFFSMITH("help")
    local sawAction = false
    for _, line in ipairs(wow.printed) do
        if wow.Plain(line) == "  Shift-right-click an icon - Ignore it; restore on Ignored" then sawAction = true end
    end
    equal(sawAction, true, toc .. ": bar actions are listed in help")

    -- Old spellings are gone.
    SlashCmdList.BUFFSMITH("copy")
    equal(wow.LastPrint(), "Buffsmith: unknown command. Type /buffsmith help for the list.", toc .. ": old commands are removed")
end

io.write("addon tests passed\n")

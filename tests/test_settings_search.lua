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
    UnitIsPVP, UnitIsPVPFreeForAll = function() return false end, function() return false end
    UnitCanAssist = function() return true end
    UnitIsDeadOrGhost = function() return false end
    IsInGroup, IsInRaid, IsResting = function() return false end, function() return false end, function() return false end
    IsShiftKeyDown = function() return false end
    GetTime = function() return 100 end
    GetBindingKey, GetBindingText = function() return nil end, function(key) return key end
    SetBinding, SaveBindings, GetCurrentBindingSet = function() return true end, function() end, function() return 1 end
    GetWeaponEnchantInfo = function() return false end
    C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    C_Minimap = { GetNumTrackingTypes = function() return 2 end, GetTrackingInfo = function(index)
        return ({ { name = "Find Herbs", texture = 1, active = false, type = "spell", spellID = 2383 },
            { name = "Find Minerals", texture = 2, active = false, type = "spell", spellID = 2580 } })[index]
    end }
    C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end }
    C_UnitAuras = { GetAuraDataByIndex = function() return nil end, GetUnitAuraBySpellID = function() return nil end }
    C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. id, iconID = 1 } end }
    C_SpellBook = { IsSpellKnown = function(id) return id == 465 or id == 465 end }
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
    local registrations = {}
    for line in io.lines(tocName) do
        local entry = line:gsub("\r", ""):gsub("\\", "/")
        if entry:match("%.xml$") then
            wow.LoadHammerCore(entry:match("^(.*)/[^/]+$"), "Buffsmith", ns)
            local UI = ns.HammerCore.UI
            local register = UI.RegisterRow
            UI.RegisterRow = function(parent, row, label)
                local resolved = type(label) == "function" and label() or label
                local owner = parent.hcHeaderOwner or parent
                local previous = owner.hcRows and owner.hcRows[resolved]
                assert(not previous or previous == row, "duplicate setting: " .. tostring(resolved))
                registrations[#registrations + 1] = { owner = owner, row = row, label = resolved }
                return register(parent, row, label)
            end
        elseif entry:match("%.lua$") then
            assert(loadfile(entry))("Buffsmith", ns)
        end
    end
    local events = _G.BuffsmithEventFrame
    events.scripts.OnEvent(events, "ADDON_LOADED", "Buffsmith")
    events.scripts.OnEvent(events, "PLAYER_LOGIN")
    return ns, registrations
end

local checked = 0
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local saved = { iconSize = 56, thanksMessage = "Cheers {player}", thanksDelay = 4,
        categories = { food = false }, reminderPercent = { food = 23, item = { [9001] = 31 } },
        preferred = { food = 9001 }, excludedConsumables = { [9002] = true },
        palettePoint = { "TOPLEFT", "CENTER", 20, -40 }, visibilityVersion = 2, paletteAnchorVersion = 1 }
    local ns, registrations = loadAddon(toc, saved)
    local HC, settings = ns.HammerCore, ns.HammerCore.Settings
    local owned = true
    ns.Inventory.OwnedChoices = function(_, key)
        if key ~= "food" or not owned then return {} end
        return { { name = "Test Food", itemID = 9001, kind = "item", category = "food", icon = 1 } }
    end
    settings:Show("Appearance")
    for name, err in pairs(settings.errors) do error(name .. ": " .. err) end
    equal(ns.db.iconSize, 56, "saved icon size")
    equal(ns.db.thanksMessage, "Cheers {player}", "saved message")
    equal(ns.db.reminderPercent.item[9001], 31, "saved item threshold")
    equal(ns.db.categories.food, false, "saved category toggle")
    local bodies = {}
    for name, page in pairs(settings.pages) do
        for tab, body in pairs(page.bodies or {}) do bodies[body] = { page = name, tab = tab } end
    end
    local count = #registrations
    for index = 1, count do
        local item = registrations[index]
        local location = assert(bodies[item.owner], "registration outside body: " .. item.label)
        -- Restores for no-longer-ignored entries are deliberately absent.
        local searchable = false
        for _, result in ipairs(settings:Search(item.label, 10000)) do
            if result.page == location.page and result.tab == location.tab and result.label == item.label then
                searchable = true
                assert(settings:Focus(result.page, result.label, result.tab), "cannot focus " .. item.label)
            end
        end
        assert(searchable, "missing search: " .. location.page .. "/" .. item.label)
        checked = checked + 1
    end
    local function body(page, tab) return settings.pages[page].bodies[tab or page] end
    local function clickReset(page, label, tab)
        settings:Show(page, tab)
        local row = assert(body(page, tab).hcRows[label], label)
        wow.Click(row)
        assert(HC.Dialog:IsShown(), label .. " asks for confirmation")
        equal(HC.Dialog.current.title, label, "confirmation names its reset")
        wow.Click(HC.Dialog.frame.accept)
    end
    ns.Set("showTooltip", false)
    settings:Show("Tooltips")
    equal(settings:Focus("Tooltips", "Show item effects"), body("Tooltips").hcRows["Show bar tooltips"], "hidden tooltip child focuses master")
    equal(settings:Focus("Thank You", "Message"), body("Thank You").hcRows["Thank players for buffs"], "disabled thanks focuses master")
    ns.Thanks:SetEnabled(true)
    ns.db.thanksChannel = "EMOTE"
    settings:Show("Thank You")
    equal(settings:Focus("Thank You", "Message"), body("Thank You").hcRows["Send thanks as"], "wrong channel focuses selector")
    ns.db.thanksChannel = "WHISPER"
    settings:Show("Thank You")
    local preview = body("Thank You").content.thanksPreview
    local lastPrint = wow.LastPrint()
    local message = body("Thank You").hcRows.Message
    local editor
    for _, frame in ipairs(wow.frames) do
        if frame.kind == "EditBox" and frame:GetParent() == message then editor = frame end
    end
    assert(editor, "message editor exists")
    editor:SetText("Thanks {player} for {buff}!")
    editor.scripts.OnEnterPressed(editor)
    equal(preview:GetText(), "Sample: Thanks a friendly mage for Power Word: Fortitude!", "inline sample updates after editing")
    equal(wow.LastPrint(), lastPrint, "preview posts nothing to chat")
    settings:Show("Buffs", "Reminders")
    equal(body("Buffs", "Reminders").content.reminderHeading:GetText(),
        "Remind when this much time is left", "buff duration column is labelled")
    local candidates, excluded = ns.KnownSelfBuffCandidates, ns.IsBuffExcluded
    local temporary = { spellID = 7777, castID = 7777, name = "A timed buff", duration = 3600 }
    ns.KnownSelfBuffCandidates = function() return { temporary } end
    local disabled = false
    ns.IsBuffExcluded = function() return disabled end
    settings:Show("Buffs", "Reminders")
    equal(body("Buffs", "Reminders").content.reminderHeading:IsShown(), true, "heading shows with an enabled timed slider")
    disabled = true
    settings:Show("Buffs", "Reminders")
    equal(body("Buffs", "Reminders").content.reminderHeading:IsShown(), false, "heading hides when timed sliders are disabled")
    temporary.permanent = true; disabled = false
    settings:Show("Buffs", "Reminders")
    equal(body("Buffs", "Reminders").content.reminderHeading:IsShown(), false, "permanent effects need no duration heading")
    ns.KnownSelfBuffCandidates = function() return {} end
    settings:Show("Buffs", "Reminders")
    equal(body("Buffs", "Reminders").content.reminderHeading:IsShown(), false, "empty buff list needs no duration heading")
    ns.KnownSelfBuffCandidates, ns.IsBuffExcluded = candidates, excluded
    settings:Show("Buffs", "Reminders")

    settings:Show("Consumables")
    equal(body("Consumables").content.reminderHeading:GetText(),
        "Remind when this much time is left", "consumable duration column is labelled")
    local categories = ns.db.categories
    ns.db.categories = {}
    settings:Show("Consumables")
    equal(body("Consumables").content.reminderHeading:IsShown(), false, "all-off categories hide the duration heading")
    ns.db.categories = { food = true }
    owned = false
    settings:Show("Consumables")
    equal(body("Consumables").content.reminderHeading:IsShown(), true, "enabled category still has a slider without owned items")
    ns.db.categories, owned = categories, true
    settings:Show("Consumables")

    equal(settings:Focus("Consumables", "Test Food"), body("Consumables").hcRows.Food, "disabled category focuses category")
    equal(settings:Focus("Consumables", "Test Food reminder threshold"), body("Consumables").hcRows.Food, "nested disabled item threshold focuses category")
    ns.db.categories.food = true
    settings:Show("Consumables")
    equal(settings:Focus("Consumables", "Test Food"), body("Consumables").hcRows["Test Food"], "enabled category reveals item")
    settings:Show("Appearance")
    owned = false
    local events = _G.BuffsmithEventFrame
    events.scripts.OnEvent(events, "BAG_UPDATE_DELAYED")
    equal(#settings:Search("Test Food", 1000), 0, "removed bag item disappears while another page is open")
    owned = true
    events.scripts.OnEvent(events, "BAG_UPDATE_DELAYED")
    equal(#settings:Search("Test Food", 1000), 2, "new bag item is searchable without opening Consumables")
    settings:Hide()
    owned = false
    events.scripts.OnEvent(events, "BAG_UPDATE_DELAYED")
    settings:Show("Appearance")
    equal(#settings:Search("Test Food", 1000), 0, "reopening settings refreshes hidden dynamic pages")
    owned = true
    ns.db.excludedBuffs[465], ns.db.excludedBuffs[2383] = true, true
    ns.db.reminderPercent.buffBySpell[465] = 29
    ns.db.trackingChoice = 2383
    clickReset("Buffs", "Reset reminders", "Reminders")
    equal(ns.db.excludedBuffs[465], nil, "reminder reset clears buff exclusion")
    equal(ns.db.excludedBuffs[2383], true, "reminder reset preserves tracking exclusion")
    equal(ns.db.reminderPercent.buffBySpell[465], nil, "reminder reset clears buff threshold")
    equal(ns.db.reminderPercent.food, 23, "reminder reset preserves food threshold")
    clickReset("Buffs", "Reset tracking", "Tracking")
    equal(ns.db.trackingChoice, nil, "tracking reset clears choice")
    equal(ns.db.excludedBuffs[2383], nil, "tracking reset clears tracking exclusion")
    ns.db.showTargetBuffs = false
    clickReset("Buffs", "Reset targets", "Targets")
    equal(ns.db.showTargetBuffs, true, "target reset")
    equal(ns.db.iconSize, 56, "target reset preserves appearance")
    clickReset("Consumables", "Reset consumable reminders")
    equal(ns.db.reminderPercent.food, 10, "category threshold reset")
    equal(ns.db.reminderPercent.item[9001], nil, "item threshold reset")
    equal(ns.db.excludedConsumables[9002], true, "consumable reset preserves ignored items")
    equal(ns.db.preferred.food, 9001, "consumable reset preserves preferred item")
    clickReset("Appearance", "Reset appearance")
    equal(ns.db.iconSize, 40, "appearance reset")
    equal(ns.db.palettePoint[3], 20, "appearance reset preserves position")
    equal(ns.db.thanksDelay, 4, "appearance reset preserves thanks")
    clickReset("Tooltips", "Reset tooltips")
    equal(ns.db.showTooltip, true, "tooltip reset")
    clickReset("Thank You", "Reset thank you")
    equal(ns.db.thanksEnabled, false, "thanks reset disables feature")
    equal(ns.db.thanksMessage, ns.defaults.thanksMessage, "thanks reset restores message")
    -- Every dynamic restore action is indexed, including after list reordering.
    local ignored = { { kind = "spell", id = 1126, name = "Test Mark", icon = 1 },
        { kind = "item", id = 9002, name = "Test Scroll", icon = 1 } }
    ns.Actions.IgnoredEntries = function() return ignored end
    settings:Show("Ignored")
    assert(settings:Focus("Ignored", "Restore Test Mark (spell 1126)"))
    ignored = { ignored[2] }
    settings:Show("Ignored")
    equal(#settings:Search("Restore Test Mark", 1000), 0, "restored entry leaves search")
    assert(settings:Focus("Ignored", "Restore Test Scroll (item 9002)"))
    HC.State().minimap = false
    HC.State().settingsSearch = false
    ns.db.ignoreBuffsInRestedAreas = true
    ns.db.legacyVisibility = { solo = true }
    local refresh, legacyAtRefresh = ns.RefreshAll, "not refreshed"
    ns.RefreshAll = function()
        legacyAtRefresh = ns.db.legacyVisibility
        refresh()
    end
    clickReset("Visibility", "Reset bar visibility")
    ns.RefreshAll = refresh
    equal(legacyAtRefresh, nil, "legacy visibility is cleared before applying the reset")
    equal(ns.db.ignoreBuffsInRestedAreas, false, "bar visibility reset")
    equal(HC.State().minimap, false, "visibility reset preserves shared minimap setting")
    equal(HC.State().settingsSearch, false, "visibility reset preserves settings search")
end
io.write("settings search: " .. checked .. " registrations checked on both clients; compatibility and scoped resets passed\n")

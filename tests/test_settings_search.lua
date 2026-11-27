package.path = "./tests/hammercore/?.lua;" .. package.path
local wow = require("wow")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

-- Client APIs Buffsmith uses beyond the HammerCore harness, as plain stubs.
local function installClient(class, learned)
    RegisterStateDriver, UnregisterStateDriver = function() end, function() end
    RegisterAttributeDriver = function() end
    SecureHandlerWrapScript = function() end
    GetSpecialization = function() return 1 end
    UnitClass = function() return class or "Paladin", class or "PALADIN" end
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
    C_SpellBook = { IsSpellKnown = function(id) return learned and learned[id] == true or not learned and id == 465 end }
    Enum = { SpellBookSpellBank = { Player = 0 } }
    C_ChatInfo = {}
    EmoteList, TextEmoteSpeechList = {}, {}
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    NUM_BAG_SLOTS = 4
end

-- Load Buffsmith exactly as a TOC lists it.
local function loadAddon(tocName, saved, class, learned)
    wow.Install({ Buffsmith = { Version = "0.1.4-dev1", ["X-Buffsmith-Target"] = tocName:find("Camelot") and "Camelot" or nil } })
    installClient(class, learned)
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
    ns.Set("showTooltip", true)
    settings:Show("Tooltips")
    local tooltipRows = body("Tooltips").hcRows
    local barTips, itemEffects = tooltipRows["Show bar tooltips"], tooltipRows["Show item effects"]
    equal(itemEffects:GetParent(), barTips:GetParent(), "tooltip switches share their row section")
    equal(itemEffects.points[1][3], barTips.points[1][3], "tooltip switches align vertically")
    assert(itemEffects.points[1][2] > barTips.points[1][2], "item effects occupies the right column")
    ns.Set("showTooltip", false)
    equal(settings:Focus("Thank You", "Message"), body("Thank You").hcRows["Thank players for buffs"], "disabled thanks focuses master")
    ns.Thanks:SetEnabled(true)
    ns.db.thanksChannel = "EMOTE"
    settings:Show("Thank You")
    equal(settings:Focus("Thank You", "Message"), body("Thank You").hcRows["Send thanks as"], "wrong channel focuses selector")
    local emote = body("Thank You").hcRows.Emote
    local unknown = body("Thank You").hcRows["Emote when caster is unknown"]
    equal(emote:GetParent().hcColumns, 2, "emote controls use two columns")
    if ns.TARGET == "Camelot" then
        equal(unknown:GetParent(), emote:GetParent(), "emote controls share their row section")
        equal(unknown.points[1][3], emote.points[1][3], "emote controls align vertically")
        assert(unknown.points[1][2] > emote.points[1][2], "unknown-caster switch occupies the right column")
    else
        equal(unknown, nil, "unsupported unknown-caster switch stays absent on Retail")
    end
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
        "Remind below", "buff duration column is labelled")
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
        "Remind below", "consumable duration column is labelled")
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
    local clickOnly = assert(settings:Focus("Consumables", "Click only: Food"))
    local rows = body("Consumables").hcRows
    local food, threshold, timing = rows.Food, rows["Food reminder threshold"], rows["Food: When to show"]
    equal(clickOnly:GetParent(), food, "click-only switch is part of the category row")
    local _, _, _, clickX, clickY = clickOnly:GetPoint()
    local _, thresholdX = threshold:GetPoint()
    local _, _, _, timingInset = timing:GetPoint()
    equal(clickY, 0, "click-only switch is vertically centered on the category row")
    assert(thresholdX + threshold:GetWidth() + 32 < clickX - clickOnly:GetWidth() / 2,
        "there is room for the threshold value before the click-only switch")
    assert(clickX + clickOnly:GetWidth() / 2 < food:GetWidth() + timingInset - timing:GetWidth(),
        "the click-only switch fits before the timing selector")
    local content = body("Consumables").content
    local reminderHeading = content.reminderHeading
    local _, headingX, headingY = reminderHeading:GetPoint()
    local _, rowX, rowY = food:GetPoint()
    equal(headingX, rowX + thresholdX, "threshold heading aligns to the real window width")
    equal(headingY - rowY, 20, "headings sit directly above the first category row")
    local clickHeading, timingHeading
    for _, region in ipairs(wow.regions) do
        if region:GetParent() == content then
            if region:GetText() == "Click only" then clickHeading = region end
            if region:GetText() == "When to show" then timingHeading = region end
        end
    end
    local _, anchor, _, headingOffset = assert(clickHeading):GetPoint()
    equal(anchor, reminderHeading, "click-only header uses the shared heading anchor")
    equal(headingX + headingOffset + clickHeading:GetWidth() / 2, rowX + clickX, "click-only heading is centered over its switch")
    local _, timingAnchor, _, timingOffset = assert(timingHeading):GetPoint()
    equal(timingAnchor, reminderHeading, "timing header uses the shared heading anchor")
    equal(headingX + timingOffset, rowX + food:GetWidth() + timingInset - timing:GetWidth(), "timing heading aligns above the selector")
    local headingHint
    for _, frame in ipairs(wow.frames) do
        if frame.points[1] and frame.points[1][2] == clickHeading and frame.hcHintTitle == "Click only" then
            headingHint = frame
            break
        end
    end
    local tooltipLine, addLine = nil, GameTooltip.AddLine
    GameTooltip.AddLine = function(_, line) tooltipLine = line end
    for _, control in ipairs({ assert(headingHint, "click-only heading has a hover target"), clickOnly }) do
        tooltipLine = nil
        control.scripts.OnEnter(control)
        assert(tooltipLine and tooltipLine:find("Next buff key skips this category", 1, true), "hover explains the keybind effect")
    end
    GameTooltip.AddLine = addLine
    local originalChoices = ns.Inventory.Choices
    function ns.Inventory:Choices(category)
        if category == "food" then return self:OwnedChoices(category) end
        if category == "flask" then
            return { { name = "Test Flask", itemID = 9003, kind = "item", category = "flask", icon = 1 } }
        end
        return {}
    end
    local function inKeyRotation(itemID)
        local key = ns.Readiness:Key({ kind = "item", itemID = itemID })
        for _, candidate in ipairs(ns.Bindings.order or {}) do
            if candidate == key then return true end
        end
        return false
    end
    ns.RefreshAll()
    equal(inKeyRotation(9001), true, "existing saves include food in the key rotation")
    wow.Click(clickOnly)
    equal(ns.db.categories.food, true, "click-only toggle leaves the category enabled")
    equal(inKeyRotation(9001), false, "click-only food is removed from the key rotation immediately")
    equal(inKeyRotation(9003), true, "the flask remains in the key rotation")
    local clickableFood = false
    for _, button in pairs(ns.Palette.buttons) do
        if button:IsShown() and button:GetAttribute("type1") == "item" and button:GetAttribute("item1") == "item:9001" then
            clickableFood = true
        end
    end
    equal(clickableFood, true, "click-only food still has a visible, armed bar icon")
    wow.Click(clickOnly)
    equal(inKeyRotation(9001), true, "turning off click only puts food back in the key rotation")
    wow.Click(clickOnly)
    ns.Inventory.Choices = originalChoices
    settings:Show("Appearance")
    owned = false
    local events = _G.BuffsmithEventFrame
    events.scripts.OnEvent(events, "BAG_UPDATE_DELAYED")
    equal(#settings:Search("Test Food", 1000), 0, "removed bag item disappears while another page is open")
    owned = true
    events.scripts.OnEvent(events, "BAG_UPDATE_DELAYED")
    equal(#settings:Search("Test Food", 1000), 8, "item, threshold and six display-rule controls are searchable without opening Consumables")
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
    clickReset("Buffs", "Reset character tracking", "Tracking")
    equal(ns.db.trackingChoice, 2383, "character tracking reset preserves legacy account choice")
    equal(ns.db.excludedBuffs[2383], true, "character tracking reset preserves legacy account exclusion")
    ns.db.showTargetBuffs = false
    clickReset("Buffs", "Reset targets", "Targets")
    equal(ns.db.showTargetBuffs, true, "target reset")
    equal(ns.db.iconSize, 56, "target reset preserves appearance")
    clickReset("Consumables", "Reset this page")
    equal(ns.db.clickOnlyCategories.food, nil, "consumable reset restores food to the key rotation")
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
-- Learned blessing controls, collapsed search, reordering and Fury.
do
    local ns = loadAddon("Buffsmith_Camelot.toc", {})
    local known = { [19740] = true }
    local names = { [19740] = "Blessing of Might", [19742] = "Blessing of Wisdom", [20217] = "Blessing of Kings", [25780] = "Righteous Fury" }
    C_SpellBook.IsSpellKnown = function(id) return known[id] == true end
    C_Spell.GetSpellInfo = function(id) return { name = names[id] or ("Spell " .. id), iconID = id } end
    ns.ResetSpellbook()
    local settings = ns.HammerCore.Settings
    assert(settings:Show("Buffs", "Paladin Blessings"))
    for name, err in pairs(settings.errors) do error(name .. ": " .. err) end
    assert(settings:Focus("Buffs", "My blessing Might priority", "Paladin Blessings"))
    equal(#settings:Search("Mage Wisdom priority", 1000), 0, "unlearned Wisdom absent")
    known[19742], known[20217], known[25780] = true, true, true
    ns.ResetSpellbook()
    settings:Show("Buffs", "Paladin Blessings")
    assert(settings:Focus("Buffs", "Mage Wisdom priority", "Paladin Blessings"), "collapsed Mage order searchable")
    assert(settings:Focus("Buffs", "Remind me to maintain Righteous Fury", "Paladin Blessings"))
    equal(#settings:Search("Warrior Wisdom priority", 1000), 0, "warrior Wisdom absent")
    local body = settings.pages.Buffs.bodies["Paladin Blessings"]
    local mage = body.hcRows["Mage Wisdom priority"]
    mage.down.scripts.OnClick(mage.down)
    equal(ns.Blessings:Order("MAGE", ns.Blessings:Known())[1], 20217, "down button reorders")
    known[19742] = nil
    ns.ResetSpellbook()
    settings:Show("Buffs", "Paladin Blessings")
    equal(#settings:Search("Mage Wisdom priority", 1000), 0, "lost spell leaves search")
    ns.db.blessings.automatic = false
    settings:Show("Buffs", "Paladin Blessings")
    assert(settings:Focus("Buffs", "Blessing to offer", "Paladin Blessings"))
    for name, err in pairs(settings.errors) do error(name .. ": " .. err) end
end
-- Class-only controls use the actual TOC load path on both clients.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    for _, class in ipairs({ "DRUID", "ROGUE", "SHAMAN" }) do
        local learned = { [1126] = true, [467] = true, [324] = true, [52127] = true }
        local ns = loadAddon(toc, {}, class, learned)
        local settings = ns.HammerCore.Settings
        local forever = toc:find("Camelot") ~= nil
        equal(ns.db.displayRules.categories.food, "INSTANCES", "fresh TOC load uses recommended defaults")
        local tab = ({ DRUID = "Druid Buffs", ROGUE = "Poisons", SHAMAN = "Shields" })[class]
        settings:Show("Buffs", forever and tab or "Reminders")
        for name, err in pairs(settings.errors) do error(class .. " " .. name .. ": " .. err) end
        if forever then
            local label = ({ DRUID = "Thorns: Party recipients", ROGUE = "Main-hand poison", SHAMAN = "Preferred shield" })[class]
            assert(settings:Focus("Buffs", label, tab), class .. " control searchable")
            if class == "DRUID" then
                learned[467] = nil
                ns.ResetSpellbook()
                settings:Show("Buffs", tab)
                equal(#settings:Search("Thorns: Party recipients", 1000), 0, "unlearned druid section leaves search")
                learned[467] = true
                ns.ResetSpellbook()
                settings:Show("Buffs", tab)
                assert(settings:Focus("Buffs", "Thorns: Party recipients", tab), "relearned section searchable")
                ns.db.excludedBuffs[467] = true
                ns.db.reminderPercent.buffBySpell[467] = 37
                ns.db.showPartyBuffs = false
            elseif class == "ROGUE" then
                ns.db.preferred["1"] = { ["poison:16"] = 9001, ["poison:17"] = 9002, weapon = 9003 }
                ns.db.excludedConsumables[9001] = true
                ns.ClassBuffs:Config().poisons = false
            else
                ns.db.preferred["1"] = { ["shaman-shield"] = 52127, food = 9001 }
                ns.ClassBuffs:Config().keepShield = false
            end
            local reset = ({ DRUID = "Reset druid recipients", ROGUE = "Reset poison choices", SHAMAN = "Reset shield choices" })[class]
            local body = settings.pages.Buffs.bodies[tab]
            wow.Click(assert(body.hcRows[reset]))
            assert(ns.HammerCore.Dialog:IsShown())
            wow.Click(ns.HammerCore.Dialog.frame.accept)
            if class == "DRUID" then
                equal(ns.ClassBuffs:Druid({ spellID = 467 }).party, "NONE", "druid reset inherits global party ceiling")
                equal(ns.db.excludedBuffs[467], true, "druid reset preserves ignored Thorns")
                equal(ns.db.reminderPercent.buffBySpell[467], 37, "druid reset preserves renewal threshold")
            elseif class == "ROGUE" then
                equal(ns.db.preferred["1"]["poison:16"], nil, "poison reset clears main hand")
                equal(ns.db.preferred["1"].weapon, 9003, "poison reset preserves other weapon preference")
                equal(ns.db.excludedConsumables[9001], true, "poison reset preserves ignored items")
                equal(ns.ClassBuffs:Config().poisons, false, "poison reset preserves reminder switch")
            else
                equal(ns.db.preferred["1"]["shaman-shield"], nil, "shield reset clears preference")
                equal(ns.db.preferred["1"].food, 9001, "shield reset preserves other preferences")
                equal(ns.ClassBuffs:Config().keepShield, nil, "shield reset restores keep default")
            end
        else
            equal(settings.pages.Buffs.bodies[tab], nil, "Forever-only class tab absent on Retail")
        end
    end
end
-- Display-rule controls preserve inheritance, expand Custom and reset only rules.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc, { iconSize = 44, reminderPercent = { food = 23 },
        categories = { food = true }, clickOnlyCategories = { food = true } })
    local settings, R = ns.HammerCore.Settings, ns.DisplayRules
    ns.Inventory.OwnedChoices = function(_, category)
        return category == "food" and { { kind = "item", itemID = 9001, name = "Test Food", category = "food", usable = true } } or {}
    end
    settings:Show("Consumables")
    local body = settings.pages.Consumables.bodies.Consumables
    equal(body.hcRows["Click only: Food"]:GetChecked(), true, "existing click-only settings render on the category row")
    local selector = assert(body.hcRows["Food: When to show"])
    local frame = selector:GetParent()
    local collapsed = frame:GetHeight()
    equal(collapsed, frame.hcParentRow:GetHeight(), "preset selector occupies the existing reminder row")
    equal(selector.Title:IsShown(), false, "inline selector hides the repeated buff label")
    equal(selector.points[1][2], frame.hcParentRow, "selector anchors beside its reminder")
    R:Set({kind='category',category='food'}, 'CUSTOM')
    settings:Show("Consumables")
    assert(frame:GetHeight() > collapsed, "custom controls expand the list")
    local world = assert(body.hcRows["Food: Open world"])
    wow.Click(world.hcCheckbox)
    equal(ns.db.displayRules.categories.food.world, false, "custom checkbox persists")
    assert(settings:Focus("Consumables", "Test Food (item 9001): When to show"))
    R:Set({kind='category',category='food'}, 'INSTANCES')
    settings:Show("Consumables")
    equal(frame:GetHeight(), collapsed, "preset collapses custom controls")
    R:Set({kind='category',category='food'}, 'CUSTOM')
    settings:Show("Consumables")
    local customHeight = frame:GetHeight()
    local stringHeight = frame.summary.GetStringHeight
    frame.summary.GetStringHeight = function() return 80 end
    settings:Show("Consumables")
    assert(frame:GetHeight() > customHeight, "wrapped custom summary expands its available height")
    frame.summary.GetStringHeight = stringHeight
    R:Set({kind='category',category='food'}, 'INSTANCES')
    settings:Show("Consumables")
    equal(settings:Focus("Consumables", "Food: Open world"), selector, "hidden custom setting focuses its selector")
    local item = {kind='item',itemID=9001,category='food'}
    equal(R:Describe(item), 'Using Food settings: Dungeons and raids', "item displays effective inherited category")
    R:Set(item, 'ALWAYS')
    R:Set({kind='spell',spellID=465}, 'READY')
    wow.Click(assert(body.hcRows["Apply recommended display rules"]))
    assert(ns.HammerCore.Dialog:IsShown())
    wow.Click(ns.HammerCore.Dialog.frame.accept)
    equal(R:Own(item), nil, "apply clears explicit item overrides")
    equal(R:Own({kind='spell',spellID=465}), nil, "apply clears buff overrides")
    equal(ns.db.iconSize, 44, "apply preserves layout")
    equal(ns.db.reminderPercent.food, 23, "apply preserves renewal threshold")
    equal(ns.db.categories.food, true, "apply preserves enabled categories")
    equal(ns.db.clickOnlyCategories.food, true, "apply preserves click-only choices")
    for name, err in pairs(settings.errors) do error(toc .. " " .. name .. ": " .. err) end
end
-- The actual READY_CHECK event and combat recovery refresh the next-buff key.
do
    local ns = loadAddon("Buffsmith_Camelot.toc", { iconSize = 40 })
    local now, combat, expire = 100, false, nil
    GetTime = function() return now end
    IsInGroup = function() return true end
    InCombatLockdown = function() return combat end
    C_Timer.After = function(delay, fn) if delay == 15 then expire = fn end end
    ns.DisplayRules:Set({kind='spell',spellID=465}, 'READY')
    local function offered()
        for _, entry in ipairs(ns.Actions:BindingEntries()) do if entry.spellID == 465 then return true end end
        return false
    end
    assert(not offered(), "before ready check the key cannot offer the buff")
    local frame = BuffsmithEventFrame
    frame.scripts.OnEvent(frame, "READY_CHECK")
    assert(offered() and expire, "actual ready-check event permits the key")
    equal(ns.Bindings.trigger:GetAttribute("spell1"), "Spell 465", "ready event prepares the actual secure key")
    combat, now = true, 115
    expire()
    equal(ns.DisplayRules.readyUntil, nil, "expiry clears even while combat prevents refresh")
    assert(not offered(), "combat still suppresses key actions")
    combat = false
    frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED")
    assert(not offered(), "combat recovery refreshes expired rules")
    equal(ns.Bindings.trigger:GetAttribute("type1"), nil, "combat recovery disarms the actual expired key")
end
io.write("settings search: " .. checked .. " registrations checked on both clients; compatibility and scoped resets passed\n")

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
    local ns = loadAddon(toc)
    local now, auras = 100, {}
    GetTime = function() return now end
    C_UnitAuras.GetAuraDataByIndex = function(_, index) return auras[index] end
    C_UnitAuras.GetUnitAuraBySpellID = function(_, id)
        for _, aura in ipairs(auras) do if aura.spellId == id then return aura end end
    end
    ns.db.ignoreBuffsInRestedAreas, ns.db.showPartyCoverage = false, false
    ns.db.excludedBuffs[465], ns.db.excludedBuffs[19740] = true, true
    local function render()
        ns.Palette:Refresh()
        local entries = {}
        for _, frame in pairs(ns.Palette.buttons) do
            if frame:IsShown() and frame.buffsmithEntry and frame.buffsmithEntry.displayOnly then
                entries[#entries + 1] = frame
            end
        end
        return entries
    end
    local function foodSlot()
        for _, frame in pairs(ns.Palette.buttons) do
            local entry = frame.buffsmithEntry
            if frame:IsShown() and not frame.buffsmithSmall and entry
                and (entry.category == "food" or entry.displayOnly) then return frame end
        end
        error("food slot missing")
    end
    local function aura(id, name, icon, duration, ends)
        return { spellId = id, auraInstanceID = id + 1000, name = name, icon = icon, duration = duration, expirationTime = ends }
    end
    auras = { aura(433, "Food", 133906, 30, 130), aura(430, "Drink", 132794, 20, 120) }
    local icons = render()
    equal(#icons, 1, toc .. ": simultaneous food/drink uses one slot")
    equal(icons[1].buffsmithEntry.icon, 133906, "native meal icon")
    equal(icons[1].cooldown:IsShown(), true, "readable meal duration has native sweep")
    equal(ns.Palette.frame:IsShown(), true, "last consumed item still has progress without bag items")
    equal(ns.Palette.statusText:IsShown(), false, "no eating/drinking text row")
    equal(ns.Actions.eatingPaused, true, "casts stay paused")
    equal(icons[1].buffsmithFlyout, nil, "progress has no alternatives")
    equal(icons[1].check, nil, "no success tick widget")
    for _, entry in ipairs(ns.Actions:BindingEntries()) do
        equal(entry.displayOnly, nil, "progress never enters next buff key")
    end
    icons[1].scripts.PreClick(icons[1], "LeftButton")
    icons[1].scripts.PostClick(icons[1], "LeftButton")
    icons[1].scripts.PostClick(icons[1], "RightButton")
    equal(icons[1]:GetAttribute("type1"), nil, "progress cannot cast or use")
    local anchor = { ns.Palette.frame:GetPoint() }
    auras[3] = aura(18125, "Well Fed", 136000, 900, 1000)
    equal(#render(), 0, "fresh Well Fed hides progress even before eating ends")
    equal(ns.Actions.eatingPaused, true, "food buff does not unpause casting during meal")
    auras = { auras[3] }
    equal(#render(), 0, "no Well Fed icon remains after standing")
    equal(ns.Actions.eatingPaused, false, "standing permits casts")
    auras[2] = aura(433, "Food", 133906, 30, 130)
    equal(#render(), 0, "existing Well Fed does not reveal a progress slot")
    for index,value in ipairs(anchor) do equal(({ns.Palette.frame:GetPoint()})[index], value, "handle stays fixed") end
    local food = { kind = "item", itemID = 9001, category = "food", name = "Steak", usable = true, icon = 133906 }
    local alternative = { kind = "item", itemID = 9002, category = "food", name = "Stew", usable = true, icon = 133906 }
    ns.Inventory.ownedItems = { food = { food, alternative } }
    ns.Inventory.items.food = { food, alternative }
    auras = {}
    render()
    equal(foodSlot().buffsmithEntry.kind, "item", "normal food reminder before meal")
    local beforeMains = #select(2, ns.Palette:Items())
    equal(foodSlot().buffsmithFlyout, "food", "normal food offers alternatives")
    auras = { aura(433, "Food", 133906, 30, 130) }
    icons = render()
    equal(#icons, 1, "meal replaces food rather than adding another slot")
    local _, entries, subs = ns.Palette:Items()
    equal(#entries, beforeMains, "progress replaces exactly one main food slot")
    equal(#subs, 0, "no alternative food icons while eating")
    ns.Readiness.lastEntry = food
    C_Item = C_Item or {}
    local originalCooldown = C_Item.GetItemCooldown
    C_Item.GetItemCooldown = function() return 100, 30, 1 end
    local _, coolingEntries = ns.Palette:Items()
    equal(#coolingEntries, beforeMains, "last-used food cooldown cannot add another icon")
    auras[2] = aura(18125, "Well Fed", 136000, 900, 1000)
    render()
    equal(ns.Palette:CooldownEntry(), nil, "food benefit hides food cooldown fallback while eating")
    auras = { auras[2] }
    render()
    equal(ns.Palette:CooldownEntry(), nil, "food benefit hides food cooldown fallback after standing")
    ns.Readiness.lastEntry = { kind = "item", itemID = 9999, category = "flask", name = "Flask" }
    assert(ns.Palette:CooldownEntry(), "other consumable cooldown displays are retained")
    ns.Readiness.lastEntry, C_Item.GetItemCooldown = nil, originalCooldown
    auras = { aura(433, "Food", 133906, 30, 130) }
    icons = render()
    equal(icons[1].buffsmithFlyout, nil, "existing food flyout is detached")
    auras = {}
    render()
    equal(foodSlot().buffsmithEntry.kind, "item", "interruption restores normal food reminder")
    equal(foodSlot().buffsmithFlyout, "food", "interruption restores alternatives")
    auras = { aura(430, "Drink", 132794) }
    icons = render()
    equal(#icons, 1, "plain drink has one progress indicator")
    equal(icons[1].cooldown:IsShown(), false, "unknown timer has no invented sweep")
    auras = { aura(433, "Food", 133906, 30, 130) }
    ns.db.categories.food = false
    equal(#render(), 0, "Food category toggle hides progress")
    ns.db.categories.food = true
    if ns.TARGET == "Camelot" then
        auras[2] = aura(1229741, "Camp Benefits", 136000, 3600, 3700)
        equal(#render(), 1, "Forever camp buff cannot satisfy food")
    end
    ns.db.consumableAuras[9001] = { spellID = 433, name = "Food", duration = 30 }
    auras = { aura(433, "Food", 133906, 30, 130) }
    equal(#render(), 1, "old eating-aura mapping cannot satisfy food")
    equal(ns.Inventory:LearnedAura(food), nil, "temporary meal mapping is ignored")
    ns.db.consumableAuras[9001] = nil
    local secret = {}
    local plain, isSecret = ns.Plain, ns.IsSecret
    ns.Plain = function(value) if value == secret then return nil end; return plain(value) end
    ns.IsSecret = function(value) return value == secret or isSecret(value) end
    auras = { aura(433, "Food", 133906, 30, 130), secret }
    equal(#render(), 1, "readable meal remains visible in partial snapshot")
    auras = { secret }
    equal(#render(), 0, "unreadable first aura invents no icon")
    auras = { aura(433, secret, secret, secret, secret) }
    icons = render()
    equal(icons[1].buffsmithEntry.name, "Food / Drink", "secret aura name has a readable fallback")
    icons[1].scripts.OnEnter(icons[1])
    equal(icons[1].cooldown:IsShown(), false, "secret timer invents no sweep")
    ns.Plain, ns.IsSecret = plain, isSecret
    auras = { aura(433, "Food", 133906, 30, 130), aura(467, "Thorns", 136100, 600, 700) }
    equal(#render(), 1, "unrelated class buff cannot satisfy food")
    auras = {}
    ns.Actions:MealStatus()
    ns.Palette:UpdateFeedback()
    for _, frame in pairs(ns.Palette.buttons) do
        if frame:IsShown() then equal(frame.buffsmithEntry.displayOnly, nil, "feedback removes interrupted meal progress") end
    end
    equal(ns.Palette.statusText:IsShown(), false, "text never flashes after meal")
end
io.write("Meal progress tests passed\n")

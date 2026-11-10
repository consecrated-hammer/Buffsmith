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
    local forever = toc:find("Camelot") ~= nil
    local buffID, buffName, rankID = forever and 467 or 1126, forever and "Thorns" or "Mark of the Wild", forever and 782 or 5232
    UnitClass = function() return "Druid", "DRUID" end
    IsInGroup = function() return true end
    C_SpellBook.IsSpellKnown = function(id) return id == buffID end
    C_Spell.GetSpellInfo = function(id) return { name = id == buffID and buffName or "Spell " .. id, iconID = 1 } end
    ns.ResetSpellbook()
    local clock = 100
    GetTime = function() return clock end
    local thorns = { name = buffName, spellId = buffID, duration = 600, expirationTime = 700, sourceUnit = "player" }
    C_UnitAuras.GetAuraDataByIndex = function(_, index) if index == 1 then return thorns end end
    C_UnitAuras.GetUnitAuraBySpellID = function(_, id) if id == buffID then return thorns end end
    local spell = { kind = "spell", spellID = buffID, castID = buffID, name = buffName, icon = 1 }
    ns.Readiness.lastEntry, ns.Readiness.lastEntryAt = spell, 100
    local cooldown = { startTime = 100, duration = 1.5, isEnabled = true }
    C_Spell.GetSpellCooldown = function() return cooldown end
    ns.Palette:Refresh()
    assert(ns.Palette:CooldownEntry(), "own initial cooldown remains visible")
    clock = 102; cooldown = { startTime = 0, duration = 0, isEnabled = true }
    ns.Palette:UpdateFeedback()
    equal(ns.Palette:CooldownEntry(), nil, "own cooldown ends normally")
    clock = 160; cooldown = { startTime = 160, duration = 1.5, isEnabled = true }
    BuffsmithEventFrame.scripts.OnEvent(BuffsmithEventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "form", 768)
    ns.Palette:UpdateFeedback()
    equal(ns.Readiness.lastEntryAt, 100, "form cast does not renew Thorns retention")
    BuffsmithEventFrame.scripts.OnEvent(BuffsmithEventFrame, "UNIT_SPELLCAST_SUCCEEDED", "party1", "other", buffID)
    equal(ns.Readiness.lastEntryAt, 100, "another player cannot renew retained cooldown timing")
    equal(ns.Palette:CooldownEntry(), nil, toc .. ": form GCD cannot revive already-applied Thorns")
    for _, button in pairs(ns.Palette.buttons) do
        if button:IsShown() and button.buffsmithEntry then
            equal(button.buffsmithEntry.name == buffName, false, "active Thorns has no visible reminder or retained icon")
        end
    end
    -- A missing buff still gets its normal icon and GCD sweep.
    thorns = nil
    ns.Palette:Refresh()
    local normal
    for _, button in pairs(ns.Palette.buttons) do
        if button:IsShown() and button.buffsmithEntry and button.buffsmithEntry.name == buffName then normal = button end
    end
    assert(normal, "genuinely missing Thorns still appears")
    equal(normal.buffsmithEntry.cooldownOnly, nil, "normal reminder remains actionable")
    equal(normal.cooldown:IsShown(), true, "normal reminder still shows current GCD")
    -- A blocked input cannot claim a different action's running GCD.
    local button = ns.Palette:Acquire(98, false)
    ns.Readiness:Press(button, spell)
    equal(ns.Readiness.lastEntryAt, 100, "blocked input cannot renew confirmed cast timing")
    equal(ns.Readiness:LastCooldown(), nil, "blocked input cannot adopt another form's GCD")
    GetCVar = function() return "400" end
    clock = 161.3
    ns.Readiness:Press(button, spell)
    equal(ns.Readiness.lastEntryAt, 100, "native queue deadline is not a successful-cast timestamp")
    equal(ns.Readiness:LastCooldown(), nil, "queued attempt alone cannot adopt an old GCD")
    -- A cast-time spell can begin its cooldown after the original input window.
    clock = 164
    cooldown = { startTime = 0, duration = 0, isEnabled = true }
    BuffsmithEventFrame.scripts.OnEvent(BuffsmithEventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "spell", buffID)
    equal(ns.Readiness.lastEntryAt, 164, "matching successful cast anchors delayed cooldown")
    equal(ns.Readiness:LastCooldown().remaining, 0, "cooldown metadata may lag successful cast")
    clock = 165
    cooldown = { startTime = 164, duration = 30, isEnabled = true }
    assert(ns.Readiness:LastCooldown(), "late API arrival preserves actual cooldown start")
    -- Real ability cooldowns survive unrelated casts while their original start is unchanged.
    clock = 180
    BuffsmithEventFrame.scripts.OnEvent(BuffsmithEventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "form", 783)
    assert(ns.Readiness:LastCooldown(), "unrelated form does not hide an ongoing real cooldown")
    cooldown.duration = 60
    assert(ns.Readiness:LastCooldown(), "duration updates on original cooldown remain visible")
    -- Skipping every observation of the original cooldown cannot create a later fake one.
    ns.Readiness.lastEntryAt = 100
    cooldown = { startTime = 180, duration = 1.5, isEnabled = true }
    equal(ns.Readiness:LastCooldown(), nil, "unobserved old cooldown cannot restart from later GCD")
    -- Matching rank, secret values and combat use never redirect secure actions.
    ns.Readiness.lastEntry = { kind = "spell", spellID = buffID, castID = rankID, name = buffName }
    ns.Readiness:NoteSpellCast(rankID)
    equal(ns.Readiness.lastEntryAt, 180, "resolved cast rank updates timing")
    local originalCombat = InCombatLockdown
    InCombatLockdown = function() return true end
    clock = 181; ns.Readiness:NoteSpellCast(rankID)
    equal(ns.Readiness.lastEntryAt, 181, "matching combat completion records only timing")
    InCombatLockdown = originalCombat
    ns.Readiness:NoteSpellCast(nil)
    equal(ns.Readiness.lastEntryAt, 181, "missing cast identity cannot renew retention")
    -- A readable same-name higher rank is accepted; unrelated metadata is not.
    clock = 182
    C_Spell.GetSpellInfo = function(id) return { name = id == rankID + 1 and buffName or "Unrelated", iconID = 1 } end
    ns.Readiness:NoteSpellCast(rankID + 1)
    equal(ns.Readiness.lastEntryAt, 182, "readable same-name rank anchors actual completion")
    clock = 183; ns.Readiness:NoteSpellCast(rankID + 2)
    equal(ns.Readiness.lastEntryAt, 182, "unrelated spell metadata cannot renew retention")
    -- A genuinely new, failed attempt never gets a confirmed timestamp.
    local newSpell = { kind = "spell", spellID = 999, name = "Other buff" }
    cooldown = { startTime = 182, duration = 30, isEnabled = true }
    ns.Readiness:Press(button, newSpell)
    equal(ns.Readiness.lastEntry.spellID, buffID, "blocked different spell preserves previous confirmed cooldown")
    equal(ns.Readiness.lastEntryAt, 182, "blocked different spell cannot erase confirmed timing")
    cooldown = { startTime = 0, duration = 0, isEnabled = true }
    ns.Readiness:Press(button, newSpell)
    equal(ns.Readiness.lastEntryAt, nil, "new attempt waits for actual cast success")
    cooldown = { startTime = 183, duration = 1.5, isEnabled = true }
    equal(ns.Readiness:LastCooldown(), nil, "failed attempt cannot retain unrelated GCD")
end
-- Items: a later GCD (cat form) can't bring back a used scroll, and an item
-- that's left the bags never shows. Its own GCD and real cooldowns still do.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    local clock = 200
    GetTime = function() return clock end
    local itemCD, count = { 0, 0, 1 }, 1
    C_Item = { GetItemCooldown = function() return itemCD[1], itemCD[2], itemCD[3] end,
        GetItemCount = function() return count end }
    local scroll = { kind = "item", itemID = 1180, name = "Scroll of Stamina", icon = 1 }
    local button = ns.Palette:Acquire(97, false)
    ns.Readiness.Check = function() return { allow = true } end
    ns.Readiness:Press(button, scroll)
    equal(ns.Readiness.lastEntry.itemID, 1180, toc .. ": the scroll is remembered")
    clock = 200.2; itemCD = { 200.1, 1.5, 1 }
    assert(ns.Readiness:LastCooldown(), toc .. ": the scroll's own GCD sweep shows")
    clock = 230; itemCD = { 229.9, 1.5, 1 }
    equal(ns.Readiness:LastCooldown(), nil, toc .. ": a later cat-form GCD doesn't bring the scroll back")
    count = 0; itemCD = { 200.1, 120, 1 }
    equal(ns.Readiness:LastCooldown(), nil, toc .. ": an item that's left the bags never shows")
    count = 2
    assert(ns.Readiness:LastCooldown(), toc .. ": a real item cooldown still shows")
end

io.write("Retained spell cooldown regression tests passed\n")

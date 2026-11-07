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
        "Visibility,Appearance,Tooltips,Buffs,Consumables,Ignored,Key Bindings,Thank You,Commands,Troubleshooting,About",
        toc .. ": rail order")
    local failures = {}
    for name, err in pairs(HC.Settings.errors) do failures[#failures + 1] = name .. ": " .. err end
    equal(table.concat(failures, "; "), "", toc .. ": every settings page builds")
    for _, spec in ipairs(HC.Settings.order) do
        HC.Settings:Show(spec.name)
        equal(HC.Settings.selected, spec.name, toc .. ": " .. spec.name .. " opens")
    end

    HC.Settings:Show("Buffs")
    equal(wow.FindText("Find Minerals") ~= nil, true, toc .. ": the Buffs page lists tracking")
    HC.Settings:Show("Thank You")
    equal(wow.FindText("WoW Forever may report a new buff without telling addons who cast it. Whispers still need a known caster.") ~= nil,
        true, toc .. ": Thank You explains unknown casters")
    local skipGroup = wow.FindText("Skip party and raid members").parent
    wow.Click(skipGroup)
    equal(ns.db.thanksSkipGroupMembers, true, toc .. ": Thank You group skip checkbox enables")
    wow.Click(skipGroup)
    equal(ns.db.thanksSkipGroupMembers, false, toc .. ": Thank You group skip checkbox disables")

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
    equal(wow.LastPrint(), "Buffsmith: bags scanned: food 0, scroll 0, flask 0, other 0, weapon 0", toc .. ": scan reports")

    -- A consumable on cooldown is still in the bag inventory, but must never
    -- occupy the bar or block a ready alternative in its category.
    ns.Inventory.items.food = {
        { kind = "item", itemID = 111, name = "Fish Liver Oil", category = "food" },
        { kind = "item", itemID = 222, name = "Redridge Goulash", category = "food" },
    }
    GetItemCooldown = function(itemID)
        if itemID == 111 then return 100, 120, 1 end
        return 0, 0, 1
    end
    local foodChoices = ns.Actions:VisibleChoices("food")
    equal(#foodChoices, 1, toc .. ": a cooling bag item is hidden")
    equal(foodChoices[1].itemID, 222, toc .. ": a ready alternative remains usable")
    equal(ns.Inventory.items.food[1].state, "cooldown", toc .. ": cooldown state is recorded")

    -- Class-restricted bag items must not be offered merely because their
    -- subtype is Scroll.  A temporary no-mana result remains usable.
    C_Item = C_Item or {}
    C_Item.IsUsableItem = function(itemID)
        if itemID == 333 then return false, false end
        if itemID == 444 then return false, true end
        return true, false
    end
    equal(ns.Inventory:IsUsableItem(333), false, toc .. ": a mage-only scroll is rejected for this character")
    equal(ns.Inventory:IsUsableItem(444), true, toc .. ": a temporary no-mana result is not treated as a restriction")
    C_Item.GetItemCooldown = function() return { startTime = 100, duration = 120, isEnabled = false } end
    equal(ns.Inventory:CooldownRemaining({ itemID = 555 }), nil,
        toc .. ": a disabled table cooldown does not hide an item")
    C_Item.GetItemCooldown = nil

    -- The generic icon is not reliable on every client.  A named Well Fed
    -- aura still suppresses all food choices while its 15-minute effect lasts.
    GetItemCooldown = nil
    C_UnitAuras.GetAuraDataByIndex = function(_, index)
        if index == 1 then return { spellId = 333, name = "Well Fed", duration = 900,
            expirationTime = 1000, icon = 1 } end
        return nil
    end
    equal(#ns.Actions:VisibleChoices("food"), 0, toc .. ": an active Well Fed aura suppresses food")
    C_UnitAuras.GetAuraDataByIndex = function() return nil end
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

-- Tooltip content follows the configured recipient and actual offered rank.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    ns.HammerCore.Settings:Show("Tooltips")
    local check = wow.FindText("Show spell descriptions").parent
    wow.Click(check)
    equal(ns.db.tooltipSpellDescriptions, true, toc .. ": description checkbox enables option")
    wow.Click(check)
    equal(ns.db.tooltipSpellDescriptions, false, toc .. ": description checkbox disables option")
    local exists = { player = true, party1 = true, target = true, pet = true }
    local identities = { player = "self", party1 = "friend", target = "target", pet = "pet" }
    UnitExists = function(unit) return exists[unit] == true end
    UnitGUID = function(unit) return identities[unit] end
    UnitName = function(unit)
        if unit == "player" then return "Rowan" end
        if unit == "party1" then return "Mira", "OtherRealm" end
        if unit == "target" then return "Finch" end
        if unit == "pet" then return "Moss" end
    end
    local lines, descriptionID, calls = {}, nil, 0
    GameTooltip.SetOwner = function(self, owner) self.tooltipOwner = owner end
    GameTooltip.IsOwned = function(self, owner) return self.tooltipOwner == owner end
    GameTooltip.AddLine = function(_, text, _, _, _, wrap) lines[#lines + 1] = { text = text, wrap = wrap } end
    C_Spell.GetSpellDescription = function(id)
        descriptionID, calls = id, calls + 1
        return "A static explanation of the spell."
    end
    local frame = ns.Palette:Acquire(99, false)
    local function hover(entry)
        lines = {}
        GameTooltip:Hide()
        frame.buffsmithEntry = entry
        frame.scripts.OnEnter(frame)
    end
    local function has(text)
        for _, line in ipairs(lines) do if line.text == text then return true, line.wrap end end
        return false
    end
    local thorns = { kind = "spell", name = "Thorns", spellID = 467, castID = 782,
        unit = "party1", unitGUID = "friend", scope = "party" }
    hover(thorns)
    equal(has("Cast on: Mira-OtherRealm"), true, toc .. ": party tooltip names recipient and realm")
    equal(calls, 0, toc .. ": descriptions are not queried while off")
    ns.db.tooltipSpellDescriptions = true
    hover(thorns)
    equal(descriptionID, 782, toc .. ": description uses actual offered rank")
    local present, wrapped = has("A static explanation of the spell.")
    equal(present and wrapped, true, toc .. ": description is wrapped")
    hover({ kind = "spell", name = "Buff", spellID = 467 })
    equal(has("Cast on: Rowan"), true, toc .. ": self tooltip names player")
    hover({ kind = "spell", name = "Buff", spellID = 467, unit = "target", scope = "target" })
    equal(has("Cast on: Finch"), true, toc .. ": selected target is named")
    hover({ kind = "spell", name = "Buff", spellID = 467, unit = "pet", scope = "pet" })
    equal(has("Cast on: Moss"), true, toc .. ": pet is named")
    hover({ kind = "notice", name = "Arcane Intellect", spellID = 1459,
        providerText = "Mira", missingText = "Rowan, Finch" })
    equal(descriptionID, 1459, toc .. ": coverage can describe the catalogue spell")
    equal(has("Missing on: Rowan, Finch"), true, toc .. ": coverage retains missing recipients")
    local missingAt, descriptionAt
    for index, line in ipairs(lines) do
        if line.text == "Missing on: Rowan, Finch" then missingAt = index end
        if line.text == "A static explanation of the spell." then descriptionAt = index end
    end
    assert(missingAt < descriptionAt, toc .. ": recipients precede optional long description")
    local before = calls
    hover({ kind = "item", name = "Keg", itemID = 1262 })
    equal(calls, before, toc .. ": bag items do not query a spell description")
    identities.party1 = "replacement"
    hover(thorns)
    equal(has("Recipient unavailable."), true, toc .. ": reused party slot cannot name a different recipient")
    identities.party1, exists.party1 = "friend", false
    hover(thorns)
    equal(has("Recipient unavailable."), true, toc .. ": departed recipient handled safely")
    exists.party1 = true
    C_Spell.GetSpellDescription = function() error("unavailable") end
    hover(thorns)
    equal(has("Cast on: Mira-OtherRealm"), true, toc .. ": failed description keeps useful tooltip")
    local secret = {}
    issecretvalue = function(value) return value == secret end
    C_Spell.GetSpellDescription = function() return secret end
    hover(thorns)
    equal(has("Cast on: Mira-OtherRealm"), true, toc .. ": secret description is ignored")
    issecretvalue = nil
    C_Spell.GetSpellDescription = nil
    GetSpellDescription = function() return "Legacy static description." end
    hover(thorns)
    equal(has("Legacy static description."), true, toc .. ": legacy description API works")
    GetSpellDescription = nil
    hover(thorns)
    equal(has("Cast on: Mira-OtherRealm"), true, toc .. ": absent description API keeps tooltip")
    hover({ kind = "spell", name = "Find Herbs", spellID = 2383, tracking = true, scope = "pet" })
    equal(has("Left-click: cast on them."), false, toc .. ": tracking keeps its own action instruction")
    local hovered = false
    ns.Palette.HoverEnter = function() hovered = true end
    frame.buffsmithFlyout = "food"
    ns.db.showTooltip = false
    hover(thorns)
    equal(#lines, 0, toc .. ": master toggle suppresses tooltip content")
    equal(GameTooltip:IsShown(), false, toc .. ": master toggle suppresses tooltip display")
    equal(hovered, true, toc .. ": hiding tooltips does not disable flyouts")
    GameTooltip:SetOwner({})
    GameTooltip:Show()
    frame.scripts.OnLeave(frame)
    equal(GameTooltip:IsShown(), true, toc .. ": leaving an icon does not hide another frame's tooltip")
    GameTooltip:SetOwner(frame)
    frame.scripts.OnLeave(frame)
    equal(GameTooltip:IsShown(), false, toc .. ": leaving closes its own tooltip")
end

-- Death and ghost state suppress the whole live reminder surface, including
-- consumable flyouts and the buff trigger, then resurrection restores it.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    local events, life = _G.BuffsmithEventFrame, "alive"
    UnitIsDeadOrGhost = function(unit) return unit == "player" and life ~= "alive" end
    ns.Inventory.items.food = { { kind = "item", itemID = 4599, name = "Cured Ham Steak", category = "food" } }
    assert(#ns.Actions:Entries() > 0, toc .. ": missing buffs exist while alive")
    equal(#ns.Actions:VisibleChoices("food"), 1, toc .. ": food available while alive")
    for _, state in ipairs({ "dead", "ghost" }) do
        life = state
        C_UnitAuras.GetAuraDataByIndex = function() error("aura scan while dead") end
        equal(#ns.Actions:Entries(), 0, toc .. ": no self or tracking reminders while " .. state)
        equal(#ns.Actions:VisibleChoices("food"), 0, toc .. ": no consumable reminders while " .. state)
        equal(#ns.Actions:BindingEntries(), 0, toc .. ": no trigger entries while " .. state)
        ns.Actions.coverageEvidence = { sentinel = "retained" }
        equal(#ns.Actions:PartyCoverage(), 0, toc .. ": no party notices while " .. state)
        equal(ns.Actions.coverageEvidence.sentinel, "retained", toc .. ": death does not forget providers")
        ns.Bindings:Prepare()
        equal(ns.Bindings.trigger:GetAttribute("type1"), nil, toc .. ": trigger disarmed while " .. state)
        events.scripts.OnEvent(events, state == "dead" and "PLAYER_DEAD" or "PLAYER_ALIVE")
        equal(ns.Palette.lastLayout, "hidden: no available actions", toc .. ": death/release event hides bar")
    end
    life = "alive"
    C_UnitAuras.GetAuraDataByIndex = function() return nil end
    for _, event in ipairs({ "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
        events.scripts.OnEvent(events, event)
        assert(#ns.Actions:Entries() > 0, toc .. ": missing buffs restore after " .. event)
        equal(ns.Bindings.trigger:GetAttribute("type1"), "spell", toc .. ": trigger restores after " .. event)
    end
    for _, event in ipairs({ "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
        local deferred
        C_Timer.After = function(delay, fn) if delay == 0 then deferred = fn end end
        life = "ghost"
        events.scripts.OnEvent(events, event)
        equal(ns.Bindings.trigger:GetAttribute("type1"), nil, toc .. ": lagging unit state stays suppressed")
        assert(deferred, toc .. ": resurrection schedules next-frame refresh")
        life = "alive"
        deferred()
        equal(ns.Bindings.trigger:GetAttribute("type1"), "spell", toc .. ": next-frame refresh recovers after " .. event)
    end
    C_Timer.After = function() end
    ns.db.visibilityMode, ns.db.legacyVisibility, ns.db.visibility = "ALWAYS", nil, {}
    equal(ns.Visibility:Rule(), "[@player,dead] hide; show", toc .. ": player death overrides always-visible rule independently of target")
    ns.db.visibility = { inCombat = true, outOfCombat = true }
    equal(ns.Visibility:Rule():sub(1, 21), "[@player,dead] hide; ", toc .. ": player death precedes configurable combat visibility")
    ns.db.legacyVisibility = { outOfCombat = true }
    equal(ns.Visibility:Rule():sub(1, 21), "[@player,dead] hide; ", toc .. ": player death precedes legacy visibility")
    ns.db.visibilityMode = "NEVER"
    equal(ns.Visibility:Rule(), "hide", toc .. ": Never stays hidden")
end

-- Loading events re-prime Thank You on both client entrypoints.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    local events, settle = _G.BuffsmithEventFrame
    C_Timer.After = function(delay, fn) if delay == 1 then settle = fn end end
    events.scripts.OnEvent(events, "PLAYER_LEAVING_WORLD")
    equal(ns.Thanks.loadingWorld, true, toc .. ": leaving world pauses Thank You")
    events.scripts.OnEvent(events, "ZONE_CHANGED_NEW_AREA")
    equal(ns.Thanks.loadingWorld, true, toc .. ": new area cannot end loading early")
    events.scripts.OnEvent(events, "PLAYER_ENTERING_WORLD")
    equal(ns.Thanks.zonePriming, true, toc .. ": entering starts settling")
    assert(settle, toc .. ": entering schedules a final aura baseline")
    events.scripts.OnEvent(events, "UNIT_AURA", "player")
    settle()
    equal(ns.Thanks.zonePriming, false, toc .. ": settled aura snapshot restores Thank You")
end

-- Every page also builds under HammerCore's Classic theme.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc, { hammerCore = { theme = "classic" } })
    local HC = ns.HammerCore
    -- Classic is switched off for players until it is reworked; keep it building.
    HC.Theme.registry.classic.available = true
    equal(HC.Theme.IsClassic(), true, toc .. ": classic theme is active")
    HC.Settings:Show()
    local failures = {}
    for name, err in pairs(HC.Settings.errors) do failures[#failures + 1] = name .. ": " .. err end
    equal(table.concat(failures, "; "), "", toc .. ": every settings page builds in classic")
    for _, spec in ipairs(HC.Settings.order) do
        HC.Settings:Show(spec.name)
        equal(HC.Settings.selected, spec.name, toc .. ": " .. spec.name .. " opens in classic")
    end
end

-- The zoom option appears only for a captured wheel key with a camera action.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    local keys = { MOUSEWHEELDOWN = "CAMERAZOOMOUT" }
    local command = ns.Bindings:Command("trigger")
    GetBindingAction = function(key) return keys[key] or "" end
    GetBindingKey = function(action)
        for key, value in pairs(keys) do if value == action then return key end end
    end
    SetBinding = function(key, action) keys[key] = action; return true end
    local settings = ns.HammerCore.Settings
    settings:Show("Key Bindings")
    local check = wow.FindText("Also zoom in/out").parent
    equal(check.parent:IsShown(), false, toc .. ": option hidden before detecting a camera binding")
    ns.Bindings:Set("trigger", "MOUSEWHEELDOWN")
    settings:Select("Key Bindings")
    equal(check.parent:IsShown(), true, toc .. ": camera wheel binding exposes option")
    equal(check.Text:GetText(), "Also zoom out", toc .. ": option names the actual zoom direction")
    equal(check:GetChecked(), false, toc .. ": camera sharing is opt-in")
    wow.Click(check)
    equal(ns.Bindings:WheelZoom().enabled, true, toc .. ": option enables shared camera action")
    ns.Bindings:Set("trigger", "F")
    settings:Select("Key Bindings")
    equal(check.parent:IsShown(), false, toc .. ": ordinary key hides camera option")
    equal(keys.MOUSEWHEELDOWN, "CAMERAZOOMOUT", toc .. ": replacing wheel restores camera action")
    ns.Bindings:Set("trigger", "MOUSEWHEELDOWN")
    settings:Select("Key Bindings")
    keys.MOUSEWHEELDOWN = "JUMP"
    local eventFrame = _G.BuffsmithEventFrame
    eventFrame.scripts.OnEvent(eventFrame, "UPDATE_BINDINGS")
    equal(check.parent:IsShown(), false, toc .. ": external rebind immediately hides stale zoom option")
end

-- Flight paths suppress every actionable reminder, then landing restores it.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    local taxi = false
    UnitOnTaxi = function(unit) equal(unit, "player", "taxi check uses player"); return taxi end
    local events = _G.BuffsmithEventFrame
    ns.Inventory.items.food = { { kind = "item", itemID = 4599, name = "Cured Ham Steak", category = "food" } }
    assert(#ns.Actions:Entries() > 0, toc .. ": reminders available before takeoff")
    taxi = true
    C_UnitAuras.GetAuraDataByIndex = function() error("reminder aura scan while flying") end
    equal(#ns.Actions:Entries(), 0, toc .. ": flight path suppresses buff and tracking reminders")
    equal(#ns.Actions:VisibleChoices("food"), 0, toc .. ": flight path suppresses consumables")
    equal(#ns.Actions:BindingEntries(), 0, toc .. ": flight path disarms trigger actions")
    ns.Actions.coverageEvidence = { sentinel = true }
    equal(#ns.Actions:PartyCoverage(), 0, toc .. ": flight path suppresses party coverage")
    equal(ns.Actions.coverageEvidence.sentinel, true, toc .. ": flight path retains provider evidence")
    events.scripts.OnEvent(events, "PLAYER_CONTROL_LOST")
    equal(ns.Bindings.trigger:GetAttribute("type1"), nil, toc .. ": takeoff disarms normal trigger")
    equal(ns.Bindings.zoomOut:GetAttribute("type1"), nil, toc .. ": takeoff disarms shared wheel buff action")
    taxi = false
    C_UnitAuras.GetAuraDataByIndex = function() return nil end
    events.scripts.OnEvent(events, "PLAYER_CONTROL_GAINED")
    equal(ns.Bindings.trigger:GetAttribute("type1"), "spell", toc .. ": landing restores trigger")
    local deferred
    C_Timer.After = function(delay, fn) if delay == 0 then deferred = fn end end
    events.scripts.OnEvent(events, "PLAYER_CONTROL_LOST")
    taxi = true
    assert(deferred, toc .. ": takeoff retries after control state settles")
    deferred()
    equal(ns.Bindings.trigger:GetAttribute("type1"), nil, toc .. ": deferred takeoff disarms trigger")
    taxi = false
    events.scripts.OnEvent(events, "UNIT_FLAGS", "player")
    equal(ns.Bindings.trigger:GetAttribute("type1"), "spell", toc .. ": flags update restores reminders")
    UnitOnTaxi = nil
end

-- Health/mana and cooldown changes refresh a known Forever recovery action.
do
    local ns = loadAddon("Buffsmith_Camelot.toc")
    local health, mana, now, cooling = 100, 100, 100, false
    local timer
    C_SpellBook.IsSpellKnown = function(id) return id == 1259705 end
    C_Spell.GetSpellInfo = function(id) return { name = id == 1259705 and "Read Leyline" or "Other", iconID = id } end
    C_Spell.GetSpellCooldown = function() return { startTime = cooling and 90 or 0, duration = cooling and 120 or 0, isEnabled = true } end
    UnitHealth, UnitHealthMax = function() return health end, function() return 100 end
    UnitPower, UnitPowerMax = function() return mana end, function() return 100 end
    GetTime = function() return now end
    C_Timer.After = function(delay, fn) if delay > 1 then timer = fn end end
    ns.Tracking.Entries = function() return {} end
    ns.ResetSpellbook()
    local events = _G.BuffsmithEventFrame
    health = 49
    events.scripts.OnEvent(events, "UNIT_HEALTH", "player")
    equal(ns.Bindings.trigger:GetAttribute("spell1"), "Read Leyline", "low health arms racial through normal event refresh")
    health = 50
    events.scripts.OnEvent(events, "UNIT_HEALTH", "player")
    equal(ns.Bindings.trigger:GetAttribute("type1"), nil, "recovering health disarms racial immediately")
    mana = 49
    events.scripts.OnEvent(events, "UNIT_POWER_UPDATE", "player", "MANA")
    equal(ns.Bindings.trigger:GetAttribute("spell1"), "Read Leyline", "low mana event arms racial")
    cooling = true
    events.scripts.OnEvent(events, "SPELL_UPDATE_COOLDOWN")
    equal(ns.Bindings.trigger:GetAttribute("type1"), nil, "cooldown event disarms racial")
    assert(timer, "cooldown schedules wakeup even with no other bar actions")
    now = 211
    timer()
    equal(ns.Bindings.trigger:GetAttribute("spell1"), "Read Leyline", "cooldown expiry re-arms without unrelated events")
end

-- Resource event gates and visibility-change deduplication.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    local health, known, combat, dead, taxi, resting = 100, true, false, false, false, false
    local refreshes, reads = 0, 0
    C_SpellBook.IsSpellKnown = function(id) return known and id == 1259705 end
    C_Spell.GetSpellCooldown = function() reads = reads + 1; return { startTime = 0, duration = 0, isEnabled = true } end
    UnitHealth, UnitHealthMax = function() return health end, function() return 100 end
    UnitPower, UnitPowerMax = function() return 100 end, function() return 100 end
    UnitIsDeadOrGhost = function() return dead end
    UnitOnTaxi = function() return taxi end
    IsResting = function() return resting end
    InCombatLockdown = function() return combat end
    ns.Tracking.Entries = function() return {} end
    ns.ResetSpellbook()
    local original = ns.RefreshAll
    ns.RefreshAll = function() refreshes = refreshes + 1; original() end
    original()
    local events = _G.BuffsmithEventFrame
    local function fire(event, unit, power) events.scripts.OnEvent(events, event, unit, power) end
    for index = 1, 20 do fire("UNIT_HEALTH", "player") end
    equal(refreshes, 0, toc .. ": unchanged healthy state does not rebuild UI")
    health = 49
    fire("UNIT_HEALTH", "party1")
    fire("UNIT_POWER_UPDATE", "player", "ENERGY")
    fire("UNIT_MAXPOWER", "player", "RAGE")
    equal(refreshes, 0, toc .. ": non-player and non-mana events are ignored")
    combat = true
    fire("UNIT_HEALTH", "player")
    equal(refreshes, 0, toc .. ": combat resource events never refresh secure UI")
    combat = false
    for index = 1, 20 do fire("UNIT_HEALTH", "player") end
    equal(refreshes, toc:find("Camelot") and 1 or 0, toc .. ": only Forever rebuilds once when crossing threshold")
    ns.db.excludedBuffs[1259705] = true
    original()
    refreshes, reads = 0, 0
    fire("UNIT_HEALTH", "player"); fire("SPELL_UPDATE_COOLDOWN")
    equal(refreshes, 0, toc .. ": excluded racial never causes event-driven rebuild")
    equal(reads, 0, toc .. ": excluded racial skips cooldown probing on events")
    ns.db.excludedBuffs[1259705] = nil
    known = false; ns.ResetSpellbook(); original()
    fire("UNIT_HEALTH", "player")
    equal(refreshes, 0, toc .. ": unknown racial does not refresh")
    if toc:find("Camelot") then
        known = true; ns.ResetSpellbook(); original()
        for _, pause in ipairs({ "dead", "taxi", "resting" }) do
            dead, taxi, resting = pause == "dead", pause == "taxi", pause == "resting"
            ns.db.ignoreBuffsInRestedAreas = resting
            fire("UNIT_HEALTH", "player")
            equal(ns.Bindings.trigger:GetAttribute("type1"), nil, pause .. " event leaves no armed recovery action")
            dead, taxi, resting = false, false, false
            ns.db.ignoreBuffsInRestedAreas = false
            original()
        end
    end
    UnitOnTaxi = nil
end

-- Binding-only preparation cannot overwrite the bar's rendered decision.
do
    local ns = loadAddon("Buffsmith_Camelot.toc")
    local health = 100
    C_SpellBook.IsSpellKnown = function(id) return id == 1259705 end
    C_Spell.GetSpellCooldown = function() return { startTime = 0, duration = 0, isEnabled = true } end
    UnitHealth, UnitHealthMax = function() return health end, function() return 100 end
    UnitPower, UnitPowerMax = function() return 100 end, function() return 100 end
    ns.Tracking.Entries = function() return {} end
    ns.ResetSpellbook(); ns.RefreshAll()
    equal(ns.Palette.recoveryDisplayed, false, "racial starts absent from bar")
    health = 49
    ns.Bindings:Prepare()
    equal(ns.Palette.recoveryDisplayed, false, "binding query does not claim racial was rendered")
    local events = _G.BuffsmithEventFrame
    events.scripts.OnEvent(events, "UNIT_HEALTH", "player")
    equal(ns.Palette.recoveryDisplayed, true, "resource event renders the missing racial")
    health = 100
    ns.Bindings:Prepare()
    equal(ns.Palette.recoveryDisplayed, true, "binding query does not claim icon was removed")
    events.scripts.OnEvent(events, "UNIT_HEALTH", "player")
    equal(ns.Palette.recoveryDisplayed, false, "resource event removes stale icon")
end

io.write("addon tests passed\n")

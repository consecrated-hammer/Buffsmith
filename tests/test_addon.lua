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
        "Appearance,Key Bindings,Buffs,Consumables,Tooltips,Thank You,Ignored,Visibility,What's new,Commands,Troubleshooting,About",
        toc .. ": rail order")
    local failures = {}
    for name, err in pairs(HC.Settings.errors) do failures[#failures + 1] = name .. ": " .. err end
    equal(table.concat(failures, "; "), "", toc .. ": every settings page builds")
    for _, spec in ipairs(HC.Settings.order) do
        HC.Settings:Show(spec.name)
        equal(HC.Settings.selected, spec.name, toc .. ": " .. spec.name .. " opens")
    end

    -- Every page builds in the new shell, including What's new.
    for _, spec in ipairs(HC.Settings.order) do HC.Settings:Show(spec.name) end
    HC.Settings:Show("Buffs", "Tracking")
    equal(wow.FindText("Find Minerals") ~= nil, true, toc .. ": the Buffs page lists tracking")
    HC.Settings:Show("Thank You")
    ns.Thanks:SetEnabled(true)
    HC.Settings.pages["Thank You"].hcRefreshAll()
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

    -- Minimap right-click: HammerCore's menu with Buffsmith's own items.
    equal(HC.Minimap.RightClickMode(), "menu", toc .. ": minimap right-click opens the menu")
    equal(HC.Minimap.RightClickLabel(), "menu", toc .. ": minimap tooltip says menu")
    local function menuItem(text)
        for _, item in ipairs(HC.Minimap:MenuItems()) do
            if item.text == text then return item end
        end
    end
    equal(menuItem("Buffsmith settings") ~= nil, true, toc .. ": menu leads with settings")
    equal(menuItem("Show bar").checked, true, toc .. ": Show bar is ticked")
    menuItem("Show bar").func()
    equal(ns.db.visibilityMode, "NEVER", toc .. ": Show bar hides the bar")
    equal(menuItem("Show bar").checked, false, toc .. ": Show bar unticks")
    menuItem("Show bar").func()
    equal(ns.db.visibilityMode, "ALWAYS", toc .. ": Show bar brings it back")
    equal(menuItem("Show drag handle").checked, true, toc .. ": Show drag handle is ticked")
    menuItem("Show drag handle").func()
    equal(ns.db.showHandle, false, toc .. ": Show drag handle hides the handle")
    menuItem("Show drag handle").func()
    equal(ns.db.showHandle, true, toc .. ": Show drag handle shows it again")
    menuItem("Rescan bags").func()
    equal(wow.LastPrint():find("bags scanned", 1, true) ~= nil, true, toc .. ": Rescan bags scans")
    HC.Minimap:RightClick()
    equal(HC.Menu:IsShown(), true, toc .. ": right-click opens the menu")
    HC.Menu:Close()
    HC.Settings:Show("Visibility")
    equal(wow.FindText("Minimap right-click") ~= nil, true, toc .. ": Visibility offers Minimap right-click")

    -- Settings search finds Buffsmith's own rows.
    local found = false
    for _, match in ipairs(HC.Settings:Search("drag handle")) do
        if match.label == "Show drag handle" then found = match.page end
    end
    equal(found ~= false, true, toc .. ": search finds Show drag handle")
    ns.db.palettePoint = { "TOP", "TOP", 5, 5 }
    SlashCmdList.BUFFSMITH("reset position")
    equal(ns.db.palettePoint[1], "TOPLEFT", toc .. ": reset position keeps fixed corner")
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

    -- The header preview button and the preview command agree.
    HC.Settings:Show("Appearance")
    equal(HC.Settings.headerAction:GetText(), "Preview on screen", toc .. ": Appearance offers the preview")
    SlashCmdList.BUFFSMITH("preview")
    equal(HC.Settings.headerAction:GetText(), "Hide preview", toc .. ": preview command updates the header")

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
    equal(ns.db.tooltipItemEffects, true, toc .. ": item effects default on")
    local itemLines = {
        [2001] = { "Hearty Stew", "Use: Restores 874 health over 30 sec. Must remain seated while eating. If you spend at least 10 seconds eating you will become well fed and gain 12 Stamina and Spirit for 15 min." },
        [2002] = { "Flask of Stuff", "Use: Increases Strength by 75 for 2 hours." },
        [2003] = { "Odd Rock", "A fine rock." },
    }
    local itemReads = 0
    C_TooltipInfo = { GetItemByID = function(id)
        itemReads = itemReads + 1
        local out = {}
        for _, text in ipairs(itemLines[id] or {}) do out[#out + 1] = { leftText = text } end
        return { lines = out }
    end }
    hover({ kind = "item", name = "Hearty Stew", itemID = 2001 })
    equal(has("Well fed: 12 Stamina and Spirit for 15 min."), true, toc .. ": food shows its Well Fed buff")
    hover({ kind = "item", name = "Flask of Stuff", itemID = 2002 })
    equal(has("Increases Strength by 75 for 2 hours."), true, toc .. ": other items show their Use line")
    local reads = itemReads
    hover({ kind = "item", name = "Flask of Stuff", itemID = 2002 })
    equal(itemReads, reads, toc .. ": item effect is cached")
    hover({ kind = "item", name = "Odd Rock", itemID = 2003 })
    equal(#lines, 3, toc .. ": no effect line without a Use line")
    ns.db.tooltipItemEffects = false
    hover({ kind = "item", name = "Hearty Stew", itemID = 2001 })
    equal(has("Well fed: 12 Stamina and Spirit for 15 min."), false, toc .. ": item effects can be turned off")
    ns.db.tooltipItemEffects = true
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

-- Moving cancels eating but uses up the food, so food hides until you stop.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    local moving = false
    IsPlayerMoving = function() return moving end
    ns.Inventory.items.food = { { kind = "item", itemID = 4599, name = "Cured Ham Steak", category = "food" } }
    equal(#ns.Actions:VisibleChoices("food"), 1, toc .. ": food offered standing still")
    moving = true
    equal(#ns.Actions:VisibleChoices("food"), 0, toc .. ": food hidden while moving")
    IsPlayerMoving = nil
    local speed = 7
    GetUnitSpeed = function() return speed end
    equal(#ns.Actions:VisibleChoices("food"), 0, toc .. ": unit speed fallback detects moving")
    speed = 0
    equal(#ns.Actions:VisibleChoices("food"), 1, toc .. ": unit speed fallback detects standing")
    GetUnitSpeed = nil

    -- Stopping starts the grace period; food returns once it has passed.
    local now, timers, refreshed = 100, {}, 0
    GetTime = function() return now end
    C_Timer.After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end
    equal(ns.db.foodStillSeconds, 5, toc .. ": five-second wait by default")
    ns.Actions:StoppedMoving(function() refreshed = refreshed + 1 end)
    equal(#ns.Actions:VisibleChoices("food"), 0, toc .. ": food waits just after stopping")
    equal(timers[#timers].delay, 5, toc .. ": refresh scheduled for the end of the wait")
    now = 105
    timers[#timers].fn()
    equal(refreshed, 1, toc .. ": wait ending refreshes the bar")
    equal(#ns.Actions:VisibleChoices("food"), 1, toc .. ": food back after the wait")
    now = 110
    ns.Actions:StoppedMoving(function() refreshed = refreshed + 1 end)
    local stale = timers[#timers]
    now = 112
    ns.Actions:StoppedMoving(function() refreshed = refreshed + 1 end)
    stale.fn()
    equal(refreshed, 1, toc .. ": an older stop's timer is ignored")
    ns.db.foodStillSeconds = 0
    equal(#ns.Actions:VisibleChoices("food"), 1, toc .. ": zero wait shows food on stopping")
    GetTime = function() return 100 end
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

-- Direct main and flyout buttons share the hardware-time guard and rearm.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    GetCVar = function() return "400" end
    C_CVar = nil
    local cd = { startTime = 100, duration = 3, isEnabled = true }
    C_Spell.GetSpellCooldown = function() return cd end
    for _, small in ipairs({ false, true }) do
        local frame = ns.Palette:Acquire(91, small)
        local entry = { kind = "spell", spellID = 465, name = "Spell 465", unit = "player" }
        ns.Actions:Configure(frame, entry)
        frame.scripts.PreClick(frame, "LeftButton")
        equal(frame:GetAttribute("type1"), nil, toc .. ": direct blocked click clears secure action")
        frame.scripts.PostClick(frame, "LeftButton")
        cd = { startTime = 0, duration = 0, isEnabled = true }
        frame.scripts.PreClick(frame, "LeftButton")
        equal(frame:GetAttribute("type1"), "spell", toc .. ": next hardware click rearms main/flyout")
        frame.scripts.PostClick(frame, "LeftButton")
        cd = { startTime = 100, duration = 3, isEnabled = true }
    end
end

-- Presentation remains useful with no actions and respects normal exclusions.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    local time, meals, pending = 100, { { name = "Food", duration = 30, expirationTime = 130 } }, {}
    GetTime = function() return time end
    C_Timer.After = function(delay, fn) pending[#pending + 1] = { delay, fn } end
    C_UnitAuras.GetAuraDataByIndex = function(_, index) return meals[index] end
    ns.KnownSelfBuffs = function() return {} end
    ns.Tracking.Entries = function() return {} end
    ns.Actions.BindingEntries = function() return {} end
    ns.Palette:Refresh()
    equal(ns.Palette.buttons.main1.buffsmithEntry.displayOnly, true, toc .. ": meal shows without missing actions")
    equal(ns.Palette.statusText:IsShown(), false, toc .. ": meal has no text row")
    equal(ns.Palette.buttons.main1.cooldown:IsShown(), true, toc .. ": meal uses native sweep")
    time = 110
    ns.Palette.frame.scripts.OnUpdate(ns.Palette.frame, 0.2)
    equal(ns.Palette.statusText:IsShown(), false, toc .. ": no timer text flash")
    meals[1].duration = nil
    ns.Palette:Refresh()
    equal(ns.Palette.buttons.main1.cooldown:IsShown(), false, toc .. ": unknown duration has no invented sweep")
    ns.db.visibilityMode = "NEVER"
    ns.Palette:Refresh()
    equal(ns.Palette.lastLayout, "hidden: preference", toc .. ": never remains hidden")
    ns.db.visibilityMode = "ALWAYS"
    UnitOnTaxi = function() return true end
    ns.Palette:Refresh()
    equal(ns.Palette.frame:IsShown(), false, toc .. ": no meal icon on taxi")
    UnitOnTaxi = function() return false end
    UnitIsDeadOrGhost = function() return true end
    ns.Palette:Refresh()
    equal(ns.Palette.frame:IsShown(), false, toc .. ": no meal icon while dead")
    UnitIsDeadOrGhost = function() return false end
    ns.db.ignoreBuffsInRestedAreas = true; IsResting = function() return true end
    ns.Palette:Refresh()
    equal(ns.Palette.frame:IsShown(), false, toc .. ": rested exclusion applies to meal icons")
    ns.db.ignoreBuffsInRestedAreas = false
    meals = { { name = "Food", duration = 30, expirationTime = 140 } }
    ns.Palette:Refresh()
    time = 141; meals = {}
    local work = pending; pending = {}
    for _, timer in ipairs(work) do if timer[1] == 30 then timer[2]() end end
    equal(ns.Palette.lastLayout, "hidden: no available actions", toc .. ": meal expiry clears icon without text or false success")
    time = 110
    -- Exercise the actual icon widget and cooldown event without an inventory scan.
    local frame = CreateFrame("Button")
    frame.buffsmithEntry = { kind = "spell", spellID = 465 }
    frame.cooldown = CreateFrame("Cooldown"); frame:Show()
    local cooldownArgs
    frame.cooldown.SetCooldown = function(_, ...) cooldownArgs = { ... } end
    ns.Palette.buttons = { test = frame }
    C_Spell.GetSpellCooldown = function() return { startTime = 110, duration = 2, isEnabled = true, modRate = 2 } end
    local scans = 0
    ns.Inventory.Refresh = function() scans = scans + 1 end
    ns.Readiness.feedbackSignature = "none"
    _G.BuffsmithEventFrame.scripts.OnEvent(_G.BuffsmithEventFrame, "SPELL_UPDATE_COOLDOWN")
    equal(cooldownArgs[2], 2, toc .. ": cooldown event updates sweep")
    equal(cooldownArgs[3], 2, toc .. ": native sweep receives rate separately")
    equal(scans, 0, toc .. ": sweep update does not rescan inventory")
    time = 113
    ns.Palette:RefreshCooldowns()
    equal(frame.cooldown:IsShown(), false, toc .. ": ended sweep clears")
    -- An earlier expiry callback cannot clear attribution for a newer same-spell press.
    local entry = { kind = "spell", spellID = 465, scope = "self" }
    local old = ns.Actions:BeginAttempt(entry)
    local newer = ns.Actions:BeginAttempt(entry)
    ns.Actions:ExpireAttempt(entry, old)
    equal(ns.Actions.lastAttempt, newer, toc .. ": old timer leaves newer attempt")
    ns.Actions:ExpireAttempt(entry, newer)
    equal(ns.Actions.lastAttempt, nil, toc .. ": own timer expires attempt")
end

-- PvE protection covers every explicit recipient, current flags and combat entry.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    local flags = { target = true, party1 = true, pet = true, partypet1 = true }
    local units = { player = true, target = true, party1 = true, party2 = true, pet = true, partypet1 = true }
    UnitIsPVP = function(unit) return flags[unit] == true end
    UnitIsPVPFreeForAll = function() return false end
    UnitExists = function(unit) return units[unit] == true end
    UnitIsUnit = function(a, b) return a == b end
    UnitIsPlayer = function(unit) return unit == "player" or unit == "target" or unit:match("^party%d+$") ~= nil end
    UnitCanAssist, UnitIsVisible, UnitIsConnected = function() return true end, function() return true end, function() return true end
    UnitPhaseReason = function() end
    IsInGroup = function() return true end
    ns.db.showTargetBuffs, ns.db.showPartyBuffs, ns.db.showPetBuffs, ns.db.showPartyCoverage = true, true, true, false
    ns.KnownSelfBuffs = function() return { { kind = "spell", spellID = 19740, name = "Test Buff", target = true } } end
    ns.Tracking.Entries = function() return {} end
    local function offered(unit)
        for _, entry in ipairs(ns.Actions:Entries()) do if (entry.unit or "player") == unit then return true end end
        return false
    end
    equal(offered("player"), true, toc .. ": self buffs remain")
    equal(offered("target"), false, toc .. ": flagged target skipped by default")
    equal(offered("party1"), false, toc .. ": flagged party member skipped")
    equal(offered("party2"), true, toc .. ": safe party alternative offered")
    equal(offered("pet"), false, toc .. ": flagged pet skipped")
    flags.player = true
    equal(offered("target"), true, toc .. ": already flagged player can buff flagged recipients")
    flags.player = nil
    ns.db.skipPvPWhileUnflagged = false
    equal(offered("target"), true, toc .. ": setting off restores targets")
    ns.db.skipPvPWhileUnflagged = true
    flags.target = false
    local entry = { kind = "spell", spellID = 19740, name = "Test Buff", unit = "target", unitGUID = "guid-target" }
    local button = ns.Bindings.trigger
    ns.Actions:Configure(button, entry)
    flags.target = true -- Flag changes after rendering, before hardware input.
    button.scripts.PreClick(button)
    equal(button:GetAttribute("type1"), nil, toc .. ": fresh flag blocks stale key action")
    button.scripts.PostClick(button)
    flags.target = false
    button.scripts.PreClick(button)
    equal(button:GetAttribute("type1"), "spell", toc .. ": safe next hardware input rearms")
    local guard = assert(loadstring("return function(self, newstate) " .. button:GetAttribute("_onstate-buffsmithpvpcombat") .. " end"))()
    guard(button, "combat")
    equal(button:GetAttribute("type1"), nil, toc .. ": combat entry securely disarms guarded external buff")
    ns.Actions:Configure(button, { kind = "spell", spellID = 19740, name = "Test Buff", unit = "player" })
    guard(button, "combat")
    equal(button:GetAttribute("type1"), "spell", toc .. ": reused self action is not a guarded external recipient")
    UnitIsPVPFreeForAll = function(unit) return unit == "target" end
    equal(ns.Actions:CanBuffUnit("target"), false, toc .. ": FFA recipient skipped too")
    local secret = {}
    issecretvalue = function(v) return v == secret end
    UnitIsPVP = function() return secret end
    equal(ns.Actions:CanBuffUnit("target"), false, toc .. ": secret flags do not establish safe recipient")
    equal(ns.Actions:CanBuffUnit("player"), true, toc .. ": unknown external flags do not disable self buffs")
    UnitIsPVP = function() error("unavailable") end
    equal(ns.Actions:CanBuffUnit("target"), false, toc .. ": failed flag API safely skips")
    issecretvalue = nil
    UnitIsPVPFreeForAll = nil
    UnitIsPVP = function(unit) if unit == "target" then return 1 end end
    equal(ns.Actions:CanBuffUnit("target"), false, toc .. ": legacy 1/nil flags supported")
    UnitIsPVP = function() return nil end
    equal(ns.Actions:CanBuffUnit("target"), true, toc .. ": legacy nil means unflagged")
    local refreshes = 0
    ns.RefreshAll = function() refreshes = refreshes + 1 end
    local events = _G.BuffsmithEventFrame
    flags.target, flags.player = true, false
    UnitIsPVP = function(unit) return flags[unit] == true end
    events.scripts.OnEvent(events, "UNIT_FACTION", "target")
    events.scripts.OnEvent(events, "UNIT_FLAGS", "target")
    equal(refreshes, 1, toc .. ": repeated unchanged flags do not rebuild")
    flags.player = true
    events.scripts.OnEvent(events, "PLAYER_FLAGS_CHANGED", "player")
    events.scripts.OnEvent(events, "UNIT_FLAGS", "party1")
    equal(refreshes, 2, toc .. ": only eligibility transitions rebuild")
end

-- Provider hints name every provider and keep the uncertainty in every variant.
do
    local ns = loadAddon("Buffsmith.toc")
    ns.Actions.providerHintIndex = 0
    local entry = { kind = "notice", name = "Fortitude", missingText = "Rowan", providerText = "Skyward" }
    equal(ns.Actions:ProviderHint(entry, true), "Skyward might have a little magic to spare.", "single provider grammar")
    entry.providerNames = { "Skyward", "Mira" }
    ns.Actions.providerHintIndex = 0
    equal(ns.Actions:ProviderHint(entry, true), "Skyward and Mira might have a little magic to spare.", "two providers joined naturally")
    entry.providerNames = { "Skyward", "Mira", "Rowan" }
    local seen = {}
    for index = 1, 12 do
        local hint = ns.Actions:ProviderHint(entry, true)
        assert(hint:find("Skyward, Mira and Rowan", 1, true), "all providers retained")
        assert(hint:find("might", 1, true) or hint:find("could", 1, true) or hint:find("may", 1, true)
            or hint:find("wouldn't", 1, true), "every hint preserves uncertainty")
        seen[hint] = true
    end
    local count = 0; for _ in pairs(seen) do count = count + 1 end
    equal(count, 12, "all twelve variants rotate without immediate repeats")
    local hint = entry.providerHint
    local rebuilt = { kind = "notice", name = entry.name, providerNames = entry.providerNames, providerText = entry.providerText }
    equal(ns.Actions:ProviderHint(rebuilt), hint, "hint survives a rebuilt coverage entry")
    local sent = {}
    SendChatMessage = function(message) sent[#sent + 1] = message end
    IsInGroup = function() return true end
    equal(ns.Actions:ReportPartyCoverage(entry), true, "explicit report allowed")
    assert(sent[1]:find(hint, 1, true), "report retains hint seen on hover")
    equal(ns.Actions:ReportPartyCoverage(entry), false, "existing report rate limit retained")
    equal(#sent, 1, "flavour does not add automatic reports")
    entry.missingText = string.rep("é", 200)
    GetTime = function() return 110 end
    ns.Actions:ReportPartyCoverage(entry)
    assert(#sent[2] <= 255, "long reports stay within chat byte limit")
end

-- The last used action remains as a non-casting sweep when eligibility hides it.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    local time, timers = 100, {}
    GetTime = function() return time end
    C_Timer.After = function(delay, fn) timers[#timers + 1] = { delay, fn } end
    C_Spell.GetSpellCooldown = function() return { startTime = 100, duration = 30, isEnabled = true } end
    ns.KnownSelfBuffs, ns.Tracking.Entries = function() return {} end, function() return {} end
    ns.CONSUMABLE_ORDER = {}
    ns.Readiness.lastEntry = { kind = "spell", spellID = 1259705, name = "Read Leyline", resourceRecovery = true, icon = 1 }
    ns.Readiness.lastEntryAt = time
    local point, relative, anchor, x, y = ns.Palette.frame:GetPoint()
    ns.Palette:Refresh()
    equal(ns.Palette.hasActions, true, toc .. ": cooldown keeps an icon in the grid")
    local ghost = ns.Palette.buttons.main1
    equal(ghost.buffsmithEntry.cooldownOnly, true, toc .. ": cooling icon is presentation only")
    equal(ghost:GetAttribute("type1"), nil, toc .. ": cooling icon has no secure cast")
    equal(ghost.cooldown:IsShown(), true, toc .. ": cooling icon has sweep")
    ns.Readiness.queueUntil = time + 0.3
    ns.Palette:Refresh()
    equal(ns.Palette.statusState, nil, toc .. ": native queue window cannot flash cooldown text")
    equal(ns.Palette.statusText:IsShown(), false, toc .. ": queue window does not reveal footer")
    equal(ghost.cooldown:IsShown(), true, toc .. ": sweep remains while queue footer is absent")
    equal(ns.Palette.recoveryDisplayed, false, toc .. ": cooldown icon does not claim actionable recovery")
    equal(ns.Bindings.trigger:GetAttribute("type1"), nil, toc .. ": cooldown icon is excluded from key binding")
    local blocked = ns.Readiness.blocked
    ghost.scripts.PreClick(ghost, "LeftButton")
    equal(ns.Readiness.blocked, blocked, toc .. ": informational clicks do not alter trigger diagnostics")
    equal(ghost:GetAttribute("type1"), nil, toc .. ": clicking cooling icon cannot rearm it")
    ghost.scripts.PostClick(ghost, "RightButton")
    equal(ns.Actions:IsSuppressed(ns.Readiness.lastEntry), false, toc .. ": informational icon cannot dismiss the spell")
    local p2, r2, a2, x2, y2 = ns.Palette.frame:GetPoint()
    equal(p2, point, toc .. ": resize keeps anchor kind")
    equal(x2, x, toc .. ": resize keeps horizontal anchor")
    equal(y2, y, toc .. ": resize keeps vertical anchor")
    time = 131
    local work = timers; timers = {}
    for _, timer in ipairs(work) do if timer[1] == 30 then timer[2]() end end
    equal(ns.Palette.cooldownDisplayKey, nil, toc .. ": cooldown expiry removes informational icon")
    equal(ns.Palette.lastLayout, "hidden: no available actions", toc .. ": finished cooldown clears otherwise empty grid")
    local _, _, _, x3, y3 = ns.Palette.frame:GetPoint()
    equal(x3, x, toc .. ": shrinking keeps horizontal handle position")
    equal(y3, y, toc .. ": shrinking keeps vertical handle position")
end

-- Reloading in combat defers anchor migration until the first OOC layout.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    local frame = ns.Palette.frame
    ns.db.paletteAnchorVersion = nil
    ns.Palette.anchorReady = nil
    frame:ClearAllPoints(); frame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    InCombatLockdown = function() return true end
    ns.Palette:Refresh()
    equal(ns.Palette.anchorReady, nil, toc .. ": no anchor writes during combat")
    InCombatLockdown = function() return false end
    ns.Palette:Refresh()
    equal(ns.Palette.anchorReady, true, toc .. ": first OOC layout migrates anchor")
    equal(ns.db.palettePoint[1], "TOPLEFT", toc .. ": combat reload cannot retain centred resize behavior")
    equal(ns.db.palettePoint[4], -120 + ns.Palette.contentHeight / 2,
        toc .. ": migration uses completed grid height rather than placeholder")
end

-- Owned consumables remain visible in the actual settings page during use pauses.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    local usable = false
    local names = { [9001] = "Coyote Steak", [9002] = "Crocolisk Steak" }
    C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end
    C_Container.GetContainerItemID = function(_, slot) return 9000 + slot end
    C_Container.GetContainerItemInfo = function() return { stackCount = 2 } end
    C_Item = {
        GetItemInfo = function(id) return { itemName = names[id], itemLink = "item:" .. id,
            itemType = "Consumable", itemSubType = "Food & Drink", iconFileID = 1 } end,
        IsUsableItem = function() return usable end,
    }
    C_TooltipInfo = { GetItemByID = function() return { lines = { { leftText = "Use: Eat to become well fed." } } } end }
    ns.Inventory:Refresh()
    ns.HC.Settings:Show("Consumables")
    equal(wow.FindText("Coyote Steak") ~= nil, true, toc .. ": settings list owned unavailable coyote steak")
    equal(wow.FindText("Crocolisk Steak") ~= nil, true, toc .. ": settings list owned unavailable crocolisk steak")
    equal(#ns.Inventory:Choices("food"), 0, toc .. ": unavailable foods never enter actions")
    assert(ns.Diagnostics:Report():find("Bag discovery: food 2", 1, true), toc .. ": diagnostics count ownership")
    assert(ns.Diagnostics:Report():find("Position: TOPLEFT CENTER", 1, true), toc .. ": diagnostics preserve full anchor tuple")
    SlashCmdList.BUFFSMITH("scan")
    assert(wow.LastPrint():find("bags scanned: food 2", 1, true), toc .. ": scan reports owned food, not use eligibility")
    usable = true
    local events = _G.BuffsmithEventFrame
    events.scripts.OnEvent(events, "PLAYER_LEVEL_UP", 10)
    equal(#ns.Inventory:Choices("food"), 2, toc .. ": level-up refresh restores newly usable cast choices")
    usable = false; ns.Inventory:Refresh()
    InCombatLockdown = function() return true end
    usable = true
    events.scripts.OnEvent(events, "PLAYER_LEVEL_UP", 11)
    equal(#ns.Inventory:Choices("food"), 0, toc .. ": level-up does not rebuild during combat")
    InCombatLockdown = function() return false end
    events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED")
    equal(#ns.Inventory:Choices("food"), 2, toc .. ": combat exit rescans deferred usability")
    ns.db.ignoreBuffsInRestedAreas = true
    IsResting = function() return true end
    ns.Inventory:Refresh()
    equal(#ns.Inventory:OwnedChoices("food"), 2, toc .. ": rested-area pause cannot remove owned items")
    equal(#ns.Actions:VisibleChoices("food"), 0, toc .. ": rested-area pause still stops reminders")
    IsResting = function() return false end
    equal(#ns.Actions:VisibleChoices("food"), 2, toc .. ": leaving rested area restores reminders")
end

-- A Thorns aura rescan during a temporary use lockout cannot strand food choices.
for _, toc in ipairs({ "Buffsmith.toc", "Buffsmith_Camelot.toc" }) do
    local ns = loadAddon(toc)
    local time, usable, thorns = 100, true, false
    local timers = {}
    GetTime = function() return time end
    C_Timer.After = function(delay, fn) timers[#timers + 1] = { delay, fn } end
    C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end
    C_Container.GetContainerItemID = function() return 9001 end
    C_Container.GetContainerItemInfo = function() return { stackCount = 3 } end
    C_Item = { GetItemInfo = function() return { itemName = "Coyote Steak", itemLink = "item:9001",
        itemType = "Consumable", itemSubType = "Food & Drink", iconFileID = 1 } end,
        IsUsableItem = function() return usable end, GetItemCooldown = function() return 0, 0, 1 end }
    C_TooltipInfo = { GetItemByID = function() return { lines = { { leftText = "Use: Eat to become well fed." } } } end }
    C_UnitAuras.GetUnitAuraBySpellID = function(_, id)
        if thorns and id == 782 then return { spellId = 782, name = "Thorns", duration = 600, expirationTime = 700 } end
    end
    ns.KnownSelfBuffs = function() return { { kind = "spell", spellID = 782, name = "Thorns" } } end
    ns.Tracking.Entries = function() return {} end
    ns.Inventory:Refresh()
    equal(#ns.Inventory:Choices("food"), 1, toc .. ": Thorns and food initially available")
    ns.Bindings.trigger.scripts.PreClick(ns.Bindings.trigger)
    usable, thorns = false, true -- Client reports a temporary lockout after casting.
    ns.Bindings.trigger.scripts.PostClick(ns.Bindings.trigger)
    local events = _G.BuffsmithEventFrame
    events.scripts.OnEvent(events, "UNIT_AURA", "player")
    equal(#ns.Inventory:Choices("food"), 0, toc .. ": food cannot cast during lockout")
    equal(#ns.Inventory:OwnedChoices("food"), 1, toc .. ": food stays owned during lockout")
    local scans = 0
    local oldSlots = C_Container.GetContainerNumSlots
    C_Container.GetContainerNumSlots = function(...) scans = scans + 1; return oldSlots(...) end
    time, usable = 102, true
    local useReads, metadataReads, tooltipReads = 0, 0, 0
    C_Item.IsUsableItem = function() useReads = useReads + 1; return usable end
    C_Item.GetItemInfo = function() metadataReads = metadataReads + 1; error("metadata scan forbidden") end
    C_TooltipInfo.GetItemByID = function() tooltipReads = tooltipReads + 1; error("tooltip scan forbidden") end
    for index = 1, 20 do
        events.scripts.OnEvent(events, "SPELL_UPDATE_USABLE")
        events.scripts.OnEvent(events, "SPELL_UPDATE_COOLDOWN")
        events.scripts.OnEvent(events, "BAG_UPDATE_COOLDOWN")
    end
    for pass = 1, 4 do
        local pending = timers; timers = {}
        for _, timer in ipairs(pending) do if timer[1] <= 0.2 then timer[2]() end end
    end
    equal(#ns.Inventory:Choices("food"), 1, toc .. ": food returns after readiness events without unrelated bag changes")
    equal(scans, 0, toc .. ": readiness events do not rescan bag slots")
    equal(metadataReads + tooltipReads, 0, toc .. ": readiness events do not reclassify items")
    equal(useReads, 1, toc .. ": event burst coalesces into one usability query")
    local displayedFood = false
    for _, frame in pairs(ns.Palette.buttons) do
        if frame:IsShown() and frame.buffsmithEntry and frame.buffsmithEntry.itemID == 9001 then displayedFood = true end
    end
    equal(displayedFood, true, toc .. ": food actually reappears in the grid")
    if toc:find("Camelot") then
        ns.db.consumableAuras[9001] = { spellID = 782, name = "Épines", duration = 600 }
        ns.Inventory.nonFoodCatalogue = nil
        ns.Inventory:PlanUsabilityWake()
        equal(ns.Inventory:LearnedAura(ns.Inventory:OwnedChoices("food")[1]) ~= nil, true,
            "missing localized data preserves an unknown mapping")
        C_Spell.GetSpellName = function(id) if id == 467 or id == 782 then return "Épines" end end
        events.scripts.OnEvent(events, "SPELL_DATA_LOAD_RESULT", 467, true)
        for pass = 1, 3 do
            local pending = timers; timers = {}
            for _, timer in ipairs(pending) do if timer[1] <= 0.2 then timer[2]() end end
        end
        equal(ns.Inventory:LearnedAura(ns.Inventory:OwnedChoices("food")[1]), nil,
            "metadata event revalidates localized class mapping without a bag event")
    end

end

io.write("addon tests passed\n")

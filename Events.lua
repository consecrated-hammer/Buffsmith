local addonName, ns = ...

local frame = CreateFrame("Frame", "BuffsmithEventFrame")
local rangeElapsed = 0
local lastTaxiState
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_CONTROL_LOST")
frame:RegisterEvent("PLAYER_CONTROL_GAINED")
frame:RegisterEvent("UNIT_FLAGS")
frame:RegisterEvent("UNIT_FACTION")
frame:RegisterEvent("PLAYER_FLAGS_CHANGED")
frame:RegisterEvent("UPDATE_BINDINGS")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
pcall(frame.RegisterEvent, frame, "SPELL_RANGE_CHECK_UPDATE")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do frame:RegisterUnitEvent(event, "player") end
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("UNIT_AURA")
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER" }) do
    frame:RegisterUnitEvent(event, "player")
end
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("UNIT_PET")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_UNGHOST")
-- Offline and phased party members stop being offered as buff targets.
pcall(frame.RegisterEvent, frame, "UNIT_CONNECTION")
pcall(frame.RegisterEvent, frame, "UNIT_PHASE")
pcall(frame.RegisterEvent, frame, "PLAYER_UPDATE_RESTING")
-- Tracking switched on or off, from the bar or the minimap menu.
pcall(frame.RegisterEvent, frame, "MINIMAP_UPDATE_TRACKING")

local lastPvPEligibility
local function pvpEligibility()
    local values = {}
    for _, unit in ipairs({ "target", "party1", "party2", "party3", "party4", "pet",
        "partypet1", "partypet2", "partypet3", "partypet4" }) do
        values[#values + 1] = ns.Actions:CanBuffUnit(unit) and "1" or "0"
    end
    return table.concat(values)
end
local function refreshPvP()
    if ns.IsCombatLocked() then return end
    local signature = pvpEligibility()
    if signature == lastPvPEligibility then return end
    lastPvPEligibility = signature
    ns.RefreshAll()
end

local function refresh()
    if ns.IsCombatLocked() then return end
    lastTaxiState = UnitOnTaxi and ns.Plain(UnitOnTaxi("player")) == true or false
    ns.Inventory:Refresh()
    ns.HC.Minimap:Update()
    ns.Handle:Update()
    ns.Preview:Refresh()
    lastPvPEligibility = pvpEligibility()
end

-- HammerCore hides settings, reports and the minimap button itself
-- (spec.hideInCombat); these are Buffsmith's own non-secure frames.
local function hideForCombat()
    if ns.Preview then ns.Preview:Hide() end
    if ns.Bindings and ns.Bindings.capture then ns.Bindings.capture:Hide() end
    GameTooltip:Hide()
end

frame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        ns.InitConfig()
        ns.Palette:Create()
        ns.Bindings:Create()
        ns.HC:Start()
        frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "UPDATE_BINDINGS" then
        ns.Bindings:SyncZoom()
        local settings = ns.HC and ns.HC.Settings
        local page = settings and settings.pages and settings.pages["Key Bindings"]
        if page and page.hcRefreshAll then page.hcRefreshAll() end
    elseif event == "PLAYER_LOGIN" then
        ns.Thanks:Observe(true)
        refresh()
    elseif event == "PLAYER_LEVEL_UP" then
        refresh()
        C_Timer.After(0, refresh)
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.Thanks:CombatStarted()
        hideForCombat()
    elseif event == "SPELL_RANGE_CHECK_UPDATE" then
        if not ns.IsCombatLocked() and ns.Palette then ns.Palette:RefreshRange() end
    elseif event == "UI_ERROR_MESSAGE" then
        if ns.Actions:HandleAuraBounce(arg2) and not ns.IsCombatLocked() then refresh() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if ns.Actions:FinishAttempt(arg3) then refresh() end
        if ns.Readiness then ns.Readiness:Feedback() end
    elseif event:match("^UNIT_SPELLCAST_") then
        if arg1 == "player" and ns.Readiness then ns.Readiness:Feedback() end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        ns.Palette:RefreshCooldowns()
        if ns.Readiness then ns.Readiness:Feedback() end
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_POWER_UPDATE"
        or event == "UNIT_MAXPOWER" or event == "SPELL_UPDATE_COOLDOWN" then
        if event == "SPELL_UPDATE_COOLDOWN" then
            ns.Palette:RefreshCooldowns()
            if ns.Readiness then ns.Readiness:Feedback() end
        end
        local powerEvent = event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER"
        if (event == "SPELL_UPDATE_COOLDOWN" or arg1 == "player")
            and (not powerEvent or arg2 == nil or arg2 == "MANA") then ns.Actions:RefreshRecovery() end
    elseif event == "UNIT_AURA" then
        if arg1 == "player" then ns.Thanks:Observe(false, arg2) end
        if arg1 == "player" or arg1 == "target" or arg1 == "pet"
            or string.match(tostring(arg1), "^partypet%d+$")
            or string.match(tostring(arg1), "^party%d+pet$") or string.match(tostring(arg1), "^party%d$") then refresh() end
    elseif event == "PLAYER_LEAVING_WORLD" then
        ns.Thanks:ZoneTransition(true)
        if ns.Readiness then ns.Readiness.queueUntil, ns.Readiness.lastEntry = nil, nil end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if event == "PLAYER_ENTERING_WORLD" or not ns.Thanks.loadingWorld then ns.Thanks:ZoneTransition(false) end
        ns.Actions:ResetDismissals()
        refresh()
    elseif event == "UNIT_FACTION" or event == "PLAYER_FLAGS_CHANGED" then
        if ns.db.skipPvPWhileUnflagged and (arg1 == "player" or arg1 == "target"
            or (type(arg1) == "string" and (arg1:match("^party%d+$") or arg1:match("^partypet%d+$")))
            or arg1 == "pet") and not ns.IsCombatLocked() then refreshPvP() end
    elseif event == "UNIT_FLAGS" then
        local onTaxi = UnitOnTaxi and ns.Plain(UnitOnTaxi("player")) == true or false
        local pvpUnit = ns.db.skipPvPWhileUnflagged and (arg1 == "player" or arg1 == "target" or arg1 == "pet"
            or (type(arg1) == "string" and (arg1:match("^party%d+$") or arg1:match("^partypet%d+$"))))
        if arg1 == "player" and onTaxi ~= lastTaxiState then refresh()
        elseif pvpUnit and not ns.IsCombatLocked() then refreshPvP() end
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST"
        or event == "PLAYER_CONTROL_LOST" or event == "PLAYER_CONTROL_GAINED" then
        refresh()
        -- Unit state can settle after the event; retry on the next frame.
        C_Timer.After(0, refresh)
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_INVENTORY_CHANGED" or event == "SPELLS_CHANGED" or event == "PLAYER_TARGET_CHANGED"
        or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_UPDATE_RESTING"
        or event == "UNIT_CONNECTION" or event == "UNIT_PHASE" or event == "UNIT_PET" or event == "MINIMAP_UPDATE_TRACKING"
        or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_DEAD" then
        if event == "SPELLS_CHANGED" then
            ns.ResetSpellbook()
            ns.Thanks.tracked, ns.Thanks.trackedNames = nil, nil
        end
        if event == "PLAYER_REGEN_ENABLED" then
            ns.Thanks:CombatEnded()
            ns.Bindings:SyncZoom()
        end
        refresh()
    end
    ns.Thanks:SaveDiagnostics()
end)

frame:SetScript("OnUpdate", function(_, elapsed)
    rangeElapsed = rangeElapsed + elapsed
    if rangeElapsed < 0.25 then return end
    rangeElapsed = 0
    if not ns.IsCombatLocked() and ns.Palette and ns.Palette.rangeWatching then ns.Palette:RefreshRange() end
end)

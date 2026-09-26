local addonName, ns = ...

local frame = CreateFrame("Frame", "BuffsmithEventFrame")
local rangeElapsed = 0
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
pcall(frame.RegisterEvent, frame, "SPELL_RANGE_CHECK_UPDATE")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("UNIT_AURA")
pcall(frame.RegisterEvent, frame, "PLAYER_UPDATE_RESTING")

local function refresh()
    if ns.IsCombatLocked() then return end
    ns.Inventory:Refresh()
    ns.Minimap:Update()
    ns.Handle:Update()
    ns.Preview:Refresh()
end

local function hideForCombat()
    if ns.Preview then ns.Preview:Hide() end
    if ns.Minimap and ns.Minimap.button then ns.Minimap.button:Hide() end
    if ns.Options and ns.Options.frame then ns.Options.frame:Hide() end
    if ns.Diagnostics and ns.Diagnostics.copy then ns.Diagnostics.copy:Hide() end
    if ns.Diagnostics and ns.Diagnostics.about then ns.Diagnostics.about:Hide() end
    if ns.Bindings and ns.Bindings.capture then ns.Bindings.capture:Hide() end
    GameTooltip:Hide()
end

frame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        ns.InitConfig()
        ns.Palette:Create()
        ns.Bindings:Create()
        ns.Minimap:Create()
        ns.Minimap:Update()
        if ns.db.showStartupMessage then
            ns.Print("loaded — version " .. tostring(ns.VERSION) .. "; type /buffsmith for settings")
        end
        frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        ns.Thanks:Observe(true)
        refresh()
    elseif event == "PLAYER_REGEN_DISABLED" then
        hideForCombat()
    elseif event == "SPELL_RANGE_CHECK_UPDATE" then
        if not ns.IsCombatLocked() and ns.Palette then ns.Palette:RefreshRange() end
    elseif event == "UI_ERROR_MESSAGE" then
        if ns.Actions:HandleAuraBounce(arg2) and not ns.IsCombatLocked() then refresh() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        ns.Actions:FinishAttempt(arg3)
    elseif event == "UNIT_AURA" then
        if arg1 == "player" then ns.Thanks:Observe(false, arg2) end
        if arg1 == "player" or arg1 == "target" or arg1 == "pet"
            or string.match(tostring(arg1), "^party%d+pet$") or string.match(tostring(arg1), "^party%d$") then refresh() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        ns.Actions:ResetDismissals()
        refresh()
    elseif event == "BAG_UPDATE_DELAYED" or event == "SPELLS_CHANGED" or event == "PLAYER_TARGET_CHANGED"
        or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_UPDATE_RESTING"
        or event == "PLAYER_REGEN_ENABLED" then
        if event == "SPELLS_CHANGED" then ns.ResetSpellbook() end
        refresh()
    end
end)

frame:SetScript("OnUpdate", function(_, elapsed)
    rangeElapsed = rangeElapsed + elapsed
    if rangeElapsed < 0.25 then return end
    rangeElapsed = 0
    if not ns.IsCombatLocked() and ns.Palette and ns.Palette.rangeWatching then ns.Palette:RefreshRange() end
end)

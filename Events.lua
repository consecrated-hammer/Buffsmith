local addonName, ns = ...

local frame = CreateFrame("Frame", "BuffsmithEventFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("UNIT_AURA")

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

frame:SetScript("OnEvent", function(_, event, arg1)
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
    elseif event == "UNIT_AURA" then
        if arg1 == "player" then ns.Thanks:Observe(false) end
        if arg1 == "player" or arg1 == "target" or arg1 == "pet"
            or string.match(tostring(arg1), "^party%d+pet$") or string.match(tostring(arg1), "^party%d$") then refresh() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        ns.Actions:ResetDismissals()
        refresh()
    elseif event == "BAG_UPDATE_DELAYED" or event == "SPELLS_CHANGED" or event == "PLAYER_TARGET_CHANGED"
        or event == "GROUP_ROSTER_UPDATE"
        or event == "PLAYER_REGEN_ENABLED" then
        refresh()
    end
end)

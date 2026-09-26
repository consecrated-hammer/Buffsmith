local addonName, ns = ...

Buffsmith = ns
ns.NAME = addonName

function ns.GetMetadata(key)
    local getter = C_AddOns and C_AddOns.GetAddOnMetadata
    local value = getter and getter(addonName, key)
    if value ~= nil then return value end
    return GetAddOnMetadata and GetAddOnMetadata(addonName, key)
end

ns.VERSION = ns.GetMetadata("Version") or "0.1.0"
ns.REVISION = ns.VERSION
ns.TARGET = ns.GetMetadata("X-Buffsmith-Target")
    or (WOW_PROJECT_ID and WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and "Mainline")
    or "Unknown"

_G.BINDING_HEADER_BUFFSMITH = "Buffsmith"
_G["BINDING_NAME_CLICK BuffsmithBindingButton:LeftButton"] = "Buff trigger — apply next missing buff"

-- Chat output, settings, commands, the minimap button and the standard
-- reference pages come from HammerCore (Libs/HammerCore); see Setup.lua.
ns.HC = ns.HammerCore
ns.Print = ns.HammerCore.Print

-- Single refresh entry point: the live bar settles its own geometry first, so
-- the preview can read the bar's real size when both are on screen.
function ns.RefreshAll()
    if ns.Palette then ns.Palette:Refresh() end
    if ns.Preview then ns.Preview:Refresh() end
end

function ns.IsCombatLocked()
    return InCombatLockdown and InCombatLockdown() or false
end

function ns.IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

function ns.Plain(value)
    if ns.IsSecret(value) then return nil end
    return value
end

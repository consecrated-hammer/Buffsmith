local addonName, ns = ...

-- The palette owns secure action buttons.  Its combat visibility therefore
-- belongs to Blizzard's state driver, not Lua Show/Hide calls at the instant
-- combat starts.  The driver also lets group scenario changes take effect
-- without rebuilding secure buttons.
ns.Visibility = {}
local Visibility = ns.Visibility

ns.VISIBILITY_CONDITIONS = {
    { key = "solo", label = "Solo", cond = "[nogroup,nocombat]" },
    { key = "inParty", label = "In a party", cond = "[group:party,nocombat]" },
    { key = "inRaid", label = "In a raid group", cond = "[group:raid,nocombat]" },
}

function Visibility:Rule()
    if ns.db.visibilityMode == "NEVER" then return "hide" end
    local parts = {}
    for _, condition in ipairs(ns.VISIBILITY_CONDITIONS) do
        if ns.db.visibility[condition.key] then parts[#parts + 1] = condition.cond .. " show" end
    end
    if #parts == 0 then return "[nocombat] show; hide" end
    return table.concat(parts, "; ") .. "; hide"
end

function Visibility:Apply(frame, hasActions)
    if not frame or ns.IsCombatLocked() then return end
    UnregisterStateDriver(frame, "visibility")
    if not hasActions then frame:Hide(); return end
    RegisterStateDriver(frame, "visibility", self:Rule())
end

function Visibility:Summary()
    if ns.db.visibilityMode == "NEVER" then return "Never" end
    local labels = {}
    for _, condition in ipairs(ns.VISIBILITY_CONDITIONS) do
        if ns.db.visibility[condition.key] then labels[#labels + 1] = condition.label end
    end
    return #labels > 0 and table.concat(labels, ", ") or "Always out of combat"
end

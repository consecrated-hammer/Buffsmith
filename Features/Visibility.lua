local addonName, ns = ...

-- The bar owns secure action buttons.  Its combat visibility therefore
-- belongs to Blizzard's state driver, not Lua Show/Hide calls at the instant
-- combat starts.  The driver also lets group scenario changes take effect
-- without rebuilding secure buttons.
ns.Visibility = {}
local Visibility = ns.Visibility

ns.VISIBILITY_CONDITIONS = {
    { key = "inCombat", label = "In combat", cond = "[combat]" },
    { key = "outOfCombat", label = "Out of combat", cond = "[nocombat]" },
    { key = "solo", label = "Solo", cond = "[nogroup]" },
    { key = "inParty", label = "In a party", cond = "[group:party]" },
    { key = "inRaid", label = "In a raid group", cond = "[group:raid]" },
}

function Visibility:Rule()
    if ns.db.visibilityMode == "NEVER" then return "hide" end
    if type(ns.db.legacyVisibility) == "table" then
        local parts = {}
        for _, condition in ipairs(ns.VISIBILITY_CONDITIONS) do
            if ns.db.legacyVisibility[condition.key] then
                parts[#parts + 1] = condition.cond:gsub("%]$", ",nocombat]") .. " show"
            end
        end
        if #parts > 0 then return table.concat(parts, "; ") .. "; hide" end
    end
    local parts = {}
    for _, condition in ipairs(ns.VISIBILITY_CONDITIONS) do
        if ns.db.visibility[condition.key] then parts[#parts + 1] = condition.cond .. " show" end
    end
    if #parts == 0 then return "show" end
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
    if type(ns.db.legacyVisibility) == "table" then
        local labels = {}
        for _, condition in ipairs(ns.VISIBILITY_CONDITIONS) do
            if ns.db.legacyVisibility[condition.key] then labels[#labels + 1] = condition.label end
        end
        if #labels > 0 then return table.concat(labels, ", ") .. " (out of combat)" end
    end
    local labels = {}
    for _, condition in ipairs(ns.VISIBILITY_CONDITIONS) do
        if ns.db.visibility[condition.key] then labels[#labels + 1] = condition.label end
    end
    if #labels == 0 then return "Always" end
    if #labels > 2 then return #labels .. " conditions" end
    return table.concat(labels, ", ")
end

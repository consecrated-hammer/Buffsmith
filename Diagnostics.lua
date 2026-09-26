local addonName, ns = ...

ns.Diagnostics = {}
local Diagnostics = ns.Diagnostics

function Diagnostics:Report()
    local foods = #ns.Inventory:Choices("food")
    local scrolls = #ns.Inventory:Choices("scroll")
    local flasks = #ns.Inventory:Choices("flask")
    local weapons = #ns.Inventory:Choices("weapon")
    local bar = ns.Palette.frame
    local point, _, relativePoint, x, y = bar and bar:GetPoint()
    local position = bar and ("%s %s %.1f %.1f"):format(
        tostring(point), tostring(relativePoint), tonumber(x) or 0, tonumber(y) or 0) or "not built"
    return table.concat({
        "Client",
        "Target: " .. tostring(ns.TARGET),
        "Combat lockdown: " .. (ns.IsCombatLocked() and "yes" or "no"),
        "Rested-area pause: " .. (ns.db.ignoreBuffsInRestedAreas and "enabled" or "disabled")
            .. "; currently resting " .. (IsResting and IsResting() and "yes" or "no"),
        "Reminder thresholds: buffs " .. tostring(ns.db.reminderPercent.buff) .. "%"
            .. ", food " .. tostring(ns.db.reminderPercent.food) .. "%"
            .. ", scrolls " .. tostring(ns.db.reminderPercent.scroll) .. "%"
            .. ", flasks " .. tostring(ns.db.reminderPercent.flask) .. "%"
            .. ", weapon enhancements " .. tostring(ns.db.reminderPercent.weapon) .. "%",
        "",
        "Self-buffs",
        "Class probe: " .. tostring(ns.lastSelfBuffClass or "not queried"),
        "Spell APIs: C_SpellBook " .. (C_SpellBook and C_SpellBook.IsSpellKnown and "yes" or "no")
            .. ", IsPlayerSpell " .. (IsPlayerSpell and "yes" or "no")
            .. ", IsSpellKnown " .. (IsSpellKnown and "yes" or "no"),
        "Spellbook: " .. ns.SpellbookSummary(),
        "Known self-buffs: " .. tostring(#ns.KnownSelfBuffs()),
        "Self-buff candidates: " .. table.concat(ns.lastSelfBuffProbe or {}, ", "),
        "Aura state: " .. table.concat(ns.lastAuraProbe or {}, ", "),
        "Target buffs: " .. table.concat(ns.lastTargetProbe or {}, ", "),
        "Party buffs: " .. (#(ns.lastPartyProbe or {}) > 0 and table.concat(ns.lastPartyProbe, ", ") or "none missing or unsupported"),
        "Pet buffs: " .. (#(ns.lastPetProbe or {}) > 0 and table.concat(ns.lastPetProbe, ", ") or "none missing or disabled"),
        "Party coverage: " .. (#(ns.lastCoverageProbe or {}) > 0 and table.concat(ns.lastCoverageProbe, ", ") or "not evaluated"),
        "Thank You: " .. (ns.db.thanksEnabled and "enabled" or "disabled")
            .. "; channel " .. tostring(ns.db.thanksChannel) .. "; emote " .. tostring(ns.db.thanksEmote)
            .. "; status " .. tostring(ns.Thanks.lastStatus),
        "Thank You scan: " .. tostring(ns.Thanks.lastScan),
        "Thank You attribution: " .. tostring(ns.Thanks.lastAttribution),
        "",
        "Consumables",
        "Bag discovery: food " .. tostring(foods) .. ", scroll " .. tostring(scrolls)
            .. ", flask " .. tostring(flasks) .. ", weapon enhancement " .. tostring(weapons),
        "Inventory: " .. tostring(ns.Inventory.lastStatus),
        "Item API: " .. tostring(ns.Inventory.lastItemInfoAPI or "not queried"),
        "Container API: " .. tostring(ns.Inventory.lastContainerAPI or "not queried"),
        "Consumable aura tracking: " .. tostring(ns.Inventory.lastConsumableAura or "no item use observed"),
        "",
        "Bar",
        "Visibility: " .. ns.Visibility:Summary(),
        "Layout: " .. tostring(ns.Palette.lastLayout),
        "Preview: " .. (ns.Preview:IsShown() and "on screen" or "closed"),
        "Position: " .. position,
        "Secure buttons prepared: " .. tostring(ns.lastSecureButtonCount or 0),
        "Key binding actions prepared: " .. tostring(ns.Bindings and ns.Bindings.lastCount or 0),
        "",
        "Privacy: configuration and client API state only.",
    }, "\n")
end

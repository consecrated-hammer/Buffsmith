local addonName, ns = ...

ns.Diagnostics = {}
local Diagnostics = ns.Diagnostics

function Diagnostics:Report()
    local foods = #ns.Inventory:OwnedChoices("food")
    local scrolls = #ns.Inventory:OwnedChoices("scroll")
    local flasks = #ns.Inventory:OwnedChoices("flask")
    local others = #ns.Inventory:OwnedChoices("other")
    local weapons = #ns.Inventory:OwnedChoices("weapon")
    local bar = ns.Palette.frame
    local point, relativeFrame, relativePoint, x, y
    if bar then point, relativeFrame, relativePoint, x, y = bar:GetPoint() end
    local position = bar and ("%s %s %.1f %.1f"):format(
        tostring(point), tostring(relativePoint), tonumber(x) or 0, tonumber(y) or 0) or "not built"
    local history = {}
    for _, entry in ipairs(ns.db.thanksDiagnostics or {}) do
        history[#history + 1] = tostring(entry.at) .. ": " .. tostring(entry.status)
            .. "; scan " .. tostring(entry.scan) .. "; attribution " .. tostring(entry.attribution)
            .. "; delay " .. tostring(entry.delay) .. "s; skip group " .. tostring(entry.skipGroup)
            .. "; unknown emote " .. tostring(entry.unknownEmote) .. "; channel " .. tostring(entry.channel)
            .. "; pending " .. tostring(entry.pending)
    end
    return table.concat({
        "Client",
        "Target: " .. tostring(ns.TARGET),
        "Combat lockdown: " .. (ns.IsCombatLocked() and "yes" or "no"),
        "Rested-area pause: " .. (ns.db.ignoreBuffsInRestedAreas and "enabled" or "disabled")
            .. "; currently resting " .. (IsResting and IsResting() and "yes" or "no"),
        "Eating or drinking (casting paused): " .. (ns.Actions:IsEating() and "yes" or "no"),
        "Reminder thresholds: buffs " .. tostring(ns.db.reminderPercent.buff) .. "%"
            .. ", food " .. tostring(ns.db.reminderPercent.food) .. "%"
            .. ", scrolls " .. tostring(ns.db.reminderPercent.scroll) .. "%"
            .. ", flasks " .. tostring(ns.db.reminderPercent.flask) .. "%"
            .. ", other buffs " .. tostring(ns.db.reminderPercent.other) .. "%"
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
        "Tracking: " .. ns.Tracking:Summary() .. (ns.Tracking.Exclusive() and " (one at a time)" or " (several at once)"),
        "Tracking offered: " .. (#(ns.lastTrackingProbe or {}) > 0 and table.concat(ns.lastTrackingProbe, ", ") or "none"),
        "Aura state: " .. table.concat(ns.lastAuraProbe or {}, ", "),
        "Target buffs: " .. table.concat(ns.lastTargetProbe or {}, ", "),
        "Party buffs: " .. (#(ns.lastPartyProbe or {}) > 0 and table.concat(ns.lastPartyProbe, ", ") or "none missing or unsupported"),
        "Pet buffs: " .. (#(ns.lastPetProbe or {}) > 0 and table.concat(ns.lastPetProbe, ", ") or "none missing or disabled"),
        "Party coverage: " .. (#(ns.lastCoverageProbe or {}) > 0 and table.concat(ns.lastCoverageProbe, ", ") or "not evaluated"),
        "Buff trigger readiness: " .. tostring(ns.Readiness and ns.Readiness.lastStatus or "not available"),
        "Buff trigger blocked presses: " .. tostring(ns.Readiness and ns.Readiness.blocked or 0),
        "Thank You: " .. (ns.db.thanksEnabled and "enabled" or "disabled")
            .. "; delay " .. tostring(ns.db.thanksDelay) .. "s"
            .. "; skip group " .. tostring(ns.db.thanksSkipGroupMembers)
            .. "; unknown emote " .. tostring(ns.db.thanksUnknownEmote)
            .. "; channel " .. tostring(ns.db.thanksChannel) .. "; emote " .. tostring(ns.db.thanksEmote)
            .. "; status " .. tostring(ns.Thanks.lastStatus),
        "Thank You scan: " .. tostring(ns.Thanks.lastScan),
        "Thank You attribution: " .. tostring(ns.Thanks.lastAttribution),
        "Recent Thank You decisions (saved locally, up to 12):\n" .. table.concat(history, "\n"),
        "",
        "Consumables",
        "Bag discovery: food " .. tostring(foods) .. ", scroll " .. tostring(scrolls)
            .. ", flask " .. tostring(flasks) .. ", other buffs " .. tostring(others)
            .. ", weapon enhancement " .. tostring(weapons),
        "Inventory: " .. tostring(ns.Inventory.lastStatus),
        "Item API: " .. tostring(ns.Inventory.lastItemInfoAPI or "not queried"),
        "Container API: " .. tostring(ns.Inventory.lastContainerAPI or "not queried"),
        "Item usability API: " .. tostring(ns.Inventory.lastUsabilityAPI or "not queried"),
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

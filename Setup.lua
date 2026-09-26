local addonName, ns = ...
local HC = ns.HammerCore

-- Declares Buffsmith to HammerCore: commands, the shared verbs, the rail
-- preview, the minimap right-click, status, diagnostics and About content.
-- Everything here is read lazily, after saved variables exist.

local anvilLines = {
    "The anvil gleams. Your buffs approve.",
    "A crisp ring echoes across Azeroth. Somewhere, a paladin nods.",
    "Polished. The forge now grants +1 confidence.",
    "The anvil reflects your face. It has seen worse gear choices.",
    "A tiny spark escapes. It is probably not a fire hazard.",
    "The anvil is immaculate. Your bags remain a separate matter.",
    "A blacksmith somewhere senses a disturbance in the profession window.",
    "Polished to raid-ready shine. The raid may still be less prepared.",
    "The hammer approves, with the restrained enthusiasm of a dwarf.",
    "Your buffs are now culturally significant.",
    "A murloc attempts to inspect the workmanship. It is removed from the premises.",
    "The anvil hums softly. This is normal. Probably.",
    "One polish closer to legendary. Two hundred and forty-seven closer to a mount drop.",
    "No durability was harmed in this ceremonial maintenance.",
    "The forge whispers: remember to eat something with a proper buff.",
    "Shiny enough to distract a rogue for almost half a second.",
    "A nearby mage requests an intellect scroll. The anvil declines to take sides.",
    "The anvil has been buffed. This is not technically useful, but it feels right.",
    "A goblin offers to sell you an anvil-polishing subscription. Declined.",
    "The sparkle is cosmetic. The sense of readiness is entirely real.",
    "Properly buffed. Professionally smug.",
    "No adventurer should leave home structurally unbuffed.",
    "Applying entirely reasonable amounts of magical preparation.",
    "Because \"I thought someone else had Fortitude\" is not a strategy.",
    "The forge is hot. Your buffs are not.",
    "Keeping heroes polished, provisioned, and mildly overprepared.",
    "Every great victory begins with someone checking the buffs.",
    "Buffs inspected. Flasks located. Standards maintained.",
    "Putting the \"prepared\" back into \"wildly overprepared\".",
    "A well-buffed adventurer is a slightly less embarrassing corpse.",
    "Forging stronger heroes, one tiny icon at a time.",
    "Someone has to notice you forgot your flask.",
    "Your equipment is enchanted. Your attitude is questionable. Your buffs are fine.",
    "No blessing left unapplied. No consumable left suspiciously unused.",
    "The difference between readiness and confidence is usually a food buff.",
    "Adventuring is dangerous enough without forgetting Mark of the Wild.",
    "Measure twice. Buff once. Check again anyway.",
    "The anvil does not judge. Buffsmith absolutely does.",
}

local function setHandle(shown)
    ns.db.showHandle = shown
    ns.Handle:Update()
    HC.Print("drag handle " .. (shown and "shown" or "hidden"))
end

local function resetBarPosition()
    ns.db.palettePoint = { "CENTER", "CENTER", 0, -120 }
    if ns.Palette.frame then
        ns.Palette.frame:ClearAllPoints()
        ns.Palette.frame:SetPoint(unpack(ns.db.palettePoint))
    end
    ns.Preview:ApplyPosition()
end

local function bagSummary()
    local parts = {}
    for _, category in ipairs({ "food", "scroll", "flask", "weapon" }) do
        parts[#parts + 1] = category .. " " .. #ns.Inventory:Choices(category)
    end
    return table.concat(parts, ", ")
end

HC:Init({
    name = "Buffsmith",
    command = "buffsmith",
    aliases = { "bs", "bsmith" },
    savedVariable = "BuffsmithDB",
    db = function() return ns.db end,
    icon = "Interface\\AddOns\\Buffsmith\\Textures\\BuffsmithLogo",
    legacy = {
        startupMessage = "showStartupMessage",
        minimap = "showMinimap",
        minimapAngle = "minimapAngle",
        settingsPoint = "settingsPoint",
    },
    hideInCombat = true,
    clientLabel = function() return ns.TARGET == "Camelot" and "WoW Forever" or "Retail" end,
    minimap = {
        icon = "Interface\\AddOns\\Buffsmith\\Textures\\BuffsmithMinimap",
        rightClick = function() setHandle(not ns.db.showHandle) end,
        rightClickLabel = "show or hide the drag handle",
    },
    railButton = {
        label = function() return ns.Preview:IsShown() and "Hide preview" or "Preview on screen" end,
        run = function() ns.Preview:Toggle() end,
        active = function() return ns.Preview:IsShown() end,
    },
    onSettingsHidden = function() ns.Preview:Hide() end,
    toggle = { help = "Show or hide the bar", run = function()
        ns.Set("visibilityMode", ns.db.visibilityMode == "NEVER" and "ALWAYS" or "NEVER")
        HC.Print("bar " .. (ns.db.visibilityMode == "NEVER" and "hidden" or "shown"))
    end },
    lock = { help = "Hide the drag handle", run = function() setHandle(false) end },
    unlock = { help = "Show the drag handle", run = function() setHandle(true) end },
    resetPosition = resetBarPosition,
    status = function()
        return table.concat({
            "Bar: " .. ns.Visibility:Summary(),
            "Known self-buffs: " .. #ns.KnownSelfBuffs(),
            "Bags: " .. bagSummary(),
        }, "\n")
    end,
    diagnostics = function() return ns.Diagnostics:Report() end,
    about = {
        note = "FROM THE FORGE",
        tips = anvilLines,
        action = "Polish the anvil",
    },
})

HC.Commands:AddAction({ section = "Bar", usage = "Left-click an icon", help = "Use that buff or item" })
HC.Commands:AddAction({ section = "Bar", usage = "Right-click an icon", help = "Dismiss it until you change zones" })
HC.Commands:AddAction({ section = "Bar", usage = "Shift-right-click an icon", help = "Ignore it; restore on Ignored" })
HC.Commands:AddAction({ section = "Bar", usage = "Hover a consumable", help = "Show your other choices" })
HC.Commands:AddAction({ section = "Bar", usage = "Drag the handle", help = "Move the bar; right-click it for settings" })

HC.Commands:Add({ name = "preview", section = "Bar", help = "Show or hide the on-screen preview",
    run = function()
        ns.Preview:Toggle()
        HC.Settings:RefreshRail()
    end })
HC.Commands:Add({ name = "scan", section = "Bar", help = "Rescan your bags for consumables",
    run = function()
        ns.Inventory:Refresh()
        HC.Print("bags scanned: " .. bagSummary())
    end })

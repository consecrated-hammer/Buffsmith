local addonName, ns = ...

ns.Diagnostics = {}
local Diagnostics = ns.Diagnostics

function Diagnostics:Report()
    local foods = #ns.Inventory:Choices("food")
    local scrolls = #ns.Inventory:Choices("scroll")
    local flasks = #ns.Inventory:Choices("flask")
    local weapons = #ns.Inventory:Choices("weapon")
    local palette = ns.Palette.frame
    local point, _, relativePoint, x, y = palette and palette:GetPoint()
    local position = palette and ("%s %s %.1f %.1f; scale %.2f"):format(
        tostring(point), tostring(relativePoint), tonumber(x) or 0, tonumber(y) or 0, palette:GetScale()) or "not built"
    return table.concat({
        "Buffsmith diagnostics",
        "",
        "Client",
        "Version: " .. tostring(ns.VERSION),
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
        "Known self-buffs: " .. tostring(#ns.KnownSelfBuffs()),
        "Self-buff candidates: " .. table.concat(ns.lastSelfBuffProbe or {}, ", "),
        "Aura state: " .. table.concat(ns.lastAuraProbe or {}, ", "),
        "Target buffs: " .. table.concat(ns.lastTargetProbe or {}, ", "),
        "Party buffs: " .. (#(ns.lastPartyProbe or {}) > 0 and table.concat(ns.lastPartyProbe, ", ") or "none missing or unsupported"),
        "Pet buffs: " .. (#(ns.lastPetProbe or {}) > 0 and table.concat(ns.lastPetProbe, ", ") or "none missing or disabled"),
        "Party coverage: " .. (#(ns.lastCoverageProbe or {}) > 0 and table.concat(ns.lastCoverageProbe, ", ") or "not evaluated"),
        "Thank-you messages: " .. (ns.db.thanksEnabled and "enabled" or "disabled")
            .. "; channel " .. tostring(ns.db.thanksChannel) .. "; status " .. tostring(ns.Thanks.lastStatus),
        "",
        "Consumables",
        "Bag discovery: food " .. tostring(foods) .. ", scroll " .. tostring(scrolls)
            .. ", flask " .. tostring(flasks) .. ", weapon enhancement " .. tostring(weapons),
        "Inventory: " .. tostring(ns.Inventory.lastStatus),
        "Item API: " .. tostring(ns.Inventory.lastItemInfoAPI or "not queried"),
        "Container API: " .. tostring(ns.Inventory.lastContainerAPI or "not queried"),
        "Consumable aura tracking: " .. tostring(ns.Inventory.lastConsumableAura or "no item use observed"),
        "",
        "Palette",
        "Visibility: " .. (ns.db.showPalette and "shown" or "hidden"),
        "Layout: " .. tostring(ns.Palette.lastLayout),
        "Position: " .. position,
        "Secure buttons prepared: " .. tostring(ns.lastSecureButtonCount or 0),
        "Key binding actions prepared: " .. tostring(ns.Bindings and ns.Bindings.lastCount or 0),
        "",
        "Privacy: configuration and client API state only.",
    }, "\n")
end

function Diagnostics:ShowCopy()
    if ns.IsCombatLocked() then return end
    if not self.copy then
        local frame = CreateFrame("Frame", "BuffsmithDiagnosticsCopy", UIParent, "BackdropTemplate")
        frame:SetSize(680, 500); frame:SetPoint("CENTER"); frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetToplevel(true); frame:EnableMouse(true)
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        frame:SetBackdropColor(0.04, 0.05, 0.07, 0.98); frame:SetBackdropBorderColor(0.55, 0.43, 0.16, 1)
        local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 20, -18); title:SetText("Buffsmith diagnostics")
        local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 21, -48); hint:SetText("Click the report, then press Ctrl+C to copy it.")
        local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        panel:SetPoint("TOPLEFT", 18, -72); panel:SetPoint("BOTTOMRIGHT", -18, 18)
        panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        panel:SetBackdropColor(0.012, 0.014, 0.02, 0.94); panel:SetBackdropBorderColor(0.32, 0.27, 0.12, 1)
        local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -10); scroll:SetPoint("BOTTOMRIGHT", -28, 10)
        local box = CreateFrame("EditBox", nil, scroll, "BackdropTemplate")
        box:SetMultiLine(true); box:SetAutoFocus(false); box:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
        box:SetTextColor(0.92, 0.92, 0.92); box:SetJustifyH("LEFT"); box:SetJustifyV("TOP")
        box:SetTextInsets(4, 4, 4, 4); box:SetWidth(600); box:SetHeight(430)
        scroll:SetScrollChild(box)
        box:SetScript("OnEscapePressed", function() frame:Hide() end)
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -3, -3); close:SetScript("OnClick", function() frame:Hide() end)
        frame.box = box; frame:Hide(); self.copy = frame
    end
    self.copy.box:SetText(self:Report()); self.copy.box:HighlightText(); self.copy:Show(); self.copy:Raise()
    self.copy.box:SetFocus()
end

function Diagnostics:ShowAbout()
    if ns.IsCombatLocked() then return end
    if not self.about then
        local frame = CreateFrame("Frame", "BuffsmithAboutFrame", UIParent, "BackdropTemplate")
        frame:SetSize(460, 245); frame:SetPoint("CENTER"); frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetToplevel(true); frame:EnableMouse(true)
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        frame:SetBackdropColor(0.04, 0.05, 0.07, 0.98); frame:SetBackdropBorderColor(0.55, 0.43, 0.16, 1)
        local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 18, -16); title:SetText("About Buffsmith")
        local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", 18, -52); text:SetWidth(420); text:SetJustifyH("LEFT"); text:SetJustifyV("TOP")
        text:SetText("Version " .. ns.VERSION .. "\n\nBuffsmith is an out-of-combat self-buff and consumable palette.\n\nFeatures include self-buffs, food, scroll, flask and weapon-enhancement discovery.\n\nLeft-click a button to use it. Right-click to dismiss it until you change zones.")
        local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        close:SetSize(100, 24); close:SetPoint("BOTTOMRIGHT", -16, 16); close:SetText("Close")
        close:SetScript("OnClick", function() frame:Hide() end)
        frame:Hide(); self.about = frame
    end
    self.about:Show(); self.about:Raise()
end

local addonName, ns = ...

ns.Palette = { buttons = {}, lastLayout = "not built" }
local Palette = ns.Palette

local function button(parent, small)
    local frame = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,BackdropTemplate")
    frame:SetSize(small and 30 or 40, small and 30 or 40)
    frame.buffsmithSmall = small == true
    frame:SetAttribute("useOnKeyDown", false)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.text = frame:CreateFontString(nil, "ARTWORK", small and "GameFontHighlightSmall" or "GameFontHighlight")
    frame.text:Hide()
    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.count:SetPoint("BOTTOMRIGHT", -3, 2)
    frame:SetScript("OnEnter", function(self)
        local entry = self.buffsmithEntry
        if not entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.name)
        if entry.kind == "notice" then
            GameTooltip:AddLine("Party coverage reminder — informational only.", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Potential provider: " .. tostring(entry.providerText), 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Missing on: " .. tostring(entry.missingText), 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Left-click: report to party. Right-click: dismiss until you change zones.", 0.7, 0.7, 0.7)
        elseif entry.kind == "item" then
            GameTooltip:AddLine("Bag item — left-click to use on yourself.", 0.7, 0.7, 0.7)
        elseif entry.scope == "target" then
            GameTooltip:AddLine("Friendly target — left-click to cast on them.", 0.7, 0.7, 0.7)
        elseif entry.scope == "party" then
            GameTooltip:AddLine("Party member — left-click to cast on them.", 0.7, 0.7, 0.7)
        elseif entry.scope == "pet" then
            GameTooltip:AddLine("Friendly pet — left-click to cast on them.", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Self-buff — left-click to cast on yourself.", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine("Right-click: dismiss until you change zones.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:SetScript("PreClick", function(self, mouseButton)
        local entry = self.buffsmithEntry
        if mouseButton == "LeftButton" and entry and entry.kind == "item" then
            ns.Inventory:BeginConsumableUse(entry)
        end
    end)
    frame:SetScript("PostClick", function(self, mouseButton)
        local entry = self.buffsmithEntry
        if entry and mouseButton == "RightButton" then
            ns.Actions:Dismiss(entry)
            ns.Palette:Refresh()
            return
        end
        if entry and mouseButton == "LeftButton" and entry.kind == "notice" then
            ns.Actions:ReportPartyCoverage(entry)
            return
        end
        if entry and entry.kind == "item" then
            ns.Actions:Remember(entry.category, entry.itemID)
            ns.Inventory:FinishConsumableUse()
        end
        C_Timer.After(0.2, function() if ns.Inventory then ns.Inventory:Refresh() end end)
    end)
    return frame
end

function Palette:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "BuffsmithPalette", UIParent, "BackdropTemplate")
    frame:SetSize(ns.db.iconSize + 4, ns.db.iconSize + 4)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    local point = ns.db.palettePoint
    frame:SetPoint(point[1], UIParent, point[2], point[3], point[4])
    frame:SetScale(ns.db.scale)
    self.frame = frame
    if ns.Handle then ns.Handle:Create(frame) end
    return frame
end

function Palette:Acquire(index, small)
    local key = (small and "sub" or "main") .. index
    self.buttons[key] = self.buttons[key] or button(self.frame, small)
    return self.buttons[key]
end

function Palette:Toggle(category)
    self.toggles = self.toggles or {}
    if self.toggles[category] then return self.toggles[category] end
    local control = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    control:SetSize(24, 22)
    control:SetScript("OnClick", function()
        ns.db.expanded[category] = not ns.db.expanded[category]
        self:Refresh()
    end)
    self.toggles[category] = control
    return control
end

local function show(buttonFrame, entry, x, y, size)
    buttonFrame:ClearAllPoints(); buttonFrame:SetPoint("TOPLEFT", x, y)
    buttonFrame:SetSize(size, size)
    buttonFrame.icon:SetTexture(entry.icon)
    buttonFrame.count:SetText(entry.count and tostring(entry.count) or "")
    if entry.kind == "spell" and entry.state == "unknown" then
        buttonFrame.icon:SetDesaturated(true)
    else
        buttonFrame.icon:SetDesaturated(false)
    end
    ns.Actions:Configure(buttonFrame, entry)
    buttonFrame:Show()
end

function Palette:Refresh()
    if not self.frame then return end
    if ns.IsCombatLocked() then self.lastLayout = "hidden: combat"; return end
    if not ns.db.showPalette then
        ns.Visibility:Apply(self.frame, false)
        self.lastLayout = "hidden: preference"
        return
    end
    self.frame:SetScale(ns.db.scale)
    ns.lastSecureButtonCount = 0
    for _, value in pairs(self.buttons) do value:Hide() end
    for _, value in pairs(self.toggles or {}) do value:Hide() end
    local mainSize = ns.db.iconSize
    local subSize = math.max(22, math.floor(mainSize * 0.76))
    local spacing = 6
    local vertical = ns.db.orientation == "VERTICAL"
    local mainX, mainY = 2, -2
    local width, height = mainSize + 4, mainSize + 4
    local mainIndex, subIndex = 0, 0
    local function placeMain(entry)
        mainIndex = mainIndex + 1
        local x, y = mainX, mainY
        show(self:Acquire(mainIndex, false), entry, x, y, mainSize)
        if vertical then
            mainY = mainY - mainSize - spacing
            height = math.max(height, -mainY + 2)
        else
            mainX = mainX + mainSize + spacing
            width = math.max(width, mainX - spacing + 2)
        end
        return x, y, self:Acquire(mainIndex, false)
    end
    local spells = ns.Actions:Entries()
    for _, entry in ipairs(spells) do
        placeMain(entry)
    end
    for _, category in ipairs({ "food", "scroll", "flask", "weapon" }) do
        local choices = ns.Actions:VisibleChoices(category)
        if #choices > 0 then
            local primary = ns.Actions:Preferred(category, choices)
            local entry = choices[primary]
            local primaryX, primaryY, expand = placeMain(entry)
            local toggle = self:Toggle(category)
            toggle:SetSize(16, 16)
            toggle:ClearAllPoints(); toggle:SetPoint("TOPRIGHT", expand, "TOPRIGHT", 2, 2)
            toggle:SetText(ns.db.expanded[category] and "−" or "+")
            toggle:Show()
            if ns.db.expanded[category] then
                local shown = 0
                for _, choice in ipairs(choices) do
                    if choice.itemID ~= entry.itemID and shown < ns.db.maxAlternatives then
                        subIndex = subIndex + 1; shown = shown + 1
                        local x, y
                        if vertical then
                            x, y = math.floor((mainSize - subSize) / 2) + 2, mainY
                            mainY = mainY - subSize - 4
                            height = math.max(height, -mainY + 2)
                        else
                            x = primaryX + math.floor((mainSize - subSize) / 2)
                            y = primaryY - mainSize - 4 - (shown - 1) * (subSize + 4)
                            height = math.max(height, -y + subSize + 4)
                        end
                        show(self:Acquire(subIndex, true), choice, x, y, subSize)
                    end
                end
            end
        end
    end
    if mainIndex == 0 then
        ns.Visibility:Apply(self.frame, false)
        self.lastLayout = "hidden: no available actions"
        ns.Actions:ArmReminder()
        if ns.Bindings then ns.Bindings:Prepare() end
        return
    end
    self.frame:SetWidth(math.max(mainSize + 4, width))
    self.frame:SetHeight(math.max(mainSize + 4, height))
    ns.Visibility:Apply(self.frame, true)
    self.lastLayout = ("%d primary, %d alternatives"):format(mainIndex, subIndex)
    if ns.Handle then ns.Handle:Update() end
    ns.Actions:ArmReminder()
    if ns.Bindings then ns.Bindings:Prepare() end
end

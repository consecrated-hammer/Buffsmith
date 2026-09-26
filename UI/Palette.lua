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
        if self.buffsmithFlyout then Palette:HoverEnter(self.buffsmithFlyout) end
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
        if entry.outOfRange then
            GameTooltip:AddLine("Out of range.", 1, 0.35, 0.35)
        end
        GameTooltip:AddLine("Right-click: dismiss until you change zones.", 0.7, 0.7, 0.7)
        if entry.kind ~= "notice" then
            GameTooltip:AddLine("Shift-right-click: ignore.", 0.7, 0.7, 0.7)
        end
        if self.buffsmithFlyout and not self.buffsmithSmall then
            GameTooltip:AddLine("Hover: show your other choices.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.buffsmithFlyout then Palette:HoverLeave() end
    end)
    frame:SetScript("PreClick", function(self, mouseButton)
        local entry = self.buffsmithEntry
        if mouseButton == "LeftButton" and entry then
            ns.Actions:BeginAttempt(entry)
            if entry.kind == "item" then ns.Inventory:BeginConsumableUse(entry) end
        end
    end)
    frame:SetScript("PostClick", function(self, mouseButton)
        local entry = self.buffsmithEntry
        if entry and mouseButton == "RightButton" then
            if IsShiftKeyDown and IsShiftKeyDown() then
                ns.Actions:Ignore(entry)
                Palette:CloseFlyout()
                local options = ns.Options
                if options and options.frame and options.frame:IsShown() then
                    options:ShowPage(options.currentPage or "overview")
                end
            else
                ns.Actions:Dismiss(entry)
            end
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
            Palette:CloseFlyout()
        end
        C_Timer.After(0.2, function() if ns.Inventory then ns.Inventory:Refresh() end end)
        C_Timer.After(0.25, function() ns.Actions:ExpireAttempt(entry) end)
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
    self.frame = frame
    if ns.Handle then ns.Handle:Create(frame) end
    return frame
end

function Palette:Acquire(index, small)
    local key = (small and "sub" or "main") .. index
    self.buttons[key] = self.buttons[key] or button(self.frame, small)
    return self.buttons[key]
end

local function applyVisualState(buttonFrame, entry)
    if (entry.kind == "spell" and entry.state == "unknown") or entry.outOfRange then
        buttonFrame.icon:SetDesaturated(true)
    else
        buttonFrame.icon:SetDesaturated(false)
    end
    if entry.outOfRange then
        buttonFrame.icon:SetVertexColor(0.55, 0.55, 0.55)
    else
        buttonFrame.icon:SetVertexColor(1, 1, 1)
    end
end

local function show(buttonFrame, entry, x, y, size, visible)
    buttonFrame:ClearAllPoints(); buttonFrame:SetPoint("TOPLEFT", x, y)
    buttonFrame:SetSize(size, size)
    buttonFrame.icon:SetTexture(entry.icon)
    buttonFrame.count:SetText(entry.count and tostring(entry.count) or "")
    applyVisualState(buttonFrame, entry)
    ns.Actions:Configure(buttonFrame, entry)
    buttonFrame:SetShown(visible ~= false)
end

-- SPELL_RANGE_CHECK_UPDATE tracks the selected target. Party and pet unit
-- tokens have no equivalent event, so refresh their non-secure icon treatment
-- on a light out-of-combat pulse without rebuilding secure actions.
function Palette:RefreshRange()
    if ns.IsCombatLocked() or not self.frame or not self.frame:IsShown() then return false end
    local watching = false
    for _, buttonFrame in pairs(self.buttons) do
        local entry = buttonFrame.buffsmithEntry
        if buttonFrame:IsShown() and entry and entry.kind == "spell" and entry.unit and entry.unit ~= "player" then
            watching = true
            entry.outOfRange = ns.Actions:RangeState(entry) == false
            applyVisualState(buttonFrame, entry)
        end
    end
    return watching
end

-- Flyouts: a category's other choices open beside its primary while the mouse
-- is over the primary or the flyout. They are secure buttons like any other, so
-- they are only shown or hidden out of combat; the bar itself is hidden by its
-- state driver in combat, which takes them with it.
local FLYOUT_GRACE = 0.3

function Palette:ApplyFlyout()
    for _, value in pairs(self.buttons) do
        if value.buffsmithSmall then
            value:SetShown(self.openFlyout ~= nil and value.buffsmithFlyout == self.openFlyout)
        end
    end
end

function Palette:OpenFlyout(category)
    if ns.IsCombatLocked() then return end
    self.openFlyout = category
    self:ApplyFlyout()
end

function Palette:CloseFlyout()
    self.openFlyout = nil
    if not ns.IsCombatLocked() then self:ApplyFlyout() end
end

function Palette:HoverEnter(category)
    self.hoverCategory = category
    if self.openFlyout ~= category then self:OpenFlyout(category) end
end

function Palette:HoverLeave()
    self.hoverCategory = nil
    C_Timer.After(FLYOUT_GRACE, function()
        if not self.hoverCategory then self:CloseFlyout() end
    end)
end

function Palette.FlyoutSide(frame, vertical)
    local preference = vertical and ns.db.flyoutVerticalDirection or ns.db.flyoutHorizontalDirection
    if preference and preference ~= "AUTO" then return preference end
    local x, y = frame:GetCenter()
    return ns.Layout.FlyoutSide(vertical, x, y, UIParent:GetWidth(), UIParent:GetHeight())
end

-- Resolves the live bar's contents into ns.Layout's item list. Flyout icons
-- follow their primary in item order, which is the order Layout returns them.
function Palette:Items()
    local items, mainEntries, subEntries, mainCategories = {}, {}, {}, {}
    for _, entry in ipairs(ns.Actions:Entries()) do
        items[#items + 1] = {}
        mainEntries[#mainEntries + 1] = entry
    end
    for _, category in ipairs({ "food", "scroll", "flask", "weapon" }) do
        local choices = ns.Actions:VisibleChoices(category)
        if #choices > 0 then
            local entry = choices[ns.Actions:Preferred(category, choices)]
            mainEntries[#mainEntries + 1] = entry
            mainCategories[#mainEntries] = category
            local shown = 0
            for _, choice in ipairs(choices) do
                if choice.itemID ~= entry.itemID and shown < ns.db.maxAlternatives then
                    shown = shown + 1
                    subEntries[#subEntries + 1] = choice
                end
            end
            items[#items + 1] = { subs = shown }
        end
    end
    return items, mainEntries, subEntries, mainCategories
end

function Palette:Refresh()
    if not self.frame then return end
    if ns.IsCombatLocked() then self.lastLayout = "hidden: combat"; return end
    if ns.db.visibilityMode == "NEVER" then
        ns.Actions:UpdateTargetRangeChecks({})
        self.rangeWatching = false
        ns.Visibility:Apply(self.frame, false)
        self.lastLayout = "hidden: preference"
        if ns.Bindings then ns.Bindings:Prepare() end
        return
    end
    ns.lastSecureButtonCount = 0
    for _, value in pairs(self.buttons) do
        value:Hide()
        value.buffsmithFlyout = nil
    end
    local items, mainEntries, subEntries, mainCategories = self:Items()
    ns.Actions:UpdateTargetRangeChecks(mainEntries)
    local vertical = ns.db.orientation == "VERTICAL"
    local layout = ns.Layout.Compute(items, {
        mainSize = ns.db.iconSize,
        vertical = vertical,
        flyout = Palette.FlyoutSide(self.frame, vertical),
    })
    if #layout.mains == 0 then
        self.openFlyout = nil
        self.rangeWatching = false
        ns.Visibility:Apply(self.frame, false)
        self.lastLayout = "hidden: no available actions"
        ns.Actions:ArmReminder()
        if ns.Bindings then ns.Bindings:Prepare() end
        return
    end
    local hasFlyout = {}
    for _, placement in ipairs(layout.subs) do hasFlyout[placement.parent] = true end
    for index, placement in ipairs(layout.mains) do
        local main = self:Acquire(index, false)
        show(main, mainEntries[index], placement.x, placement.y, placement.size)
        main.buffsmithFlyout = hasFlyout[index] and mainCategories[index] or nil
    end
    local stillOpen = false
    for index, placement in ipairs(layout.subs) do
        local sub = self:Acquire(index, true)
        show(sub, subEntries[index], placement.x, placement.y, placement.size, false)
        sub.buffsmithFlyout = mainCategories[placement.parent]
        if sub.buffsmithFlyout == self.openFlyout then stillOpen = true end
    end
    if not stillOpen then self.openFlyout = nil end
    self:ApplyFlyout()
    self.frame:SetWidth(layout.width)
    self.frame:SetHeight(layout.height)
    ns.Visibility:Apply(self.frame, true)
    self.rangeWatching = self:RefreshRange()
    self.lastLayout = ("%d primary, %d alternatives"):format(#layout.mains, #layout.subs)
    if ns.Handle then ns.Handle:Update() end
    ns.Actions:ArmReminder()
    if ns.Bindings then ns.Bindings:Prepare() end
end

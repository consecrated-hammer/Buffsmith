local addonName, ns = ...

ns.Palette = { buttons = {}, lastLayout = "not built" }
local Palette = ns.Palette

local function recipientName(entry)
    local unit = entry.unit or "player"
    if UnitExists and not UnitExists(unit) then return nil end
    if entry.unitGUID and UnitGUID and ns.Plain(UnitGUID(unit)) ~= ns.Plain(entry.unitGUID) then return nil end
    if not UnitName then return nil end
    local name, realm = UnitName(unit)
    name, realm = ns.Plain(name), ns.Plain(realm)
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) == "string" and realm ~= "" then name = name .. "-" .. realm end
    return name
end

local function spellDescription(entry)
    if not ns.db.tooltipSpellDescriptions or (entry.kind ~= "spell" and entry.kind ~= "notice") then return nil end
    local spellID = entry.castID or entry.spellID
    local getter = C_Spell and C_Spell.GetSpellDescription
    if type(getter) ~= "function" then getter = GetSpellDescription end
    if type(spellID) ~= "number" or type(getter) ~= "function" then return nil end
    local ok, text = pcall(getter, spellID)
    if not ok then return nil end
    text = ns.Plain(text)
    if type(text) == "string" and text ~= "" then return text end
end

local function button(parent, small)
    local frame = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,SecureHandlerStateTemplate,BackdropTemplate")
    frame:SetSize(small and 30 or 40, small and 30 or 40)
    frame.buffsmithSmall = small == true
    frame:SetAttribute("useOnKeyDown", false)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.text = frame:CreateFontString(nil, "ARTWORK", small and "GameFontHighlightSmall" or "GameFontHighlight")
    frame.text:Hide()
    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints(frame.icon)
    frame.cooldown:EnableMouse(false)
    if frame.cooldown.SetDrawEdge then frame.cooldown:SetDrawEdge(true) end
    if frame.cooldown.SetHideCountdownNumbers then frame.cooldown:SetHideCountdownNumbers(false) end
    frame.cooldown:Hide()
    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.count:SetPoint("BOTTOMRIGHT", -3, 2)
    frame:SetScript("OnEnter", function(self)
        if self.buffsmithFlyout then Palette:HoverEnter(self.buffsmithFlyout) end
        local entry = self.buffsmithEntry
        if not entry or ns.db.showTooltip == false then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.name)
        if entry.kind == "spell" and not entry.tracking and not entry.cooldownOnly then
            local name = recipientName(entry)
            GameTooltip:AddLine(name and ("Cast on: " .. name) or "Recipient unavailable.", 0.8, 0.8, 0.8, true)
        end
        if entry.cooldownOnly then
            GameTooltip:AddLine("On cooldown. This icon cannot cast.", 0.8, 0.8, 0.8, true)
        elseif entry.kind == "notice" then
            GameTooltip:AddLine("Party coverage reminder — informational only.", 0.7, 0.7, 0.7)
            GameTooltip:AddLine(ns.Actions:ProviderHint(entry, true), 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Missing on: " .. tostring(entry.missingText), 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Left-click: report to party. Right-click: dismiss until you change zones.", 0.7, 0.7, 0.7)
        elseif entry.kind == "item" then
            if entry.poison then
                GameTooltip:AddLine(entry.targetSlot == 17 and "Left-click: coat your off-hand weapon."
                    or "Left-click: coat your main-hand weapon.", 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("Bag item — left-click to use on yourself.", 0.7, 0.7, 0.7)
            end
        elseif entry.tracking then
            GameTooltip:AddLine("Tracking — left-click to turn it on.", 0.7, 0.7, 0.7)
        elseif entry.scope == "target" or entry.scope == "party" or entry.scope == "pet" then
            GameTooltip:AddLine("Left-click: cast on them.", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Self-buff — left-click to cast on yourself.", 0.7, 0.7, 0.7)
        end
        local description = spellDescription(entry)
        if description then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(description, 0.72, 0.72, 0.72, true)
            GameTooltip:AddLine(" ")
        end
        if entry.outOfRange then
            GameTooltip:AddLine("Out of range.", 1, 0.35, 0.35)
        end
        if ns.Actions.eatingPaused and entry.kind ~= "notice" then
            GameTooltip:AddLine(ns.Actions.EATING_NOTICE, 1, 0.82, 0)
        end
        if not entry.cooldownOnly then GameTooltip:AddLine("Right-click: dismiss until you change zones.", 0.7, 0.7, 0.7) end
        if entry.kind ~= "notice" and not entry.cooldownOnly then
            GameTooltip:AddLine("Shift-right-click: ignore.", 0.7, 0.7, 0.7)
        end
        if self.buffsmithFlyout and not self.buffsmithSmall then
            GameTooltip:AddLine("Hover: show your other choices.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        if self.buffsmithFlyout then Palette:HoverLeave() end
    end)
    frame:SetScript("PreClick", function(self, mouseButton)
        local entry = self.buffsmithEntry
        self.buffsmithPress, self.buffsmithAttempt = nil, nil
        if entry and entry.cooldownOnly then return end
        if mouseButton == "LeftButton" and entry and entry.kind ~= "notice" and ns.Readiness then
            self.buffsmithPress = ns.Readiness:Press(self, entry)
            if not self.buffsmithPress.allow then return end
            entry = self.buffsmithPress.entry
        end
        if mouseButton == "LeftButton" and entry and ns.Actions.eatingPaused and entry.kind ~= "notice" then
            ns.Actions:ShowEatingNotice()
        elseif mouseButton == "LeftButton" and entry then
            self.buffsmithAttempt = ns.Actions:BeginAttempt(entry)
            if entry.kind == "item" then ns.Inventory:BeginConsumableUse(entry) end
        end
    end)
    frame:SetScript("PostClick", function(self, mouseButton)
        local entry = self.buffsmithEntry
        if entry and entry.cooldownOnly then return end
        if entry and mouseButton == "RightButton" then
            if IsShiftKeyDown and IsShiftKeyDown() then
                ns.Actions:Ignore(entry)
                Palette:CloseFlyout()
                local settings = ns.HC.Settings
                if settings:IsShown() then settings:Select(settings.selected) end
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
        if ns.Actions.eatingPaused or (self.buffsmithPress and not self.buffsmithPress.allow) then return end
        entry = self.buffsmithPress and self.buffsmithPress.entry or entry
        if entry and entry.kind == "item" then
            ns.Actions:RememberItem(entry)
            ns.Inventory:FinishConsumableUse()
            Palette:CloseFlyout()
        end
        C_Timer.After(0.2, function() if ns.Inventory then ns.Inventory:Refresh() end end)
        local attempt = self.buffsmithAttempt
        if attempt then C_Timer.After(0.25, function() ns.Actions:ExpireAttempt(entry, attempt) end) end
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
    -- The fixed handle, rather than a status-widened frame centre, determines
    -- which side faces away from the nearest screen edge.
    if type(x) == "number" then x = x - frame:GetWidth() / 2 end
    if type(y) == "number" then y = y + frame:GetHeight() / 2 end
    return ns.Layout.FlyoutSide(vertical, x, y, UIParent:GetWidth(), UIParent:GetHeight())
end

-- Resolves the live bar's contents into ns.Layout's item list. Flyout icons
-- follow their primary in item order, which is the order Layout returns them.
function Palette:CooldownEntry()
    if not ns.Readiness or not ns.Readiness:DisplayAllowed() then return nil end
    local entry = ns.Readiness.lastEntry
    if not entry or (entry.kind ~= "spell" and entry.kind ~= "item") then return nil end
    if ns.Actions:IsSuppressed(entry) or (entry.kind == "spell" and ns.db.excludedBuffs[entry.spellID])
        or (entry.kind == "item" and ns.db.excludedConsumables[entry.itemID]) then return nil end
    if entry.kind == "spell" and not ns.Actions:CanBuffUnit(entry.unit) then return nil end
    local key = ns.Readiness:Key(entry)
    if self.renderedActionKeys and self.renderedActionKeys[key] then return nil end
    local cd = ns.Readiness:Cooldown(entry)
    if not cd or not cd.enabled or cd.remaining <= 0 then return nil end
    local copy = {}
    for field, value in pairs(entry) do copy[field] = value end
    copy.cooldownOnly, copy.outOfRange = true, false
    return copy, key, cd
end

function Palette:UpdateFeedback()
    if ns.IsCombatLocked() then return end
    local _, key = self:CooldownEntry()
    if key ~= self.cooldownDisplayKey then self:Refresh() else self:RefreshStatus() end
end

function Palette:Items()
    local items, mainEntries, subEntries, mainCategories = {}, {}, {}, {}
    for _, entry in ipairs(ns.Actions:Entries()) do
        items[#items + 1] = {}
        mainEntries[#mainEntries + 1] = entry
    end
    for _, category in ipairs(ns.CONSUMABLE_ORDER) do
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
    self.renderedActionKeys = {}
    for _, entry in ipairs(mainEntries) do self.renderedActionKeys[ns.Readiness:Key(entry)] = true end
    for _, entry in ipairs(subEntries) do self.renderedActionKeys[ns.Readiness:Key(entry)] = true end
    local cooldown, key, cd = self:CooldownEntry()
    self.cooldownDisplayKey = key
    if cooldown then
        items[#items + 1] = {}
        mainEntries[#mainEntries + 1] = cooldown
        if self.cooldownWakeAt ~= cd.ends then
            self.cooldownWakeAt = cd.ends
            local deadline = cd.ends
            C_Timer.After(cd.remaining, function()
                if self.cooldownWakeAt ~= deadline then return end
                self.cooldownWakeAt = nil
                if not ns.IsCombatLocked() then self:Refresh() end
            end)
        end
    else self.cooldownWakeAt = nil end
    return items, mainEntries, subEntries, mainCategories
end

-- Only a full bar/trigger refresh owns this cache. Binding-only preparation
-- may query Entries without changing what the bar currently displays.
function Palette:RecordRecovery(entries)
    self.recoveryDisplayed = false
    for _, entry in ipairs(entries) do
        if entry.resourceRecovery and not entry.cooldownOnly then self.recoveryDisplayed = true; break end
    end
end

function Palette:RefreshCooldowns()
    if ns.IsCombatLocked() or not ns.Readiness then return end
    for _, frame in pairs(self.buttons) do
        if frame:IsShown() then
            local cd = ns.Readiness:Cooldown(frame.buffsmithEntry)
            if cd and cd.enabled and cd.remaining > 0 then
                frame.cooldown:SetCooldown(cd.start, cd.duration, cd.rate)
                frame.cooldown:Show()
            else frame.cooldown:Hide() end
        end
    end
end

local function statusText(state)
    if not state then return "" end
    local remaining = state.ends and GetTime and math.max(0, state.ends - GetTime())
    if not remaining then return state.kind == "meal" and (state.label .. ": casts paused") or state.label end
    if remaining >= 60 then return state.label .. ": " .. math.ceil(remaining / 60) .. "m" end
    return state.label .. ": " .. (remaining >= 10 and tostring(math.ceil(remaining)) or string.format("%.1f", remaining)) .. "s"
end

function Palette:PrepareStatus()
    if not ns.Readiness then return false end
    if not self.statusText then
        self.statusText = self.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        self.statusText:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, 4)
        self.statusText:SetJustifyH("CENTER")
        if self.statusText.SetWordWrap then self.statusText:SetWordWrap(false) end
        self.statusElapsed = 0
        self.frame:HookScript("OnUpdate", function(_, elapsed)
            if ns.IsCombatLocked() or not self.statusState then return end
            self.statusElapsed = self.statusElapsed + elapsed
            if self.statusElapsed < 0.1 then return end
            self.statusElapsed = 0
            self.statusText:SetText(statusText(self.statusState))
            if self.statusState.ends and self.statusState.ends <= GetTime() and not self.statusExpired then
                self.statusExpired = true
                C_Timer.After(0, function() if not ns.IsCombatLocked() then ns.Readiness:Feedback() end end)
            end
        end)
    end
    self.statusState = ns.Readiness:Status()
    ns.Readiness.feedbackSignature = ns.Readiness:Signature(self.statusState)
    self.statusExpired = nil
    self.statusText:SetText(statusText(self.statusState))
    self.statusText:SetShown(self.statusState ~= nil)
    return self.statusState ~= nil
end

-- Timer/event feedback only changes presentation, never scans action choices.
function Palette:RefreshStatus()
    if not self.frame or ns.IsCombatLocked() or ns.db.visibilityMode == "NEVER" then return end
    if not self.anchorReady then self:Refresh(); return end
    local hasStatus = self:PrepareStatus()
    local width, height = self.contentWidth or 0, self.contentHeight or 0
    self.frame:SetWidth(hasStatus and math.max(170, width) or math.max(1, width))
    self.frame:SetHeight(math.max(1, height + (hasStatus and (self.hasActions and 24 or 26) or 0)))
    ns.Visibility:Apply(self.frame, self.hasActions or hasStatus)
    if not self.hasActions then self.lastLayout = hasStatus and "status only: waiting" or "hidden: no available actions" end
    if ns.Handle then ns.Handle:Update() end
end

function Palette:Refresh()
    if not self.frame then return end
    if ns.IsCombatLocked() then self.lastLayout = "hidden: combat"; return end
    if ns.db.visibilityMode == "NEVER" then
        self:RecordRecovery(ns.Actions:Entries())
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
    self:RecordRecovery(mainEntries)
    self.hasActions = #items > 0
    local hasStatus = self:PrepareStatus()
    ns.Actions:UpdateTargetRangeChecks(mainEntries)
    local vertical = ns.db.orientation == "VERTICAL"
    local layout = ns.Layout.Compute(items, {
        mainSize = ns.db.iconSize,
        vertical = vertical,
        flyout = Palette.FlyoutSide(self.frame, vertical),
    })
    if not self.anchorReady and ns.Handle then
        self.frame:SetWidth(layout.width)
        self.frame:SetHeight(layout.height)
        self.anchorReady = ns.Handle:Anchor(self.frame)
        if ns.Preview then ns.Preview:ApplyPosition() end
    end
    self.contentWidth, self.contentHeight = layout.width, layout.height
    self.hasActions = #layout.mains > 0
    if #layout.mains == 0 then
        self.contentWidth, self.contentHeight = 0, 0
        self.openFlyout = nil
        self.rangeWatching = false
        self.frame:SetWidth(170)
        self.frame:SetHeight(26)
        ns.Visibility:Apply(self.frame, hasStatus)
        self.lastLayout = hasStatus and "status only: waiting" or "hidden: no available actions"
        if ns.Handle then ns.Handle:Update() end
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
    self.frame:SetWidth(hasStatus and math.max(170, layout.width) or layout.width)
    self.frame:SetHeight(layout.height + (hasStatus and 24 or 0))
    ns.Visibility:Apply(self.frame, true)
    self:RefreshCooldowns()
    self.rangeWatching = self:RefreshRange()
    self.lastLayout = ("%d primary, %d alternatives"):format(#layout.mains, #layout.subs)
    if ns.Handle then ns.Handle:Update() end
    ns.Actions:ArmReminder()
    if ns.Bindings then ns.Bindings:Prepare() end
end

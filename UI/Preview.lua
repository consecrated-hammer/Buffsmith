local addonName, ns = ...

-- A non-secure stand-in for the bar, so the player can see where it sits while
-- nothing is actually missing. It shares ns.Layout with the live bar but never
-- touches Actions:Configure, Visibility:Apply or a secure template: a preview
-- that armed real actions could cast something on click, and would leave those
-- attributes behind when it closed.

ns.Preview = { icons = {}, expanded = false }
local Preview = ns.Preview

local QUESTION_MARK = 134400
local WELL_FED = 136000
local BORDER = { 0.78, 0.59, 0.20, 0.9 }

function Preview:Items()
    local items, mainIcons, subIcons = {}, {}, {}
    for index, buff in ipairs(ns.KnownSelfBuffs()) do
        if index > 3 then break end
        items[#items + 1] = {}
        mainIcons[#mainIcons + 1] = buff.icon or QUESTION_MARK
    end

    local choices = ns.Inventory and ns.Inventory:Choices("food") or {}
    local alternatives = self.expanded and math.min(ns.db.maxAlternatives, 2) or 0
    items[#items + 1] = { toggle = "food", subs = alternatives }
    mainIcons[#mainIcons + 1] = choices[1] and choices[1].icon or WELL_FED
    for index = 1, alternatives do
        local choice = choices[index + 1]
        subIcons[#subIcons + 1] = choice and choice.icon or WELL_FED
    end

    if ns.db.showPartyCoverage then
        items[#items + 1] = {}
        mainIcons[#mainIcons + 1] = QUESTION_MARK
    end
    return items, mainIcons, subIcons
end

function Preview:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "BuffsmithPreview", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0, 0, 0, 0.35)
    frame:SetBackdropBorderColor(unpack(BORDER))
    frame:SetAlpha(0.85)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 16, 3)
    label:SetText("PREVIEW")
    label:SetTextColor(unpack(BORDER))
    self.label = label

    self.handle = ns.Handle.Attach(frame, "BuffsmithPreviewHandle", {
        title = "Buffsmith preview",
        dragHint = "Drag: move the bar",
        onMoved = function() Preview:ApplyLivePosition() end,
    })

    local toggle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    toggle:SetSize(16, 16)
    toggle:SetScript("OnClick", function()
        Preview.expanded = not Preview.expanded
        Preview:Refresh()
    end)
    self.toggle = toggle

    self.frame = frame
    self:ApplyPosition()
    frame:Hide()
    return frame
end

function Preview:Acquire(index)
    self.icons[index] = self.icons[index] or self.frame:CreateTexture(nil, "ARTWORK")
    return self.icons[index]
end

function Preview:ApplyPosition()
    if not self.frame then return end
    local point = ns.db.palettePoint
    self.frame:ClearAllPoints()
    self.frame:SetPoint(point[1], UIParent, point[2], point[3], point[4])
end

-- The player drags whichever of the two is on screen, so a preview drag has to
-- carry the live bar with it or the bar would not move until the next reload.
function Preview:ApplyLivePosition()
    if ns.IsCombatLocked() then return end
    local bar = ns.Palette and ns.Palette.frame
    if not bar then return end
    local point = ns.db.palettePoint
    bar:ClearAllPoints()
    bar:SetPoint(point[1], UIParent, point[2], point[3], point[4])
end

function Preview:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    self:ApplyPosition()
    for _, icon in ipairs(self.icons) do icon:Hide() end

    -- While the live bar is on screen the two would sit at the same point and
    -- draw two sets of icons, so the preview keeps only its outline and lets
    -- the real bar show through.
    local bar = ns.Palette and ns.Palette.frame
    local bare = bar and bar:IsShown()
    if bare then
        self.toggle:Hide()
        self.frame:SetSize(math.max(bar:GetWidth(), 8), math.max(bar:GetHeight(), 8))
        self.label:SetText("PREVIEW — live bar shown")
        return
    end

    self.label:SetText("PREVIEW")
    local items, mainIcons, subIcons = self:Items()
    local layout = ns.Layout.Compute(items, {
        mainSize = ns.db.iconSize,
        vertical = ns.db.orientation == "VERTICAL",
    })
    local index = 0
    for position, placement in ipairs(layout.mains) do
        index = index + 1
        local icon = self:Acquire(index)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", placement.x, placement.y)
        icon:SetSize(placement.size, placement.size)
        icon:SetTexture(mainIcons[position])
        icon:Show()
    end
    for position, placement in ipairs(layout.subs) do
        index = index + 1
        local icon = self:Acquire(index)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", placement.x, placement.y)
        icon:SetSize(placement.size, placement.size)
        icon:SetTexture(subIcons[position])
        icon:Show()
    end
    local foodIndex = layout.toggles.food
    if foodIndex then
        local anchor = layout.mains[foodIndex]
        self.toggle:ClearAllPoints()
        self.toggle:SetPoint("TOPRIGHT", self.frame, "TOPLEFT", anchor.x + anchor.size + 2, anchor.y + 2)
        self.toggle:SetText(self.expanded and "−" or "+")
        self.toggle:Show()
    else
        self.toggle:Hide()
    end
    self.frame:SetSize(layout.width, layout.height)
end

function Preview:Show()
    if ns.IsCombatLocked() then return end
    self:Create()
    self.frame:Show()
    self.handle:Show()
    self:Refresh()
end

function Preview:Hide()
    if not self.frame then return end
    self.expanded = false
    self.frame:Hide()
end

function Preview:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

function Preview:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

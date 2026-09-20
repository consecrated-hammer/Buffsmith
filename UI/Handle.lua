local addonName, ns = ...

ns.Handle = {}
local Handle = ns.Handle

function Handle:Create(parent)
    if self.frame then return self.frame end
    local frame = CreateFrame("Button", "BuffsmithHandle", parent, "BackdropTemplate")
    frame:SetSize(12, 10)
    frame:SetFrameLevel(parent:GetFrameLevel() + 10)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("RightButtonUp")
    frame:EnableMouse(true)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.49, 0.35, 0.13, 0.96)
    frame:SetBackdropBorderColor(0.08, 0.06, 0.02, 1)
    local dots = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dots:SetPoint("CENTER", 0, 1); dots:SetText(":")
    frame:SetScript("OnDragStart", function()
        if not ns.IsCombatLocked() then parent:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function()
        if ns.IsCombatLocked() then return end
        parent:StopMovingOrSizing()
        local point, _, relativePoint, x, y = parent:GetPoint()
        ns.db.palettePoint = { point, relativePoint, x, y }
    end)
    frame:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then ns.Options:Toggle() end
    end)
    frame:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.78, 0.59, 0.20, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Buffsmith")
        GameTooltip:AddLine("Drag: move the palette", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Right-click: open settings", 0.85, 0.85, 0.85)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.49, 0.35, 0.13, 0.96)
        GameTooltip:Hide()
    end)
    self.frame = frame
    self:Update()
    return frame
end

function Handle:Update()
    if not self.frame then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOM", self.frame:GetParent(), "TOP", 0, 2)
    self.frame:SetShown(ns.db.showHandle == true and not ns.IsCombatLocked())
end

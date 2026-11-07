local addonName, ns = ...

ns.Handle = {}
local Handle = ns.Handle

local IDLE = { 0.49, 0.35, 0.13, 0.96 }
local HOVER = { 0.78, 0.59, 0.20, 1 }

local ANCHOR_X = { LEFT = 0, TOPLEFT = 0, BOTTOMLEFT = 0, CENTER = 0.5, TOP = 0.5, BOTTOM = 0.5,
    RIGHT = 1, TOPRIGHT = 1, BOTTOMRIGHT = 1 }
local ANCHOR_Y = { BOTTOM = 0, BOTTOMLEFT = 0, BOTTOMRIGHT = 0, CENTER = 0.5, LEFT = 0.5, RIGHT = 0.5,
    TOP = 1, TOPLEFT = 1, TOPRIGHT = 1 }

-- Normalize movement to a fixed top-left corner. The old handle was centered
-- above the bar; migration uses the first complete grid layout.
function Handle.SavePosition(parent, migrate)
    local point, _, relativePoint, x, y = parent:GetPoint()
    if not ANCHOR_X[point] then return false end
    local width, height = parent:GetWidth(), parent:GetHeight()
    x = x - ANCHOR_X[point] * width + (migrate and width / 2 or 0)
    y = y + (1 - ANCHOR_Y[point]) * height
    parent:ClearAllPoints()
    parent:SetPoint("TOPLEFT", UIParent, relativePoint, x, y)
    ns.db.palettePoint = { "TOPLEFT", relativePoint, x, y }
    ns.db.paletteAnchorVersion = 1
    return true
end

function Handle:Anchor(parent)
    if ns.IsCombatLocked() then return end
    if not self.SavePosition(parent, ns.db.paletteAnchorVersion ~= 1) then return false end
    -- Screen clamping a changing-size bar can move its fixed corner. The
    -- handle remains the drag reference; the grid grows right and down.
    parent:SetClampedToScreen(false)
    return true
end

-- Both the live bar and the settings preview carry a handle, and both write
-- ns.db.palettePoint, so dragging either one moves the other. The frames stay
-- separate: the preview must never share a frame with the bar, whose children
-- are secure.
function Handle.Attach(parent, name, opts)
    local frame = CreateFrame("Button", name, parent, "BackdropTemplate")
    frame:SetSize(12, 10)
    frame:SetFrameLevel(parent:GetFrameLevel() + 10)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("RightButtonUp")
    frame:EnableMouse(true)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(unpack(IDLE))
    frame:SetBackdropBorderColor(0.08, 0.06, 0.02, 1)
    local dots = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    dots:SetPoint("CENTER", 0, 1); dots:SetText(":")
    frame:SetScript("OnDragStart", function()
        if not ns.IsCombatLocked() then parent:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function()
        if ns.IsCombatLocked() then return end
        parent:StopMovingOrSizing()
        Handle.SavePosition(parent, false)
        if opts.onMoved then opts.onMoved() end
    end)
    frame:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then ns.HC.Settings:Toggle() end
    end)
    frame:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(HOVER))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(opts.title or "Buffsmith")
        GameTooltip:AddLine(opts.dragHint or "Drag: move the bar", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Right-click: open settings", 0.85, 0.85, 0.85)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(IDLE))
        GameTooltip:Hide()
    end)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 0, 2)
    return frame
end

function Handle:Create(parent)
    if self.frame then return self.frame end
    self.frame = Handle.Attach(parent, "BuffsmithHandle", {
        title = "Buffsmith",
        dragHint = "Drag: move the bar",
        onMoved = function()
            if ns.Preview then ns.Preview:ApplyPosition() end
        end,
    })
    self:Update()
    return self.frame
end

function Handle:Update()
    if not self.frame then return end
    self.frame:SetShown(ns.db.showHandle == true and not ns.IsCombatLocked())
end

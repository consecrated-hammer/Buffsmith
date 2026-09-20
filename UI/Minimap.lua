local addonName, ns = ...

ns.Minimap = {}
local MinimapButton = ns.Minimap
local ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

function MinimapButton:Create()
    if self.button then return self.button end
    local button = CreateFrame("Button", "BuffsmithMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:GetHighlightTexture():SetBlendMode("ADD")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetAllPoints()
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 5, -5); icon:SetPoint("BOTTOMRIGHT", -5, 5)
    icon:SetTexture(ICON)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54); border:SetPoint("TOPLEFT")

    local function radius()
        local diameter = math.min(Minimap:GetWidth() or 0, Minimap:GetHeight() or 0)
        if diameter <= 0 then return 80 end
        return diameter / 2 + button:GetWidth() / 2 - 10
    end
    local function place(angle)
        local radians = math.rad(angle or 225)
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius(), math.sin(radians) * radius())
    end
    local atan2 = math.atan2 or math.atan
    local function follow()
        local scale = Minimap:GetEffectiveScale()
        local cursorX, cursorY = GetCursorPosition()
        local centerX, centerY = Minimap:GetCenter()
        if not centerX or not centerY then return end
        local angle = math.deg(atan2(cursorY / scale - centerY, cursorX / scale - centerX))
        ns.db.minimapAngle = angle
        place(angle)
    end

    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function()
        if button.dragged then button.dragged = nil; return end
        ns.Options:Toggle()
    end)
    button:SetScript("OnDragStart", function() button:SetScript("OnUpdate", follow) end)
    button:SetScript("OnDragStop", function()
        button:SetScript("OnUpdate", nil)
        button.dragged = true
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Buffsmith")
        GameTooltip:AddLine("Click: open settings", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Drag: move this icon", 0.85, 0.85, 0.85)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Minimap:HookScript("OnSizeChanged", function() place(ns.db.minimapAngle) end)
    self.button, self.place = button, place
    place(ns.db.minimapAngle)
    return button
end

function MinimapButton:Update()
    if not self.button then return end
    if ns.db.showMinimap and not ns.IsCombatLocked() then self.button:Show() else self.button:Hide() end
    if self.place then self.place(ns.db.minimapAngle) end
end

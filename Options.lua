local addonName, ns = ...
local Options = ns.Options

function Options:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "BuffsmithOptionsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(760, 540); frame:SetFrameStrata("DIALOG"); frame:SetToplevel(true)
    frame:SetMovable(true); frame:SetClampedToScreen(true); frame:EnableMouse(true)
    Options.Surface(frame, Options.theme.outer, Options.theme.edge)
    local saved = ns.db.settingsPoint
    frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])

    -- The title bar is the drag handle, and the saved spot survives reloads, so
    -- the window can be parked beside the bar while the preview is on screen.
    local titleBar = CreateFrame("Button", nil, frame)
    titleBar:SetPoint("TOPLEFT", 8, -6); titleBar:SetPoint("TOPRIGHT", -38, -6); titleBar:SetHeight(36)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        ns.db.settingsPoint = { point, relativePoint, x, y }
    end)
    local icon = titleBar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26); icon:SetPoint("LEFT", 8, 0); icon:SetTexture(Options.ICON)
    local title = titleBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0); title:SetText("Buffsmith"); title:SetTextColor(unpack(Options.theme.accent))
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5); close:SetScript("OnClick", function() frame:Hide() end)
    local version = titleBar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("RIGHT", close, "LEFT", -8, 0); version:SetText(tostring(ns.VERSION or ""))
    version:SetTextColor(unpack(Options.theme.muted))
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(unpack(Options.theme.edge))
    rule:SetPoint("TOPLEFT", 1, -42); rule:SetPoint("TOPRIGHT", -1, -42); rule:SetHeight(1)

    local rail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    rail:SetPoint("TOPLEFT", 1, -43); rail:SetPoint("BOTTOMLEFT", 1, 1); rail:SetWidth(176); Options.Surface(rail, Options.theme.rail, Options.theme.edge)
    local pages = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    pages:SetPoint("TOPLEFT", rail, "TOPRIGHT", 1, 0); pages:SetPoint("BOTTOMRIGHT", -1, 1); Options.Surface(pages, Options.theme.content, Options.theme.edge)
    self.pages, self.nav = {}, {}
    for index, spec in ipairs(self.pageSpecs) do
        local nav = Options.Button(rail, 154, spec.label); nav:SetPoint("TOPLEFT", 11, -14 - (index - 1) * 34)
        local page = CreateFrame("Frame", nil, pages); page:SetAllPoints(); page:Hide(); Options.BuildPage(spec.id, page)
        self.pages[spec.id], self.nav[spec.id] = page, nav
        nav:SetScript("OnClick", function() self:ShowPage(spec.id) end)
    end
    -- The preview lives in the rail rather than on a page: the player is
    -- usually changing size or orientation somewhere else when they want to
    -- see where the bar lands.
    local preview = Options.Button(rail, 154, "Preview on screen")
    preview:SetPoint("BOTTOMLEFT", 11, 14)
    preview:SetScript("OnClick", function()
        ns.Preview:Toggle()
        self:RefreshPreviewToggle()
    end)
    self.previewToggle = preview

    frame:SetScript("OnHide", function()
        Options.CloseDropdown()
        ns.Preview:Hide()
        self:RefreshPreviewToggle()
    end)
    tinsert(UISpecialFrames, "BuffsmithOptionsFrame")

    self.frame = frame; self:ShowPage("overview"); frame:Hide()
    return frame
end

function Options:RefreshPreviewToggle()
    if not self.previewToggle then return end
    local active = ns.Preview:IsShown()
    self.previewToggle:SetBackdropBorderColor(unpack(active and Options.theme.selected or Options.theme.edge))
    self.previewToggle.Text:SetText(active and "Hide preview" or "Preview on screen")
end

function Options:ShowPage(id)
    for key, page in pairs(self.pages) do
        page:SetShown(key == id)
        if key == id and page.buffsmithRefresh then page.buffsmithRefresh() end
        local nav = self.nav[key]
        nav:SetBackdropColor(unpack(key == id and Options.theme.raised or Options.theme.rail))
        nav:SetBackdropBorderColor(unpack(key == id and Options.theme.selected or Options.theme.edge))
    end
end

function Options:Toggle()
    if ns.IsCombatLocked() then return end
    local frame = self:Create(); frame:SetShown(not frame:IsShown()); if frame:IsShown() then frame:Raise() end
end

Options.Refresh = function() ns.RefreshAll() end

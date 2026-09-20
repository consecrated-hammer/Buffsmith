local addonName, ns = ...
local Options = ns.Options

function Options:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "BuffsmithOptionsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(760, 500); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG"); frame:SetToplevel(true)
    Options.Surface(frame, Options.theme.outer, Options.theme.edge)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -3, -3); close:SetScript("OnClick", function() frame:Hide() end)
    local rail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    rail:SetPoint("TOPLEFT", 1, -1); rail:SetPoint("BOTTOMLEFT", 1, 1); rail:SetWidth(176); Options.Surface(rail, Options.theme.rail, Options.theme.edge)
    local title = rail:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 18, -20); title:SetText("Buffsmith"); title:SetTextColor(unpack(Options.theme.accent))
    local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("TOPRIGHT", close, "TOPLEFT", -8, 0); version:SetText(tostring(ns.VERSION or ""))
    version:SetTextColor(unpack(Options.theme.muted))
    local pages = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    pages:SetPoint("TOPLEFT", rail, "TOPRIGHT", 1, 0); pages:SetPoint("BOTTOMRIGHT", -1, 1); Options.Surface(pages, Options.theme.content, Options.theme.edge)
    self.pages, self.nav = {}, {}
    for index, spec in ipairs(self.pageSpecs) do
        local nav = Options.Button(rail, 154, spec.label); nav:SetPoint("TOPLEFT", 11, -58 - (index - 1) * 34)
        local page = CreateFrame("Frame", nil, pages); page:SetAllPoints(); page:Hide(); Options.BuildPage(spec.id, page)
        self.pages[spec.id], self.nav[spec.id] = page, nav
        nav:SetScript("OnClick", function() self:ShowPage(spec.id) end)
    end
    self.frame = frame; self:ShowPage("overview"); frame:Hide()
    return frame
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

Options.Refresh = function() if ns.Palette then ns.Palette:Refresh() end end

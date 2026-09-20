local addonName, ns = ...
ns.Options = ns.Options or {}
local Options = ns.Options

Options.theme = {
    outer = { 0.043, 0.051, 0.063, 0.98 }, rail = { 0.071, 0.082, 0.102, 1 }, content = { 0.086, 0.098, 0.118, 1 },
    raised = { 0.110, 0.125, 0.153, 1 }, edge = { 0.169, 0.192, 0.227, 1 }, selected = { 0.247, 0.604, 0.925, 1 },
    accent = { 0.298, 0.604, 0.478, 1 }, muted = { 0.553, 0.584, 0.639, 1 },
}
function Options.Surface(frame, colour, edge)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(unpack(colour)); frame:SetBackdropBorderColor(unpack(edge))
end
function Options.Button(parent, width, text, primary)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 160, 25); Options.Surface(button, Options.theme.raised, primary and Options.theme.accent or Options.theme.edge)
    button.Text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); button.Text:SetAllPoints(); button.Text:SetJustifyH("CENTER"); button.Text:SetText(text or "")
    return button
end
function Options.Check(parent, y, label, get, set, hint)
    local row = CreateFrame("Button", nil, parent); row:SetSize(500, 28); row:SetPoint("TOPLEFT", 18, y)
    local box = CreateFrame("Frame", nil, row, "BackdropTemplate"); box:SetSize(18, 18); box:SetPoint("LEFT", 0, 0); Options.Surface(box, Options.theme.rail, Options.theme.edge)
    box.mark = box:CreateTexture(nil, "ARTWORK"); box.mark:SetPoint("TOPLEFT", 3, -3); box.mark:SetPoint("BOTTOMRIGHT", -3, 3); box.mark:SetColorTexture(unpack(Options.theme.selected))
    local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); text:SetPoint("LEFT", box, "RIGHT", 9, 0); text:SetText(label)
    local function refresh() local checked = get() == true; box.mark:SetShown(checked); box:SetBackdropBorderColor(unpack(checked and Options.theme.selected or Options.theme.edge)) end
    row:SetScript("OnClick", function() set(not get()); refresh(); if Options.Refresh then Options.Refresh() end end)
    row:SetScript("OnEnter", function() if hint then GameTooltip:SetOwner(row, "ANCHOR_CURSOR"); GameTooltip:SetText(label, unpack(Options.theme.accent)); GameTooltip:AddLine(hint, 1, 1, 1, true); GameTooltip:Show() end end)
    row:SetScript("OnLeave", function() if GameTooltip:IsOwned(row) then GameTooltip:Hide() end end); refresh(); return refresh
end
function Options.Slider(parent, y, label, minimum, maximum, step, get, set)
    local value = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetPoint("TOPLEFT", 18, y); value:SetText(label)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 18, y - 25); slider:SetWidth(270); slider:SetMinMaxValues(minimum, maximum); slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    local amount = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    amount:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    local changing = false
    slider:SetScript("OnValueChanged", function(_, number)
        if changing then return end
        number = math.floor(number / step + 0.5) * step
        set(number); amount:SetText(tostring(number) .. " px")
        if Options.Refresh then Options.Refresh() end
    end)
    local function refresh()
        changing = true; slider:SetValue(get()); changing = false; amount:SetText(tostring(get()) .. " px")
    end
    refresh()
    return refresh
end
function Options.PercentSlider(parent, y, label, get, set)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 18, y); title:SetText(label)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 18, y - 25); slider:SetWidth(270); slider:SetMinMaxValues(0, 50); slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    local amount = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    amount:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    local changing = false
    slider:SetScript("OnValueChanged", function(_, number)
        if changing then return end
        number = math.floor(number + 0.5)
        set(number); amount:SetText(tostring(number) .. "%")
        if Options.Refresh then Options.Refresh() end
    end)
    local function refresh()
        changing = true; slider:SetValue(get()); changing = false; amount:SetText(tostring(get()) .. "%")
    end
    refresh()
    return refresh
end
function Options.Scroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0); scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(530); content:SetHeight(480)
    scroll:SetScrollChild(content)
    return content
end
function Options.Header(parent, title, subtitle)
    local heading = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"); heading:SetPoint("TOPLEFT", 18, -18); heading:SetText(title); heading:SetTextColor(unpack(Options.theme.accent))
    if subtitle then local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); note:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6); note:SetWidth(500); note:SetJustifyH("LEFT"); note:SetText(subtitle); note:SetTextColor(unpack(Options.theme.muted)) end
end

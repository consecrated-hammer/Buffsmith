local addonName, ns = ...
ns.Options = ns.Options or {}
local Options = ns.Options

Options.theme = {
    outer = { 0.043, 0.051, 0.063, 0.98 }, rail = { 0.071, 0.082, 0.102, 1 }, content = { 0.086, 0.098, 0.118, 1 },
    raised = { 0.110, 0.125, 0.153, 1 }, edge = { 0.169, 0.192, 0.227, 1 }, selected = { 0.247, 0.604, 0.925, 1 },
    accent = { 0.298, 0.604, 0.478, 1 }, muted = { 0.553, 0.584, 0.639, 1 },
}

-- Placeholder until the real artwork lands; both TOCs' IconTexture is still a
-- question mark for the same reason.
Options.ICON = "Interface\\Icons\\Trade_BlackSmithing"

-- Every control returns the y its successor should use, so a page reads as a
-- chain instead of a column of hand-counted offsets. Mixing the two is what
-- left the shipped Consumables page overlapping its own sub-text.
Options.LEFT = 18
local ROW = 34
local BLOCK = 58

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

function Options.Hint(frame, title, hint)
    if not hint then return end
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(title, unpack(Options.theme.accent))
        GameTooltip:AddLine(hint, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
end

function Options.Text(parent, value, y, width)
    local copy = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    copy:SetPoint("TOPLEFT", Options.LEFT, y)
    copy:SetWidth(width or 490); copy:SetJustifyH("LEFT"); copy:SetText(value)
    return copy, y - math.max(24, copy:GetStringHeight() + 14)
end

function Options.SectionLabel(parent, value, y)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", Options.LEFT, y); label:SetText(value)
    return label, y - 24
end

function Options.Check(parent, y, label, get, set, hint)
    local row = CreateFrame("Button", nil, parent); row:SetSize(500, 28); row:SetPoint("TOPLEFT", Options.LEFT, y)
    local box = CreateFrame("Frame", nil, row, "BackdropTemplate"); box:SetSize(18, 18); box:SetPoint("LEFT", 0, 0); Options.Surface(box, Options.theme.rail, Options.theme.edge)
    box.mark = box:CreateTexture(nil, "ARTWORK"); box.mark:SetPoint("TOPLEFT", 3, -3); box.mark:SetPoint("BOTTOMRIGHT", -3, 3); box.mark:SetColorTexture(unpack(Options.theme.selected))
    local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); text:SetPoint("LEFT", box, "RIGHT", 9, 0); text:SetText(label)
    local function refresh() local checked = get() == true; box.mark:SetShown(checked); box:SetBackdropBorderColor(unpack(checked and Options.theme.selected or Options.theme.edge)) end
    row:SetScript("OnClick", function() set(not get()); refresh(); if Options.Refresh then Options.Refresh() end end)
    Options.Hint(row, label, hint)
    refresh()
    return refresh, y - ROW
end

local function slider(parent, y, label, minimum, maximum, step, get, set, suffix)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", Options.LEFT, y); title:SetText(label)
    local bar = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    bar:SetPoint("TOPLEFT", Options.LEFT, y - 25); bar:SetWidth(270)
    bar:SetMinMaxValues(minimum, maximum); bar:SetValueStep(step); bar:SetObeyStepOnDrag(true)
    if bar.Low then bar.Low:SetText("") end
    if bar.High then bar.High:SetText("") end
    if bar.Text then bar.Text:SetText("") end
    local amount = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    amount:SetPoint("LEFT", bar, "RIGHT", 10, 0)
    local changing = false
    bar:SetScript("OnValueChanged", function(_, number)
        if changing then return end
        number = math.floor(number / step + 0.5) * step
        set(number); amount:SetText(tostring(number) .. suffix)
        if Options.Refresh then Options.Refresh() end
    end)
    local function refresh()
        changing = true; bar:SetValue(get()); changing = false; amount:SetText(tostring(get()) .. suffix)
    end
    refresh()
    return refresh, y - BLOCK
end

function Options.Slider(parent, y, label, minimum, maximum, step, get, set, suffix)
    return slider(parent, y, label, minimum, maximum, step, get, set, suffix or " px")
end

function Options.PercentSlider(parent, y, label, get, set)
    return slider(parent, y, label, 0, 50, 1, get, set, "%")
end

-- One popup serves every dropdown, so opening one closes the last and no
-- control can leave a list stranded over the page.
local function shared()
    if Options.popup then return Options.popup, Options.popupCatcher end
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(1)
    catcher:Hide()
    catcher:SetScript("OnClick", function() Options.CloseDropdown() end)

    local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetFrameLevel(20)
    Options.Surface(list, Options.theme.raised, Options.theme.selected)
    list:Hide()
    list.rows = {}
    Options.popup, Options.popupCatcher = list, catcher
    return list, catcher
end

function Options.CloseDropdown()
    if not Options.popup then return end
    Options.popup:Hide()
    Options.popupCatcher:Hide()
    Options.popupOwner = nil
end

local function row(list, index)
    if list.rows[index] then return list.rows[index] end
    local entry = CreateFrame("Button", nil, list)
    entry:SetSize(1, 22)
    local box = CreateFrame("Frame", nil, entry, "BackdropTemplate")
    box:SetSize(14, 14); box:SetPoint("LEFT", 8, 0)
    Options.Surface(box, Options.theme.rail, Options.theme.edge)
    box.mark = box:CreateTexture(nil, "ARTWORK")
    box.mark:SetPoint("TOPLEFT", 3, -3); box.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    box.mark:SetColorTexture(unpack(Options.theme.selected))
    entry.box = box
    entry.text = entry:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    entry.text:SetPoint("LEFT", box, "RIGHT", 8, 0)
    entry.text:SetJustifyH("LEFT")
    list.rows[index] = entry
    return entry
end

-- items: { label, get, set, radio = <exclusive>, heading = <label only> }
-- A radio choice closes the list; a tick keeps it open so several can be set.
function Options.Dropdown(parent, y, label, spec)
    local width = spec.width or 300
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", Options.LEFT, y); title:SetText(label)

    local button = Options.Button(parent, width, "")
    button:SetPoint("TOPLEFT", Options.LEFT, y - 22)
    button.Text:SetJustifyH("LEFT")
    button.Text:ClearAllPoints()
    button.Text:SetPoint("LEFT", 10, 0)
    button.Text:SetPoint("RIGHT", -22, 0)
    local arrow = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", -8, 0); arrow:SetText("v"); arrow:SetTextColor(unpack(Options.theme.muted))
    Options.Hint(button, label, spec.hint)

    local function refresh()
        button.Text:SetText(spec.summary())
    end

    local function populate()
        local list, catcher = shared()
        for _, entry in ipairs(list.rows) do entry:Hide() end
        local height = 8
        for index, item in ipairs(spec.items) do
            local entry = row(list, index)
            entry:SetWidth(width)
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", 0, -height + 4)
            entry.text:SetText(item.label)
            if item.heading then
                entry.box:Hide()
                entry.text:ClearAllPoints()
                entry.text:SetPoint("LEFT", 10, 0)
                entry.text:SetTextColor(unpack(Options.theme.muted))
                entry:SetScript("OnClick", nil)
                entry:EnableMouse(false)
            else
                entry.box:Show()
                entry.text:ClearAllPoints()
                entry.text:SetPoint("LEFT", entry.box, "RIGHT", 8, 0)
                entry.text:SetTextColor(1, 1, 1)
                entry:EnableMouse(true)
                local checked = item.get() == true
                entry.box.mark:SetShown(checked)
                entry.box:SetBackdropBorderColor(unpack(checked and Options.theme.selected or Options.theme.edge))
                entry:SetScript("OnClick", function()
                    item.set(not item.get())
                    refresh()
                    if Options.Refresh then Options.Refresh() end
                    if item.radio then Options.CloseDropdown() else populate() end
                end)
            end
            entry:Show()
            height = height + 22
        end
        list:SetSize(width, height + 4)
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
        list:Show()
        catcher:Show()
    end

    button:SetScript("OnClick", function()
        if Options.popupOwner == button then Options.CloseDropdown(); return end
        Options.CloseDropdown()
        Options.popupOwner = button
        populate()
    end)

    refresh()
    return refresh, y - BLOCK
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
    local heading = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", Options.LEFT, -18); heading:SetText(title); heading:SetTextColor(unpack(Options.theme.accent))
    if not subtitle then return -58 end
    local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6); note:SetWidth(500); note:SetJustifyH("LEFT")
    note:SetText(subtitle); note:SetTextColor(unpack(Options.theme.muted))
    return -58 - math.max(14, note:GetStringHeight())
end

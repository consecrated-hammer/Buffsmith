local addonName, ns = ...

ns.Bindings = { index = 1 }
local Bindings = ns.Bindings

local commands = {
    trigger = "CLICK BuffsmithBindingButton:LeftButton",
}

function Bindings:Command(id)
    return commands[id]
end

function Bindings:Label(id)
    local command = self:Command(id)
    local first, second = GetBindingKey and GetBindingKey(command)
    local function readable(key)
        return key and (GetBindingText and GetBindingText(key, "KEY_") or key) or nil
    end
    if first and second then return readable(first) .. ", " .. readable(second) end
    return readable(first) or "Unbound"
end

function Bindings:Set(id, key)
    if ns.IsCombatLocked() then return false, "Bindings cannot change during combat." end
    local command = self:Command(id)
    if not command or not key or key == "" then return false, "Choose a valid key." end
    local old = GetBindingKey and GetBindingKey(command)
    if not SetBinding or not SetBinding(key, command) then return false, "That key could not be assigned." end
    if old and old ~= key then SetBinding(old, nil) end
    if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
    return true, key
end

function Bindings:Clear(id)
    if ns.IsCombatLocked() then return false, "Bindings cannot change during combat." end
    local command = self:Command(id)
    local first, second = GetBindingKey and GetBindingKey(command)
    if first then SetBinding(first, nil) end
    if second then SetBinding(second, nil) end
    if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
    return true
end

local function normalizedKey(raw)
    if raw == "LeftButton" then raw = "BUTTON1" end
    if raw == "RightButton" then raw = "BUTTON2" end
    if raw == "MiddleButton" then raw = "BUTTON3" end
    if GetConvertedKeyOrButton then raw = GetConvertedKeyOrButton(raw) end
    if not raw or raw == "" or (IsKeyPressIgnoredForBinding and IsKeyPressIgnoredForBinding(raw)) then return nil end
    if CreateKeyChordStringUsingMetaKeyState then return CreateKeyChordStringUsingMetaKeyState(raw) end
    local parts = {}
    if IsControlKeyDown and IsControlKeyDown() then parts[#parts + 1] = "CTRL" end
    if IsAltKeyDown and IsAltKeyDown() then parts[#parts + 1] = "ALT" end
    if IsShiftKeyDown and IsShiftKeyDown() then parts[#parts + 1] = "SHIFT" end
    parts[#parts + 1] = raw
    return table.concat(parts, "-")
end

function Bindings:CreateCapture()
    if self.capture then return self.capture end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetAllPoints(UIParent); frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:EnableKeyboard(true); frame:EnableMouse(true); frame:EnableMouseWheel(true)
    if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(false) end
    if frame.SetPropagateMouseClicks then frame:SetPropagateMouseClicks(false) end
    local function receive(raw)
        if raw == "ESCAPE" then
            frame:Hide()
            if Bindings.captureCallback then Bindings.captureCallback(nil, "Cancelled.") end
            Bindings.captureCallback = nil
            return
        end
        local key = normalizedKey(raw)
        if not key then return end
        frame:Hide()
        if Bindings.captureCallback then Bindings.captureCallback(key) end
        Bindings.captureCallback = nil
    end
    frame:SetScript("OnKeyDown", function(_, key) receive(key) end)
    frame:SetScript("OnMouseDown", function(_, buttonName) receive(buttonName) end)
    frame:SetScript("OnMouseWheel", function(_, delta) receive(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
    frame:Hide(); self.capture = frame
    return frame
end

function Bindings:Capture(callback)
    if ns.IsCombatLocked() then callback(nil, "Bindings cannot change during combat."); return end
    self.captureCallback = callback
    self:CreateCapture():Show()
end

local function button(name, direction)
    local frame = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    frame:SetSize(1, 1)
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -20, -20)
    frame:SetAttribute("useOnKeyDown", false)
    frame:RegisterForClicks("LeftButtonUp")
    frame:Show()
    frame:SetScript("PreClick", function(self)
        local entry = self.buffsmithEntry
        if entry and entry.kind == "item" then ns.Inventory:BeginConsumableUse(entry) end
    end)
    frame:SetScript("PostClick", function(self)
        if ns.IsCombatLocked() then return end
        local entry = self.buffsmithEntry
        if entry and entry.kind == "item" then
            ns.Actions:Remember(entry.category, entry.itemID)
            ns.Inventory:FinishConsumableUse()
        end
        Bindings.index = Bindings.index + direction
        C_Timer.After(0, function() Bindings:Prepare() end)
    end)
    return frame
end

function Bindings:Create()
    if self.trigger then return end
    self.trigger = button("BuffsmithBindingButton", 1)
end

function Bindings:Prepare()
    if ns.IsCombatLocked() then return end
    self:Create()
    local entries = ns.Actions:BindingEntries()
    self.lastCount = #entries
    if #entries == 0 then
        self.index = 1
        ns.Actions:Configure(self.trigger, { kind = "none" })
        return
    end
    self.index = ((self.index - 1) % #entries) + 1
    ns.Actions:Configure(self.trigger, entries[self.index])
end

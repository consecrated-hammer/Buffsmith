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
    local first, second
    if GetBindingKey then first, second = GetBindingKey(command) end
    local function readable(key)
        return key and (GetBindingText and GetBindingText(key, "KEY_") or key) or nil
    end
    if first and second then return readable(first) .. ", " .. readable(second) end
    return readable(first) or "Unbound"
end

local function wheelKey(key)
    return type(key) == "string" and (key == "MOUSEWHEELUP" or key == "MOUSEWHEELDOWN"
        or key:match("%-MOUSEWHEELUP$") or key:match("%-MOUSEWHEELDOWN$"))
end

local function bindingAction(key)
    return GetBindingAction and GetBindingAction(key, false)
end

local function bindingProfile()
    local set = GetCurrentBindingSet and GetCurrentBindingSet()
    if set == 1 then return "account" end
    if set == 2 then
        local guid = UnitGUID and UnitGUID("player")
        if ns.Plain then guid = ns.Plain(guid) end
        if type(guid) == "string" and guid ~= "" then return "character:" .. guid end
    end
end

function Bindings:WheelZoom()
    local profile = bindingProfile()
    local zoom = profile and type(ns.db.bindingZooms) == "table" and ns.db.bindingZooms[profile]
    if type(zoom) ~= "table" or not wheelKey(zoom.key)
        or (zoom.action ~= "CAMERAZOOMIN" and zoom.action ~= "CAMERAZOOMOUT")
        or bindingAction(zoom.key) ~= commands.trigger then return nil end
    return zoom
end

function Bindings:SyncZoom()
    if ns.IsCombatLocked() or not self.trigger then return end
    local zoom = self:WheelZoom()
    local signature = zoom and zoom.enabled and (zoom.key .. ":" .. zoom.action) or nil
    if signature == self.zoomOverride then return end
    if ClearOverrideBindings then ClearOverrideBindings(self.trigger) end
    self.zoomOverride = nil
    if signature and SetOverrideBindingClick then
        local frame = zoom.action == "CAMERAZOOMIN" and self.zoomIn or self.zoomOut
        SetOverrideBindingClick(self.trigger, false, zoom.key, frame:GetName(), "LeftButton")
        self.zoomOverride = signature
    end
end

function Bindings:SetWheelZoom(enabled)
    if ns.IsCombatLocked() then return false, "Bindings cannot change during combat." end
    local zoom = self:WheelZoom()
    if not zoom then return false, "Choose a mouse-wheel key already bound to camera zoom." end
    zoom.enabled = enabled == true
    self:SyncZoom()
    return true
end

local function changeBindings(changes)
    local changed = {}
    for _, change in ipairs(changes) do
        local before = bindingAction(change.key)
        if not SetBinding or not SetBinding(change.key, change.action) then
            -- Keep recovery metadata even if the client also refuses rollback.
            for index = #changed, 1, -1 do
                local previous = changed[index]
                SetBinding(previous.key, previous.action ~= "" and previous.action or nil)
            end
            return false, "Binding change failed. Camera recovery settings were kept; try again out of combat."
        end
        changed[#changed + 1] = { key = change.key, action = before }
    end
    return true
end

local function releaseKey(changes, key, zoom)
    if key and (not GetBindingAction or bindingAction(key) == commands.trigger) then
        changes[#changes + 1] = { key = key, action = zoom and key == zoom.key and zoom.action or nil }
    end
end

function Bindings:Set(id, key)
    if ns.IsCombatLocked() then return false, "Bindings cannot change during combat." end
    local command = self:Command(id)
    if not command or not key or key == "" then return false, "Choose a valid key." end
    local old = GetBindingKey and GetBindingKey(command)
    local profile = bindingProfile()
    local oldZoom = self:WheelZoom()
    local previous = wheelKey(key) and bindingAction(key)
    local zoom
    if previous == "CAMERAZOOMIN" or previous == "CAMERAZOOMOUT" then
        if not profile then return false, "Camera bindings are not ready yet. Try again after login." end
        zoom = { key = key, action = previous, enabled = false }
    elseif oldZoom and oldZoom.key == key then
        zoom = oldZoom
    end
    local changes = { { key = key, action = command } }
    if old and old ~= key then releaseKey(changes, old, oldZoom) end
    if oldZoom and oldZoom.key ~= key and oldZoom.key ~= old then releaseKey(changes, oldZoom.key, oldZoom) end
    local ok, message = changeBindings(changes)
    if not ok then self:SyncZoom(); return false, message end
    if profile then
        if type(ns.db.bindingZooms) ~= "table" then ns.db.bindingZooms = {} end
        ns.db.bindingZooms[profile] = zoom
    end
    self:SyncZoom()
    if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
    return true, key
end

function Bindings:Clear(id)
    if ns.IsCombatLocked() then return false, "Bindings cannot change during combat." end
    local command = self:Command(id)
    local first, second
    if GetBindingKey then first, second = GetBindingKey(command) end
    local zoom = self:WheelZoom()
    local changes = {}
    releaseKey(changes, first, zoom)
    releaseKey(changes, second, zoom)
    local ok, message = changeBindings(changes)
    if not ok then self:SyncZoom(); return false, message end
    local profile = bindingProfile()
    if profile and type(ns.db.bindingZooms) == "table" then ns.db.bindingZooms[profile] = nil end
    self:SyncZoom()
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

local function button(name, direction, zoomAction)
    local frame = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
    frame:SetSize(1, 1)
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -20, -20)
    frame:SetAttribute("useOnKeyDown", false)
    frame:RegisterForClicks("LeftButtonUp")
    frame:Show()
    frame:SetScript("PreClick", function(self)
        if zoomAction then
            local camera
            if zoomAction == "CAMERAZOOMIN" then camera = CameraZoomIn else camera = CameraZoomOut end
            if type(camera) == "function" then camera(1) end
        end
        local entry = self.buffsmithEntry
        self.buffsmithAttempt = nil
        self.buffsmithPress = ns.Readiness and ns.Readiness:Press(self, entry) or nil
        if self.buffsmithPress then
            self.buffsmithPress.order = Bindings.order
            if not self.buffsmithPress.allow then return end
            entry = self.buffsmithPress.entry
        end
        if entry and ns.Actions.eatingPaused then
            ns.Actions:ShowEatingNotice()
        elseif entry and entry.kind ~= "none" then
            self.buffsmithAttempt = ns.Actions:BeginAttempt(entry)
            if entry.kind == "item" then ns.Inventory:BeginConsumableUse(entry) end
        end
    end)
    frame:SetScript("PostClick", function(self)
        if ns.IsCombatLocked() or ns.Actions.eatingPaused then return end
        local result = self.buffsmithPress
        if result and not result.allow then return end
        local entry = result and result.entry or self.buffsmithEntry
        if not entry or entry.kind == "none" then return end
        if entry.kind == "item" then
            ns.Actions:RememberItem(entry)
            ns.Inventory:FinishConsumableUse()
        end
        local attempt = self.buffsmithAttempt
        if attempt then C_Timer.After(0.25, function() ns.Actions:ExpireAttempt(entry, attempt) end) end
        if result and result.ends then
            -- One attempt per native queue window, shared by all trigger keys.
            Bindings.candidate = result.key
            return
        end
        if result and result.order then
            Bindings.successors = {}
            local at = 1
            for index, key in ipairs(result.order) do if key == result.key then at = index; break end end
            for offset = 1, #result.order do
                Bindings.successors[#Bindings.successors + 1] = result.order[((at - 1 + direction * offset) % #result.order) + 1]
            end
            Bindings.candidate = nil
        else Bindings.index = Bindings.index + direction end
        C_Timer.After(0, function() Bindings:Prepare() end)
    end)
    return frame
end

function Bindings:Create()
    if self.trigger then return end
    self.trigger = button("BuffsmithBindingButton", 1)
    self.zoomIn = button("BuffsmithZoomInBindingButton", 1, "CAMERAZOOMIN")
    self.zoomOut = button("BuffsmithZoomOutBindingButton", 1, "CAMERAZOOMOUT")
    self:SyncZoom()
end

function Bindings:Prepare()
    if ns.IsCombatLocked() then return end
    self:Create()
    self:SyncZoom()
    local function configure(entry)
        for _, frame in ipairs({ self.trigger, self.zoomIn, self.zoomOut }) do ns.Actions:Configure(frame, entry) end
    end
    local entries = ns.Actions:BindingEntries()
    self.lastCount = #entries
    if #entries == 0 then
        self.index, self.candidate, self.successors, self.order = 1, nil, nil, nil
        configure({ kind = "none" })
        return
    end
    if ns.Readiness then
        local order, positions = {}, {}
        for index, entry in ipairs(entries) do
            order[index] = ns.Readiness:Key(entry)
            positions[order[index]] = index
        end
        local selected = self.candidate and positions[self.candidate]
        for _, key in ipairs(self.successors or {}) do
            if positions[key] then selected = positions[key]; break end
        end
        self.index = selected or ((self.index - 1) % #entries) + 1
        self.candidate, self.order, self.successors = order[self.index], order, nil
    else self.index = ((self.index - 1) % #entries) + 1 end
    configure(entries[self.index])
end

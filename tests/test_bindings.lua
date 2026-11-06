package.path = "./tests/hammercore/?.lua;" .. package.path
local wow = require("wow")
local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end
local COMMAND = "CLICK BuffsmithBindingButton:LeftButton"
local function fixture(saved)
    wow.Install()
    local state = { keys = {}, override = {}, set = 1, character = "Player-1-A", zoomIn = 0, zoomOut = 0, buffs = 0, combat = false }
    UnitGUID = function() return state.character end
    GetBindingAction = function(key) return state.keys[key] or "" end
    GetBindingKey = function(command)
        local keys = {}
        for key, action in pairs(state.keys) do if action == command then keys[#keys + 1] = key end end
        table.sort(keys)
        return keys[1], keys[2]
    end
    SetBinding = function(key, action)
        if state.fail or state.combat or (state.failKey == key) then return false end
        state.keys[key] = action
        return true
    end
    GetBindingText = function(key) return key end
    SaveBindings = function() end
    GetCurrentBindingSet = function() return state.set end
    ClearOverrideBindings = function(owner) state.override = {} end
    SetOverrideBindingClick = function(owner, priority, key, name) state.override[key] = name end
    CameraZoomIn = function(n) equal(n, 1, "standard zoom step"); state.zoomIn = state.zoomIn + 1 end
    CameraZoomOut = function(n) equal(n, 1, "standard zoom step"); state.zoomOut = state.zoomOut + 1 end
    C_Timer = { After = function() end }
    local ns = { db = saved or {}, IsCombatLocked = function() return state.combat end,
        Actions = { entries = { { kind = "spell", name = "Buff" } } }, Inventory = {} }
    function ns.Actions:BindingEntries() return self.entries end
    function ns.Actions:Configure(frame, entry) frame.buffsmithEntry = entry end
    function ns.Actions:BeginAttempt(entry) if entry.kind == "spell" then state.buffs = state.buffs + 1 end end
    function ns.Actions:ExpireAttempt() end
    function ns.Actions:ShowEatingNotice() end
    assert(loadfile("Features/Bindings.lua"))("Buffsmith", ns)
    ns.Bindings:Prepare()
    function state:press(key)
        local frame = self.override[key] and _G[self.override[key]] or (self.keys[key] == COMMAND and ns.Bindings.trigger)
        if frame then frame.scripts.PreClick(frame); frame.scripts.PostClick(frame) end
    end
    return ns, state
end

for _, key in ipairs({ "MOUSEWHEELUP", "MOUSEWHEELDOWN", "SHIFT-MOUSEWHEELDOWN" }) do
    for _, action in ipairs({ "CAMERAZOOMIN", "CAMERAZOOMOUT" }) do
        local ns, s = fixture()
        s.keys[key] = action
        equal(ns.Bindings:Set("trigger", key), true, "camera key can become Buffsmith trigger")
        equal(ns.Bindings:WheelZoom().action, action, "remember original action rather than infer wheel direction")
        equal(ns.Bindings:WheelZoom().enabled, false, "camera sharing starts off")
        s:press(key)
        equal(s.zoomIn + s.zoomOut, 0, "opt-in does not zoom before enabling")
        equal(ns.Bindings:SetWheelZoom(true), true, "sharing enables")
        s.keys.F = COMMAND
        s:press("F")
        equal(s.zoomIn + s.zoomOut, 0, "a second Buffsmith key never zooms")
        s:press(key)
        equal(s.zoomIn, action == "CAMERAZOOMIN" and 1 or 0, "original zoom-in behaviour preserved")
        equal(s.zoomOut, action == "CAMERAZOOMOUT" and 1 or 0, "original zoom-out behaviour preserved")
        equal(s.buffs, 3, "shared wheel also performs ordinary buff trigger")
        ns.Actions.entries = {}
        ns.Bindings:Prepare()
        s:press(key)
        equal(s.zoomIn + s.zoomOut, 2, "empty buff list still permits camera zoom")
        equal(s.buffs, 3, "empty trigger does not add a buff")
        ns.Actions.eatingPaused = true
        s:press(key)
        equal(s.zoomIn + s.zoomOut, 3, "meal pause still permits camera zoom")
        s.combat = true
        s:press(key)
        equal(s.zoomIn + s.zoomOut, 4, "camera still works in combat")
        equal(ns.Bindings:SetWheelZoom(false), false, "binding edits blocked in combat")
        s.combat = false
        equal(ns.Bindings:SetWheelZoom(false), true, "sharing disables")
        equal(s.override[key], nil, "disabling sharing removes camera override")
        ns.Bindings:Clear("trigger")
        equal(s.keys[key], action, "clearing restores captured camera binding")
        equal(s.keys.F, nil, "clear removes the second Buffsmith binding too")
        equal(ns.Bindings:WheelZoom(), nil, "clear hides camera option")
    end
end
for _, action in ipairs({ "", "JUMP", COMMAND }) do
    local ns, s = fixture()
    s.keys.MOUSEWHEELDOWN = action
    ns.Bindings:Set("trigger", "MOUSEWHEELDOWN")
    equal(ns.Bindings:WheelZoom(), nil, "no option without detected prior camera action")
end
local ns, s = fixture()
s.keys.F = "CAMERAZOOMOUT"
ns.Bindings:Set("trigger", "F")
equal(ns.Bindings:WheelZoom(), nil, "non-wheel camera key does not expose option")
ns, s = fixture()
s.keys.MOUSEWHEELDOWN = "CAMERAZOOMOUT"
ns.Bindings:Set("trigger", "MOUSEWHEELDOWN")
ns.Bindings:SetWheelZoom(true)
ns.Bindings:Set("trigger", "MOUSEWHEELDOWN")
equal(ns.Bindings:WheelZoom().enabled, true, "recapturing the same wheel retains preference")
s.fail = true
ns.Bindings:Set("trigger", "G")
equal(ns.Bindings:WheelZoom().enabled, true, "failed rebind preserves working camera state")
s.fail = false
ns.Bindings:Set("trigger", "G")
equal(s.keys.MOUSEWHEELDOWN, "CAMERAZOOMOUT", "replacing wheel key restores original camera binding")
equal(ns.Bindings:WheelZoom(), nil, "keyboard binding hides zoom option")
ns, s = fixture({ bindingZooms = { account = { key = "MOUSEWHEELDOWN", action = "CAMERAZOOMOUT", enabled = true } } })
s.keys.MOUSEWHEELDOWN = COMMAND
ns.Bindings:Prepare()
equal(s.override.MOUSEWHEELDOWN, "BuffsmithZoomOutBindingButton", "saved camera sharing restores after reload")
s.set = 2
ns.Bindings:SyncZoom()
equal(s.override.MOUSEWHEELDOWN, nil, "camera record cannot override a different binding profile")
s.set = 1
ns.Bindings:SyncZoom()
s.keys.MOUSEWHEELDOWN = "JUMP"
ns.Bindings:SyncZoom()
equal(s.override.MOUSEWHEELDOWN, nil, "external rebind removes override")
ns.Bindings:Clear("trigger")
equal(s.keys.MOUSEWHEELDOWN, "JUMP", "clear never overwrites an externally rebound action")
ns, s = fixture()
s.keys.MOUSEWHEELDOWN = "CAMERAZOOMOUT"
ns.Bindings:Set("trigger", "MOUSEWHEELDOWN")
ns.Bindings:SetWheelZoom(true)
s.failKey = "MOUSEWHEELDOWN"
equal(ns.Bindings:Clear("trigger"), false, "failed camera restoration reports failure")
equal(ns.Bindings:WheelZoom().action, "CAMERAZOOMOUT", "failed clear keeps recovery record")
equal(ns.Bindings:Set("trigger", "G"), false, "failed camera restoration during replacement reports failure")
equal(s.keys.G, nil, "failed replacement rolls back new binding")
equal(ns.Bindings:WheelZoom().enabled, true, "failed replacement retains sharing preference")
s.failKey = nil
ns.Bindings:Clear("trigger")
equal(s.keys.MOUSEWHEELDOWN, "CAMERAZOOMOUT", "restoration can be retried")
ns, s = fixture()
s.set = 2
s.keys.MOUSEWHEELDOWN = "CAMERAZOOMIN"
ns.Bindings:Set("trigger", "MOUSEWHEELDOWN")
ns.Bindings:SetWheelZoom(true)
s.character = "Player-1-B"
ns.Bindings:SyncZoom()
equal(ns.Bindings:WheelZoom(), nil, "other character does not inherit previous camera direction")
equal(s.override.MOUSEWHEELDOWN, nil, "other character has no inherited camera override")
s.character = "Player-1-A"
ns.Bindings:SyncZoom()
equal(ns.Bindings:WheelZoom().action, "CAMERAZOOMIN", "original character's camera record survives")
s, s = nil, nil
local unready, unreadyState = fixture()
unreadyState.set = nil
unreadyState.keys.MOUSEWHEELDOWN = "CAMERAZOOMOUT"
equal(unready.Bindings:Set("trigger", "MOUSEWHEELDOWN"), false, "unavailable binding profile cannot lose original camera action")
equal(unreadyState.keys.MOUSEWHEELDOWN, "CAMERAZOOMOUT", "unavailable profile leaves camera key unchanged")
io.write("binding camera tests passed\n")

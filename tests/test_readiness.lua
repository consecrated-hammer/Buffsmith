package.path = "./tests/hammercore/?.lua;" .. package.path
local wow = require("wow")
local function eq(a, b, label) assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local secret = {}
local function fixture()
    wow.Install()
    local s = { time = 100, pending = {}, casts = 0, zoom = 0, attempts = 0, remembered = 0, combat = false }
    GetTime = function() return s.time end
    UnitGUID = function() return "player-1" end
    UnitIsDeadOrGhost, UnitOnTaxi = function() return false end, function() return false end
    UnitCastingInfo, UnitChannelInfo = function() end, function() end
    GetCVar = function() return "400" end
    C_CVar, GetSpellCooldown, GetItemCooldown, C_Item = nil, nil, nil, nil
    C_Spell = { GetSpellCooldown = function() return s.cd or { startTime = 0, duration = 0, isEnabled = true } end }
    C_Timer = { After = function(delay, fn) s.pending[#s.pending + 1] = { delay, fn } end }
    CameraZoomIn, CameraZoomOut = function() s.zoom = s.zoom + 1 end, function() s.zoom = s.zoom + 1 end
    local ns = { db = {}, Plain = function(v) if v ~= secret then return v end end,
        IsSecret = function(v) return v == secret end, IsCombatLocked = function() return s.combat end,
        Actions = {}, Inventory = {} }
    local a = ns.Actions
    a.entries = { { kind = "spell", spellID = 1, name = "One", unitGUID = "player-1" },
        { kind = "spell", spellID = 2, name = "Two", unitGUID = "player-1" },
        { kind = "spell", spellID = 3, name = "Three", unitGUID = "player-1" } }
    function a:MealStatus() return s.meal or { active = false } end
    function a:CanBuffUnit() return not s.pvpBlocked end
    function a:IsRestedPaused() return s.rested end
    function a:BindingEntries() return self.entries end
    function a:Configure(b, entry)
        assert(not s.combat, "no protected configuration in combat")
        b.buffsmithEntry, b.buffsmithReadinessDisarmed = entry, nil
        b:SetAttribute("type1", entry.kind ~= "none" and not self.eatingPaused and entry.kind or nil)
        b:SetAttribute("spell1", entry.spellID)
    end
    function a:BeginAttempt() s.attempts = s.attempts + 1; return { number = s.attempts } end
    function a:ExpireAttempt(_, token) s.expired = token end
    function a:RememberItem() s.remembered = s.remembered + 1 end
    function ns.Inventory:BeginConsumableUse() s.startedItem = true end
    function ns.Inventory:FinishConsumableUse() s.finishedItem = true end
    assert(loadfile("Features/Readiness.lua"))("Buffsmith", ns)
    assert(loadfile("Features/Bindings.lua"))("Buffsmith", ns)
    ns.Bindings:Prepare()
    function s:press(frame)
        frame = frame or ns.Bindings.trigger
        frame.scripts.PreClick(frame)
        -- Model the actual secure action between the two scripts, not BeginAttempt.
        if frame:GetAttribute("type1") then self.casts = self.casts + 1 end
        frame.scripts.PostClick(frame)
    end
    function s:flush(delay)
        local pending = self.pending; self.pending = {}
        for _, timer in ipairs(pending) do if timer[1] == delay then timer[2]() else self.pending[#self.pending + 1] = timer end end
    end
    return ns, s
end
local ns, s = fixture()
s.cd = { startTime = 100, duration = 1.5, isEnabled = true, modRate = 2 }
s:press(ns.Bindings.zoomIn)
eq(s.casts, 0, "cooldown clears actual secure action")
eq(s.attempts, 0, "blocked input cannot open attribution window")
eq(s.zoom, 1, "blocked input keeps camera zoom")
eq(ns.Bindings.index, 1, "blocked input does not advance")
eq(ns.Readiness:Cooldown(ns.Actions.entries[1]).ends, 101.5, "rate does not change cooldown deadline")
s.time = 101.2
s:press()
eq(s.casts, 1, "one hardware input enters native queue window")
s:press(ns.Bindings.zoomOut)
eq(s.casts, 1, "spam cannot replace native queued attempt")
eq(s.zoom, 2, "latched input still zooms")
s.time = 101.6; s.cd = nil
s:flush(0)
eq(s.casts, 1, "timers never cast")
s:press()
eq(s.casts, 2, "later hardware input rearms")
ns.Actions.entries = { ns.Actions.entries[2], ns.Actions.entries[3] }
s:flush(0)
eq(ns.Bindings.trigger.buffsmithEntry.spellID, 2, "shrinking list selects original successor")

ns, s = fixture()
s.meal = { active = true, ends = 130 }
s:press()
eq(s.casts, 0, "meal starting after render still blocks")
eq(ns.Readiness:Status().ends, 130, "meal deadline for status")
s.meal = { active = false }; s:press()
eq(s.casts, 1, "meal stop rearms at next hardware input")
ns.Readiness.queueUntil = nil
UnitCastingInfo = function() return "Cast", nil, nil, 100000, 103000 end
s:press(); eq(s.casts, 1, "cast outside native queue window blocked")
s.time = 102.8
s:press(); eq(s.casts, 2, "cast inside native queue window allowed")
ns.Readiness.queueUntil = nil
UnitChannelInfo = function() return "Channel", nil, nil, 100000, 104000 end
s:press(); eq(s.casts, 2, "channel cannot be clipped")
UnitCastingInfo, UnitChannelInfo = function() end, function() end
GetCVar = function() return nil end
s.cd = { startTime = 100, duration = 20, isEnabled = true }
ns.Readiness.queueUntil = nil
s:press(); eq(s.casts, 3, "unknown queue configuration preserves native spell input")
GetCVar = function() return "400" end
s.cd = secret
s:press(); eq(s.casts, 4, "secret cooldown preserves native input")
s.cd = { startTime = secret, duration = 5, isEnabled = true }
eq(ns.Readiness:Cooldown(ns.Actions.entries[1]), nil, "unreadable fields have no invented timer")
C_Spell.GetSpellCooldown = function() error("unavailable") end
s:press(); eq(s.casts, 5, "API failure preserves native input")
C_Spell = nil; GetSpellCooldown = function() return 100, 10, 1 end
GetItemCooldown = function() return 100, 10, 1 end
s.time = 100
local item = { kind = "item", itemID = 9 }
eq(ns.Readiness:Check(item).allow, false, "legacy item cooldown blocks")
GetItemCooldown = nil
eq(ns.Readiness:Cooldown(item), nil, "missing item API never calls spell cooldown")
eq(ns.Readiness:Key({kind="item",itemID=9,targetSlot=16}) == ns.Readiness:Key({kind="item",itemID=9,targetSlot=17}), false, "weapon slots have distinct identities")
UnitGUID = function() return "replacement" end
s:press(); eq(s.casts, 5, "changed recipient never casts on replacement")
s.combat = true
local previous = ns.Bindings.trigger:GetAttribute("type1")
s:press(ns.Bindings.zoomIn)
eq(ns.Bindings.trigger:GetAttribute("type1"), previous, "combat leaves protected attributes alone")
eq(s.zoom, 1, "camera still works during combat")
-- Cooldown feedback is the icon sweep, with no separate last-cooldown text row.
ns, s = fixture()
ns.Readiness.lastEntry = ns.Actions.entries[1]
s.cd = { startTime = 100, duration = 30, isEnabled = true }
eq(ns.Readiness:Status(), nil, "cooldown alone has no status text")

-- A native-window attempt expires and prepares again without an unrelated event.
ns, s = fixture()
s.cd = { startTime = 100, duration = 0.25, isEnabled = true }
s:press()
eq(ns.Readiness.queueUntil, 100.25, "bounded queue latch")
eq(ns.Readiness:Status(), nil, "short native queue window cannot flash a status row")
s.time = 100.3; s.cd = nil
s:flush(0.25)
eq(ns.Readiness.queueUntil, nil, "queue timer releases ownership")
assert(s.expired, "queue path schedules attribution expiry")
eq(s.casts, 1, "queue release never invokes a secure action")
s:press(); eq(s.casts, 2, "queue failure can retry with next hardware input")

-- A render-time meal disarm must rearm on the first later hardware press.
ns, s = fixture()
ns.Actions.eatingPaused = true
ns.Bindings:Prepare()
eq(ns.Bindings.trigger:GetAttribute("type1"), nil, "meal-rendered button is unarmed")
s:press()
eq(s.casts, 1, "first press after a rendered meal rearms")
GetCVar = function() return "400" end
s.cd = { startTime = 100, duration = 30, isEnabled = false }
s:press(); eq(s.casts, 2, "on-hold state is not proof of an unusable action")
s.cd = nil
UnitGUID = function() return nil end
s:press(); eq(s.casts, 3, "unreadable identity preserves native input")
UnitChannelInfo = nil
UnitCastingInfo = function() return "Cast", nil, nil, 100000, 100200 end
ns.Readiness.queueUntil = nil
s:press(); eq(s.casts, 4, "absent channel API does not classify normal cast as channel")
ns.Actions.eatingPaused = true
s.meal = { active = false, available = false }
ns.Readiness.queueUntil = nil
s:press(); eq(s.casts, 4, "failed aura read preserves observed meal pause")

io.write("readiness tests passed\n")

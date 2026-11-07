package.path = "./tests/hammercore/?.lua;" .. package.path
local wow = require("wow")
wow.Install()
local ns = { db = {}, IsCombatLocked = function() return false end }
assert(loadfile("UI/Handle.lua"))("Buffsmith", ns)
local function eq(a, b, label) assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local parent = CreateFrame("Frame", nil, UIParent)
parent:SetSize(100, 100)
parent:SetPoint("CENTER", UIParent, "CENTER", 100, 50)
ns.Handle:Anchor(parent)
eq(ns.db.palettePoint[1], "TOPLEFT", "normalize to fixed corner")
eq(ns.db.palettePoint[3], 100, "migration retains old handle horizontal position")
eq(ns.db.palettePoint[4], 100, "migration retains old handle vertical position")
local handle = ns.Handle.Attach(parent, nil, {})
local point, relative, anchor = handle:GetPoint()
eq(point, "BOTTOMLEFT", "handle grows away from fixed corner")
eq(relative, parent, "handle belongs to the bar")
eq(anchor, "TOPLEFT", "handle anchor is independent of bar dimensions")
for _, size in ipairs({ {40, 400}, {400, 40}, {170, 26}, {44, 44} }) do
    parent:SetSize(unpack(size))
    local _, _, _, x, y = parent:GetPoint()
    eq(x, 100, "width changes keep fixed x")
    eq(y, 100, "height changes keep fixed y")
end
-- StartMoving can choose a new screen-relative own anchor; normalize on stop.
parent:ClearAllPoints(); parent:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -100, 80)
parent:SetSize(80, 120)
handle.scripts.OnDragStop(handle)
eq(ns.db.palettePoint[1], "TOPLEFT", "drag saves fixed corner")
eq(ns.db.palettePoint[3], -180, "right anchor normalizes with current width")
eq(ns.db.palettePoint[4], 200, "bottom anchor normalizes with current height")
ns.Handle:Anchor(parent)
eq(ns.db.palettePoint[3], -180, "migration is not repeated")
eq(ns.db.palettePoint[4], 200, "reload preserves anchor")
io.write("fixed handle tests passed\n")

-- AUTO flyouts use the fixed corner, so status resizing cannot flip their side.
ns.Layout = { FlyoutSide = function(vertical, x, y, width, height)
    if vertical then return x > width / 2 and "LEFT" or "RIGHT" end
    return y < height / 2 and "UP" or "DOWN"
end }
assert(loadfile("UI/Palette.lua"))("Buffsmith", ns)
UIParent:SetSize(1000, 1000)
parent.GetCenter = function(self) return 450 + self:GetWidth() / 2, 600 - self:GetHeight() / 2 end
parent:SetSize(40, 40)
eq(ns.Palette.FlyoutSide(parent, true), "RIGHT", "small grid opens away from left screen edge")
eq(ns.Palette.FlyoutSide(parent, false), "DOWN", "small grid opens down from upper half")
parent:SetSize(170, 240)
eq(ns.Palette.FlyoutSide(parent, true), "RIGHT", "status width cannot flip flyout side")
eq(ns.Palette.FlyoutSide(parent, false), "DOWN", "status height cannot flip flyout side")

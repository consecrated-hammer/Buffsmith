local addonName, ns = ...

-- Pure geometry for the icon bar, shared by the live secure bar and the
-- settings preview. No WoW API calls belong here: the preview must be able to
-- lay itself out without touching the secure buttons the live bar owns.
--
-- Primaries flow in one line. A category's alternatives are not part of that
-- flow: they sit in a flyout beside their primary, so opening one never moves
-- any other icon and the bar's size never depends on what is in a flyout.

ns.Layout = {}
local Layout = ns.Layout

local SPACING = 6
local SUB_GAP = 4
local MIN_SUB_SIZE = 22
local SUB_SCALE = 0.76
local INSET = 2

function Layout.SubSize(mainSize)
    return math.max(MIN_SUB_SIZE, math.floor(mainSize * SUB_SCALE))
end

-- Which way a flyout opens. It runs across the bar's own direction, so a
-- vertical bar flies out sideways and a horizontal bar flies out up or down,
-- and it points at whichever side of the screen has room.
function Layout.FlyoutSide(vertical, centreX, centreY, screenWidth, screenHeight)
    if vertical then
        return (centreX and screenWidth and centreX > screenWidth / 2) and "LEFT" or "RIGHT"
    end
    return (centreY and screenHeight and centreY < screenHeight / 2) and "UP" or "DOWN"
end

local function flyoutPlacement(side, x, y, mainSize, subSize, step)
    local offset = (step - 1) * (subSize + SUB_GAP)
    local across = math.floor((mainSize - subSize) / 2)
    if side == "LEFT" then return x - SUB_GAP - subSize - offset, y - across end
    if side == "UP" then return x + across, y + SUB_GAP + subSize + offset end
    if side == "DOWN" then return x + across, y - mainSize - SUB_GAP - offset end
    return x + mainSize + SUB_GAP + offset, y - across
end

-- items: ordered list of { subs = <flyout icon count> }
-- opts:  { mainSize = <px>, vertical = <boolean>, flyout = "LEFT"|"RIGHT"|"UP"|"DOWN" }
function Layout.Compute(items, opts)
    local mainSize = opts.mainSize
    local vertical = opts.vertical == true
    local side = opts.flyout or (vertical and "RIGHT" or "DOWN")
    local subSize = Layout.SubSize(mainSize)
    local mainX, mainY = INSET, -INSET
    local width, height = mainSize + 4, mainSize + 4
    local mains, subs = {}, {}

    for _, item in ipairs(items) do
        local x, y = mainX, mainY
        mains[#mains + 1] = { x = x, y = y, size = mainSize }

        for step = 1, (item.subs or 0) do
            local sx, sy = flyoutPlacement(side, x, y, mainSize, subSize, step)
            subs[#subs + 1] = { x = sx, y = sy, size = subSize, parent = #mains }
        end

        if vertical then
            mainY = mainY - mainSize - SPACING
            height = math.max(height, -mainY + INSET)
        else
            mainX = mainX + mainSize + SPACING
            width = math.max(width, mainX - SPACING + INSET)
        end
    end

    return {
        mains = mains,
        subs = subs,
        subSize = subSize,
        side = side,
        width = math.max(mainSize + 4, width),
        height = math.max(mainSize + 4, height),
    }
end

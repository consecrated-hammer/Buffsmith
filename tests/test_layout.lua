local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

local ns = {}
assert(loadfile("UI/Layout.lua"))("Buffsmith", ns)
local Layout = ns.Layout

-- Primary-icon geometry, transcribed from the pre-refactor UI/Palette.lua
-- Refresh loop with the alternatives left out. Alternatives used to be
-- inline and displace later primaries; they are now a flyout, so only the
-- primary flow is checked against shipped behaviour. Do not tidy this copy.
local function reference(count, opts)
    local mainSize = opts.mainSize
    local spacing = 6
    local vertical = opts.vertical == true
    local mainX, mainY = 2, -2
    local width, height = mainSize + 4, mainSize + 4
    local mains = {}
    for _ = 1, count do
        mains[#mains + 1] = { x = mainX, y = mainY, size = mainSize }
        if vertical then
            mainY = mainY - mainSize - spacing
            height = math.max(height, -mainY + 2)
        else
            mainX = mainX + mainSize + spacing
            width = math.max(width, mainX - spacing + 2)
        end
    end
    return { mains = mains, width = math.max(mainSize + 4, width), height = math.max(mainSize + 4, height) }
end

-- Spot checks pinning the shipped numbers, independent of the reference copy.
local horizontal = Layout.Compute({ {}, {}, {} }, { mainSize = 40, vertical = false })
equal(horizontal.width, 136, "three 40px icons span 3*40 + 2*6 + 4")
equal(horizontal.height, 44, "a horizontal row is one icon tall")
equal(horizontal.mains[2].x, 48, "the second icon clears the first plus spacing")
equal(horizontal.mains[2].y, -2, "a horizontal row keeps every icon on one line")

-- Vertical mode counts the trailing gap below the last icon, so a lone 40px
-- icon reports 50 rather than 44. Shipped behaviour; preserved deliberately.
local vertical = Layout.Compute({ {} }, { mainSize = 40, vertical = true })
equal(vertical.height, 50, "vertical height includes the trailing spacing")
equal(vertical.width, 44, "vertical width is one icon wide")

local empty = Layout.Compute({}, { mainSize = 40, vertical = true })
equal(#empty.mains, 0, "an empty bar places nothing")
equal(empty.width, 44, "an empty bar keeps the minimum width")
equal(empty.height, 44, "an empty bar keeps the minimum height")

equal(Layout.SubSize(24), 22, "small icons clamp flyout icons to the 22px floor")
equal(Layout.SubSize(64), 48, "large icons scale flyout icons by 0.76")

-- Flyouts: 40px primary at (2, -2), 30px flyout icons, 4px gap, so the
-- cross-axis centring offset is 5.
local function flyout(side, isVertical)
    return Layout.Compute({ { subs = 2 } }, { mainSize = 40, vertical = isVertical, flyout = side })
end
local right = flyout("RIGHT", true)
equal(right.subs[1].x, 46, "a right flyout starts past the primary and the gap")
equal(right.subs[1].y, -7, "a right flyout centres on the primary")
equal(right.subs[2].x, 80, "a right flyout advances by icon plus gap")
equal(right.subs[2].y, -7, "a right flyout stays on one line")
local left = flyout("LEFT", true)
equal(left.subs[1].x, -32, "a left flyout ends before the primary and the gap")
equal(left.subs[2].x, -66, "a left flyout advances away from the bar")
local down = flyout("DOWN", false)
equal(down.subs[1].x, 7, "a downward flyout centres under the primary")
equal(down.subs[1].y, -46, "a downward flyout starts below the primary and the gap")
equal(down.subs[2].y, -80, "a downward flyout stacks away from the bar")
local up = flyout("UP", false)
equal(up.subs[1].y, 32, "an upward flyout starts above the primary and the gap")
equal(up.subs[2].y, 66, "an upward flyout stacks away from the bar")
equal(right.subs[1].parent, 1, "a flyout icon names its primary")
equal(right.side, "RIGHT", "the chosen side is reported")

-- Default side follows the bar's direction.
equal(Layout.Compute({ { subs = 1 } }, { mainSize = 40, vertical = true }).side, "RIGHT", "vertical defaults right")
equal(Layout.Compute({ { subs = 1 } }, { mainSize = 40, vertical = false }).side, "DOWN", "horizontal defaults down")

-- Which side has room.
equal(Layout.FlyoutSide(true, 300, 400, 1920, 1080), "RIGHT", "a bar on the left opens right")
equal(Layout.FlyoutSide(true, 1500, 400, 1920, 1080), "LEFT", "a bar on the right opens left")
equal(Layout.FlyoutSide(false, 900, 800, 1920, 1080), "DOWN", "a bar high on screen opens down")
equal(Layout.FlyoutSide(false, 900, 200, 1920, 1080), "UP", "a bar low on screen opens up")
equal(Layout.FlyoutSide(true, nil, nil, nil, nil), "RIGHT", "an unplaced bar falls back to right")
equal(Layout.FlyoutSide(false, nil, nil, nil, nil), "DOWN", "an unplaced bar falls back to down")

-- The point of a flyout: it never changes what the rest of the bar does.
for _, side in ipairs({ "LEFT", "RIGHT", "UP", "DOWN" }) do
    for _, isVertical in ipairs({ true, false }) do
        for mainSize = 24, 64, 2 do
            for mains = 0, 4 do
                local items, plain = {}, {}
                for index = 1, mains do
                    items[index] = { subs = index == mains and 3 or 0 }
                    plain[index] = {}
                end
                local opts = { mainSize = mainSize, vertical = isVertical, flyout = side }
                local got = Layout.Compute(items, opts)
                local want = reference(mains, opts)
                local label = ("%s %s size=%d mains=%d"):format(side, isVertical and "vertical" or "horizontal", mainSize, mains)
                equal(got.width, want.width, label .. " width")
                equal(got.height, want.height, label .. " height")
                equal(#got.mains, #want.mains, label .. " main count")
                for i, main in ipairs(want.mains) do
                    equal(got.mains[i].x, main.x, label .. " main " .. i .. " x")
                    equal(got.mains[i].y, main.y, label .. " main " .. i .. " y")
                    equal(got.mains[i].size, main.size, label .. " main " .. i .. " size")
                end
                equal(#got.subs, mains > 0 and 3 or 0, label .. " flyout count")
            end
        end
    end
end

print("layout tests passed")

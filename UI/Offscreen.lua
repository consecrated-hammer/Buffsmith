local _, ns = ...
local Guard = { queued = false }
ns.Offscreen = Guard

local function number(value)
    value = ns.Plain(value)
    if type(value) == "number" and value == value and math.abs(value) < math.huge then return value end
end
local function rect(frame, scale)
    local left, right = number(frame:GetLeft()), number(frame:GetRight())
    local top, bottom = number(frame:GetTop()), number(frame:GetBottom())
    if not left or not right or not top or not bottom or right <= left or top <= bottom then return nil end
    return { left = left * scale, right = right * scale, top = top * scale, bottom = bottom * scale }
end
local function outside(box, screen, margin)
    return box.right < screen.left - margin or box.left > screen.right + margin
        or box.top < screen.bottom - margin or box.bottom > screen.top + margin
end

function Guard:Inspect()
    local frame, handle
    if ns.Palette and ns.Palette.frame and ns.Palette.frame:IsShown() then
        frame, handle = ns.Palette.frame, ns.Handle and ns.Handle.frame
    elseif ns.Preview and not ns.Preview.settingsMode and ns.Preview.frame and ns.Preview.frame:IsShown() then
        frame, handle = ns.Preview.frame, ns.Preview.handle
    end
    if not frame then return nil end
    local parentScale = number(UIParent:GetEffectiveScale())
    local frameScale = number(frame:GetEffectiveScale())
    if not parentScale or parentScale <= 0 or not frameScale or frameScale <= 0 then return nil end
    local screen = rect(UIParent, 1)
    local bounds = rect(frame, frameScale / parentScale)
    if not screen or not bounds then return nil end
    -- Whole-bar loss only. Small overhangs and a reachable grip are not errors.
    if not outside(bounds, screen, 16) then return false, nil, bounds, screen end
    if handle and handle:IsShown() then
        local handleScale = number(handle:GetEffectiveScale())
        local grip = handleScale and rect(handle, handleScale / parentScale)
        if grip and not outside(grip, screen, 0) then return false, nil, bounds, screen end
    end
    -- Use the actual top corner, including previews, and ignore sub-pixel drift.
    local function pixel(value) return math.floor(value + 0.5) end
    local signature = table.concat({ pixel(bounds.left), pixel(bounds.top),
        pixel(screen.left), pixel(screen.right), pixel(screen.top), pixel(screen.bottom) }, ":")
    return true, signature, bounds, screen
end

function Guard:Hide(silent)
    if not self.prompt then return end
    self.silentHide = silent
    self.prompt:Hide()
    self.silentHide = false
end
function Guard:BuildPrompt()
    if self.prompt then return end
    local HC, UI = ns.HC, ns.HC.UI
    local prompt = CreateFrame("Frame", "BuffsmithOffscreenPrompt", UIParent, "BackdropTemplate")
    self.prompt = prompt
    prompt:SetSize(380,168); prompt:SetPoint("CENTER"); prompt:SetFrameStrata("DIALOG")
    prompt:SetClampedToScreen(true); prompt:EnableMouse(true)
    HC.Theme.Surface(prompt,"panel","edge")
    local title=UI.FontString(prompt,"GameFontNormal","accent")
    title:SetPoint("TOPLEFT",16,-14); title:SetText("Buffsmith is off-screen")
    local text=UI.FontString(prompt,"GameFontHighlight","text")
    text:SetPoint("TOPLEFT",16,-42); text:SetWidth(348); text:SetJustifyH("LEFT")
    text:SetText("The bar appears to be outside your screen.\nReset its position to bring it back?")
    local check=UI.CheckButton(prompt); self.check=check
    check:SetPoint("BOTTOMLEFT",15,45); check.Text:SetText("Don't show again")
    check:SetScript("OnClick",function()
        check:SetChecked(not check:GetChecked())
        ns.db.warnOffscreen = not check:GetChecked()
        local page=HC.Settings.pages and HC.Settings.pages.Appearance
        if page and page.hcRefreshAll then page.hcRefreshAll() end
    end)
    local reset=UI.Button(prompt,136,24,"primary"); self.reset=reset
    reset:SetPoint("BOTTOMRIGHT",-126,14); reset:SetText("Reset position")
    reset:SetScript("OnClick",function()
        -- Combat may have started after the prompt was drawn.
        if ns.IsCombatLocked() then self:Hide(true); return end
        local lost=self:Inspect()
        if lost == true then HC.spec.resetPosition(); self.lastRecovery="owner accepted off-screen reset" end
        self:Hide(true)
    end)
    local cancel=UI.Button(prompt,100,24); self.cancel=cancel
    cancel:SetPoint("BOTTOMRIGHT",-16,14); cancel:SetText("Not now")
    cancel:SetScript("OnClick",function() self:Hide(false) end)
    prompt:SetScript("OnHide",function()
        if not self.silentHide then self.snoozedSignature=self.openSignature end
        self.openSignature=nil
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]="BuffsmithOffscreenPrompt" end
    self:Hide(true)
end
function Guard:Check()
    if not ns.db then return end
    if ns.IsCombatLocked() then self:Hide(true); return end
    if not ns.db.warnOffscreen then self:Hide(true); return end
    local lost,signature,bounds,screen=self:Inspect()
    if bounds and screen then
        self.lastBounds=("bar %.1f,%.1f to %.1f,%.1f; viewport %.1f,%.1f to %.1f,%.1f"):format(
            bounds.left,bounds.bottom,bounds.right,bounds.top,screen.left,screen.bottom,screen.right,screen.top)
    end
    self.lastCheck = lost == true and "fully off-screen" or lost == false and "reachable" or "not measurable or hidden"
    if lost ~= true then
        if lost == false then self.snoozedSignature=nil end
        self:Hide(true)
        return
    end
    if signature == self.snoozedSignature then return end
    self:BuildPrompt()
    self.openSignature=signature
    self.check:SetChecked(not ns.db.warnOffscreen)
    self.prompt:Show()
end
function Guard:Queue(reason)
    if not ns.db or not ns.db.warnOffscreen then return end
    self.lastReason=reason
    if self.queued then return end
    self.queued=true
    C_Timer.After(0.25,function() self.queued=false; self:Check() end)
end
function Guard:Watch(frame)
    if not frame or frame.buffsmithOffscreenWatched then return end
    frame.buffsmithOffscreenWatched = true
    frame:HookScript("OnShow", function() self:Queue("frame shown") end)
    frame:HookScript("OnHide", function() self:Queue("frame hidden") end)
    frame:HookScript("OnSizeChanged", function() self:Queue("layout settled") end)
end
function Guard:Init()
    if self.events then return end
    local events=CreateFrame("Frame"); self.events=events
    for _,event in ipairs({"PLAYER_LOGIN","PLAYER_ENTERING_WORLD","DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED"}) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent",function(_,event)
        if event == "PLAYER_REGEN_DISABLED" then self:Hide(true)
        else self:Queue(event) end
    end)
    self:Watch(ns.Palette and ns.Palette.frame)
    self:Watch(ns.Preview and ns.Preview.frame)
    self:Queue("initial position")
end

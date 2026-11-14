package.path="./tests/hammercore/?.lua;"..package.path
local wow=require("wow")
local count=0
local function eq(a,b,label) count=count+1; assert(a==b,label..": "..tostring(a).." ~= "..tostring(b)) end
for _,target in ipairs({"Retail","Forever"}) do
    wow.Install()
    local ns=wow.LoadHammerCore("Libs/HammerCore","Buffsmith")
    ns.HC=ns.HammerCore
    ns.db={warnOffscreen=true,palettePoint={"TOPLEFT","RIGHT",2226,262}}
    ns.Plain=function(v) return v end
    local combat=false
    ns.IsCombatLocked=function() return combat end
    local timers={}
    C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
    local function flush() local work=timers;timers={};for _,fn in ipairs(work) do fn() end end
    local function box(frame,l,b,r,t,scale)
        frame.GetLeft=function()return l end;frame.GetBottom=function()return b end
        frame.GetRight=function()return r end;frame.GetTop=function()return t end
        frame.GetEffectiveScale=function()return scale or 1 end
    end
    box(UIParent,0,0,1920,1080)
    local bar=CreateFrame("Frame",nil,UIParent)
    local handle=CreateFrame("Frame",nil,bar)
    box(bar,4146,500,4300,700); box(handle,4146,702,4158,712)
    ns.Palette={frame=bar};ns.Handle={frame=handle}
    local preview=CreateFrame("Frame",nil,UIParent);preview:Hide()
    ns.Preview={frame=preview,settingsMode=false}
    local resets=0
    ns.HC:Init({name="Buffsmith",command="buffsmith",db=function()return ns.db end,
        resetPosition=function() resets=resets+1;box(bar,900,450,1100,650) end})
    assert(loadfile("UI/Offscreen.lua"))("Buffsmith",ns)
    local guard=ns.Offscreen
    eq(guard:Inspect(),true,target..": reported position detected")
    guard:Check();eq(guard.prompt:IsShown(),true,target..": prompt visible")
    eq(resets,0,target..": no automatic movement")
    guard.cancel.scripts.OnClick();eq(guard.prompt:IsShown(),false,"Not now closes")
    guard:Check();eq(guard.prompt:IsShown(),false,"same position snoozed")
    box(bar,1900,450,2100,650);box(handle,2000,660,2012,670)
    eq(guard:Inspect(),false,"partial overhang does not warn")
    guard:Check()
    box(bar,-250,450,-20,650);box(handle,10,660,22,670)
    eq(guard:Inspect(),false,"reachable grip prevents warning")
    box(handle,-250,660,-238,670)
    eq(guard:Inspect(),true,"fully left and unreachable")
    guard:Check();guard.check.scripts.OnClick()
    eq(guard.check:GetChecked(),true,"Don't show again checked")
    eq(ns.db.warnOffscreen,false,"opt-out saved")
    guard.cancel.scripts.OnClick();guard.snoozedSignature=nil;guard:Check()
    eq(guard.prompt:IsShown(),false,"opt-out suppresses future prompt")
    ns.db.warnOffscreen=true;guard:Check()
    combat=true;guard.reset.scripts.OnClick()
    eq(resets,0,"stale combat click cannot move secure bar")
    eq(guard.prompt:IsShown(),false,"combat hides prompt")
    combat=false;guard:Check();guard.reset.scripts.OnClick()
    eq(resets,1,"owner accepts reset")
    eq(guard.prompt:IsShown(),false,"reset closes prompt")
    guard:Check();eq(guard.lastCheck,"reachable","successful recovery observed")
    box(bar,2000,300,2200,500);box(handle,2000,502,2012,512)
    guard:Check();box(bar,900,450,1100,650);guard.reset.scripts.OnClick()
    eq(resets,1,"stale prompt rechecks geometry before reset")
    box(bar,2000,300,2200,500,0.5);box(handle,2000,502,2012,512,0.5)
    eq(guard:Inspect(),false,"effective scale converted into viewport units")
    box(bar,2000,300,2200,500);box(UIParent,0,0,0,0)
    eq(guard:Inspect(),nil,"unsettled screen dimensions ignored")
    box(UIParent,0,0,1920,1080);box(bar,0/0,300,2200,500)
    eq(guard:Inspect(),nil,"invalid coordinates ignored")
    box(bar,2000,300,2200,500);bar:Hide()
    eq(guard:Inspect(),nil,"hidden bar ignored")
    preview:Show();ns.Preview.settingsMode=true;box(preview,2000,300,2200,500)
    eq(guard:Inspect(),nil,"settings preview excluded")
    ns.Preview.settingsMode=false
    eq(guard:Inspect(),true,"lost on-screen preview covered")
    preview:Hide();bar:Show();box(handle,2000,502,2012,512)
    guard:Init();timers={};guard.queued=false;guard.snoozedSignature=nil
    for i=1,10 do guard:Queue("resize") end
    eq(#timers,1,"resize checks coalesced")
    combat=true;flush();eq(guard.prompt:IsShown(),false,"queued prompt deferred in combat")
    combat=false;guard.events.scripts.OnEvent(guard.events,"PLAYER_REGEN_ENABLED");flush()
    eq(guard.prompt:IsShown(),true,"prompt retried after combat")
    guard.events.scripts.OnEvent(guard.events,"PLAYER_REGEN_DISABLED")
    eq(guard.prompt:IsShown(),false,"combat entry closes prompt")
    guard.events.scripts.OnEvent(guard.events,"UI_SCALE_CHANGED");flush()
    eq(guard.prompt:IsShown(),true,"scale event checks viewport")
    guard:Hide(false)
    box(UIParent,0,0,1800,1000)
    guard.events.scripts.OnEvent(guard.events,"DISPLAY_SIZE_CHANGED");flush()
    eq(guard.prompt:IsShown(),true,"changed screen can prompt again")
    guard:Hide(false)
    box(UIParent,0,0,1800.00001,1000)
    guard:Check();eq(guard.prompt:IsShown(),false,"sub-pixel drift does not repeat declined prompt")
    box(bar,500,1100,700,1200);box(handle,500,1202,512,1212)
    eq(guard:Inspect(),true,"fully above viewport")
    box(bar,500,-200,700,-100);box(handle,500,-98,512,-88)
    eq(guard:Inspect(),true,"fully below viewport")
    local late=CreateFrame("Frame",nil,UIParent)
    guard:Watch(late);local script=late.scripts.OnShow
    guard:Watch(late);eq(late.scripts.OnShow,script,"late frame hook is idempotent")
    late:Hide();timers={};guard.queued=false;late:Show()
    eq(#timers,1,"lazy frame creation covered")
end
io.write("Off-screen prompt: "..count.." checks passed\n")

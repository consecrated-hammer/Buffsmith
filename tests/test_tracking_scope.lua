local checks=0
local function eq(a,b,label)checks=checks+1;if a~=b then error(label..": expected "..tostring(b)..", got "..tostring(a),2)end end
local guid,list
local function load(target)
    guid="Player-A"
    list={{name="Find Minerals",texture=1,active=false,type="spell",spellID=2580}}
    UnitGUID=function()return guid end
    UnitClass=function()return "Warrior","WARRIOR"end
    C_Minimap={GetNumTrackingTypes=function()return #list end,GetTrackingInfo=function(i)return list[i]end}
    GetNumTrackingTypes,GetTrackingInfo=nil,nil
    local db={excludedBuffs={[2580]=true},trackingChoice=2383,buffDurations={},excludedConsumables={}}
    local ns={TARGET=target,db=db,Plain=function(v)return v end}
    assert(loadfile("Data/SelfBuffs.lua"))("Buffsmith",ns)
    assert(loadfile("Features/Tracking.lua"))("Buffsmith",ns)
    return ns,db
end
for _,target in ipairs({"Camelot","Mainline"})do
    local ns,db=load(target);local T=ns.Tracking;local minerals=T:Available()[1]
    eq(T:IsShared(2580),false,target.." defaults to character scope")
    eq(#T:Entries(),1,target.." a new miner is offered its only gathering tracker")
    eq(db.excludedBuffs[2580],true,target.." legacy account exclusion retained")
    T:SetEnabled(minerals,false,true)
    eq(#T:Entries(),0,target.." local disable hides the tracker")
    guid="Player-B"
    eq(#T:Entries(),1,target.." other character does not inherit disabled tracker")
    guid="Player-A"
    eq(T:IsIgnored(minerals),true,target.." local ignored state restored")
    T:SetShared(minerals,true)
    eq(T:IsShared(2580),true,target.." scope can be shared")
    eq(#T:Entries(),0,target.." sharing adopts existing account off choice")
    T:SetEnabled(minerals,true)
    guid="Player-B"
    eq(#T:Entries(),1,target.." shared enable reaches second character")
    T:SetEnabled(minerals,false)
    guid="Player-A"
    eq(#T:Entries(),0,target.." shared disable reaches first character")
    T:SetShared(minerals,false)
    T:SetEnabled(minerals,true)
    guid="Player-B"
    eq(#T:Entries(),1,target.." unsharing restores independent default on second character")
    T:SetEnabled(minerals,false)
    guid="Player-A"
    eq(#T:Entries(),1,target.." independent change cannot disable first character")
    T:Reset()
    eq(T:IsShared(2580),false,target.." reset preserves selected scope")
    eq(#T:Entries(),1,target.." reset restores gathering default")
    eq(db.trackingChoice,2383,target.." reset preserves legacy account tracker")
    -- Ignore and restore must route through the same scope as the bar/settings.
    assert(loadfile("Features/Actions.lua"))("Buffsmith",ns)
    ns.Actions:Ignore(minerals)
    eq(T:IsIgnored(minerals),true,target.." ignore uses scoped preference")
    eq(#T:Entries(),0,target.." ignored tracker not offered")
    eq(#ns.Actions:IgnoredEntries(),1,target.." ignored list uses scoped choice")
    ns.Actions:Restore("spell",2580)
    eq(T:IsIgnored(minerals),false,target.." restore clears scoped ignore")
    eq(#T:Entries(),1,target.." restored tracker returns")
    eq(#ns.Actions:IgnoredEntries(),0,target.." ignored list clears after restore")
end
-- Mixed shared/local Forever preferences resolve by explicit choice, never list order.
do
    local ns=load("Camelot");local T=ns.Tracking
    list[#list+1]={name="Find Herbs",texture=2,active=false,type="spell",spellID=2383}
    eq(T:SelectedID(),nil,"two gathering defaults require a choice")
    T:Select(2580)
    eq(T:SelectedID(),2580,"explicit Minerals selected")
    T:Select(2580)
    eq(T:SelectedID(),nil,"explicit none persists")
    T:Select(2580)
    local herbs=T:Available()[2]
    T:SetShared(herbs,true)
    eq(T:SelectedID(),2580,"scope change preserves an explicit character choice")
    T:Select(2383,true)
    guid="Player-B"
    eq(T:SelectedID(),2383,"second character uses shared Herbs")
    guid="Player-A"
    T:Select(2580,true)
    eq(T:SelectedID(),2580,"character can explicitly select Minerals instead")
    guid="Player-B"
    eq(T:SelectedID(),2383,"local Minerals pick does not disable shared Herbs")
    T:Select(2383,true)
    guid="Player-A"
    eq(T:SelectedID(),2383,"newer shared choice wins a mixed-scope conflict")
    list[1],list[2]=list[2],list[1]
    eq(T:SelectedID(),2383,"API list order cannot change explicit preference")
    list[1].active=true
    eq(#T:Entries(),0,"active selected tracking is satisfied")
    list[1].active=false
    T:SetEnabled(herbs,false,true)
end
-- Scope changes do not invent a selection; local reset/selection preserve shared and ignored records.
do
    local ns,db=load("Camelot");local T=ns.Tracking
    db.excludedBuffs={};db.trackingChoice=nil
    list[#list+1]={name="Find Herbs",texture=2,active=false,type="spell",spellID=2383}
    local herbs=T:Available()[2]
    T:SetShared(herbs,true)
    eq(T:SelectedID(),nil,"sharing a default does not silently choose it")
    T:Select(2383,true)
    local accountOrder=T:Preference(herbs).order
    T:SetEnabled({spellID=2481,defaultOff=true},false,true)
    T:Reset()
    eq(T:Preference(herbs).order,accountOrder,"character reset does not alter shared choice")
    eq(T:IsShared(2383),true,"character reset does not alter scope")
    eq(T:IsIgnored({spellID=2481,defaultOff=true}),false,"reset clears unavailable character preferences")
    T:SetShared(herbs,false)
    T:SetEnabled(herbs,false,true)
    T:Select(2580,true)
    eq(T:IsIgnored(herbs),true,"selecting another tracker preserves explicit ignore")
    assert(loadfile("Features/Actions.lua"))("Buffsmith",ns)
    ns.KnownSelfBuffCandidates=nil
    db.excludedBuffs[2383]=true
    eq(#ns.Actions:IgnoredEntries(),1,"legacy tracking exclusion cannot duplicate scoped ignored row")
    ns.Actions:Restore("spell",2383)
    eq(#ns.Actions:IgnoredEntries(),0,"restore removes scoped ignored row despite retained legacy exclusion")
end
-- First-time sharing preserves an explicit local choice; restoration preserves selection.
do
    local ns,db=load("Camelot");local T=ns.Tracking;local minerals=T:Available()[1]
    T:Select(2580,true)
    T:SetShared(minerals,true)
    eq(T:IsExcluded(minerals),false,"first sharing preserves explicit enabled character choice")
    eq(T:SelectedID(),2580,"first sharing preserves explicit selection")
    eq(db.excludedBuffs[2580],true,"old account record is not destroyed")
end
do
    local ns,db=load("Camelot");local T=ns.Tracking;local minerals=T:Available()[1]
    db.trackingChoice=nil;db.excludedBuffs[2580]=false
    T:SetShared(minerals,true)
    eq(T:IsExcluded(minerals),false,"legacy explicit on is adopted as on")
    list[#list+1]={name="Find Herbs",texture=2,active=false,type="spell",spellID=2383}
    T:SetEnabled(minerals,false,true)
    T:Select(2383,true)
    assert(loadfile("Features/Actions.lua"))("Buffsmith",ns)
    ns.Actions:Restore("spell",2580)
    eq(T:SelectedID(),2383,"restoring ignored Minerals does not steal Herbs selection")
    eq(T:IsIgnored(minerals),false,"restore clears ignore without choosing tracker")
end
do
    local ns,db=load("Mainline");local T=ns.Tracking
    T:Entries()
    eq(next(db.trackingPreferences.characters),nil,"reading defaults does not create character buckets")
    db.trackingPreferences.account=nil
    eq(T:IsShared(2580),false,"replaced nested storage is repaired after a cache hit")
    eq(type(db.trackingPreferences.account),"table","account store repaired")
end
-- A missing identity cannot leak preferences into another character's saved record.
do
    local ns,db=load("Mainline");local T=ns.Tracking;local entry=T:Available()[1]
    guid=nil;eq(T:SetEnabled(entry,false),false,"unknown identity cannot save a choice")
    eq(next(db.trackingPreferences.characters),nil,"no unknown saved-character bucket")
    guid="Player-A"
    T:SetEnabled(entry,false)
    eq(T:IsExcluded(entry),true,"resolved character can save its choice")
    guid="Player-B"
    eq(T:IsExcluded(entry),false,"other character remains independent")
end
print("Tracking scopes: "..checks.." checks passed")

local addonName, ns = ...

SLASH_BUFFSMITH1 = "/buffsmith"
SLASH_BUFFSMITH2 = "/bsmith"
SLASH_BUFFSMITH3 = "/bs"
SlashCmdList.BUFFSMITH = function(message)
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if message == "debug" or message == "copy" then
        ns.Diagnostics:ShowCopy()
    elseif message == "report" then
        ns.Print(ns.Diagnostics:Report():gsub("\n", " | "))
    elseif message == "toggle" then
        ns.Set("visibilityMode", ns.db.visibilityMode == "NEVER" and "ALWAYS" or "NEVER")
    elseif message == "preview" then
        ns.Preview:Toggle()
        ns.Options:RefreshPreviewToggle()
    elseif message == "scan" then
        ns.Inventory:Refresh()
    else
        ns.Options:Toggle()
    end
end

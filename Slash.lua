local addonName, ns = ...

SLASH_BUFFSMITH1 = "/buffsmith"
SLASH_BUFFSMITH2 = "/bsmith"
SlashCmdList.BUFFSMITH = function(message)
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if message == "debug" or message == "copy" then
        ns.Diagnostics:ShowCopy()
    elseif message == "report" then
        ns.Print(ns.Diagnostics:Report():gsub("\n", " | "))
    elseif message == "toggle" then
        ns.Set("showPalette", not ns.db.showPalette)
    elseif message == "scan" then
        ns.Inventory:Refresh()
    else
        ns.Options:Toggle()
    end
end

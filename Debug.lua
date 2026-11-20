local _, ns = ...

-- /packrat debug: which game APIs this client has, and what the ones Packrat
-- relies on actually return. WoW Forever shares retail's UI code, so the
-- answers differ from Classic Era in places; this report settles it in game.
local Debug = {}
ns.Debug = Debug

local function get(path)
    local value = _G
    for part in path:gmatch("[^%.]+") do
        if type(value) ~= "table" then
            return nil
        end
        value = value[part]
    end
    return value
end

local APIS = {
    "GetQuestLogTitle", "GetQuestLogQuestText", "GetQuestLogLeaderBoard", "SelectQuestLogEntry", "ExpandQuestHeader",
    "C_QuestLog.GetInfo", "C_QuestLog.GetQuestObjectives", "C_QuestLog.SetSelectedQuest", "C_QuestLog.IsQuestFlaggedCompleted",
    "IsQuestFlaggedCompleted", "GetQuestGreenRange",
    "C_Container.GetContainerItemInfo", "C_Container.GetContainerItemQuestInfo", "C_Container.UseContainerItem",
    "C_Container.PickupContainerItem", "UseContainerItem", "DeleteCursorItem", "C_Item.DeleteItem", "C_Item.ConfirmDeleteItem",
    "C_TooltipInfo.GetBagItem", "TooltipDataProcessor.AddTooltipPostCall", "GetSkillLineInfo", "C_SkillInfo.GetSkillLineInfo",
    "Baganator.API.RegisterUpgradePlugin", "Syndicator.API.GetInventoryInfoByItemID", "LibStub", "PawnIsItemAnUpgrade",
}

local function probeQuestText(lines)
    if not (GetQuestLogTitle and GetNumQuestLogEntries) then
        return
    end
    for i = 1, GetNumQuestLogEntries() do
        local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
        if title and not isHeader then
            lines[#lines + 1] = string.format("first quest: %q id=%s", title, tostring(questID))
            if SelectQuestLogEntry and GetQuestLogQuestText then
                SelectQuestLogEntry(i)
                local ok, description, objectives = pcall(GetQuestLogQuestText, i)
                lines[#lines + 1] = string.format("  GetQuestLogQuestText(i): ok=%s description=%d chars, objectives=%d chars",
                    tostring(ok), #(type(description) == "string" and description or ""), #(type(objectives) == "string" and objectives or ""))
            end
            if questID and C_QuestLog and C_QuestLog.GetQuestObjectives then
                local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
                lines[#lines + 1] = string.format("  C_QuestLog.GetQuestObjectives: ok=%s count=%s", tostring(ok),
                    tostring(type(list) == "table" and #list or list))
            end
            return
        end
    end
end

function Debug.Report()
    local version, build, _, interface = GetBuildInfo()
    local lines = {
        string.format("Packrat debug  ·  client %s (%s), interface %s, project %s", tostring(version), tostring(build),
            tostring(interface), tostring(WOW_PROJECT_ID)),
        string.format("quest data: %s", ns.QuestData and ns.QuestData.source or "missing"),
        string.format("bags: %d items, %d/%d free  ·  quests in log: %d", #ns.items, ns.space.free, ns.space.total, #ns.Quests.list),
        "",
        "API availability:",
    }
    for _, name in ipairs(APIS) do
        lines[#lines + 1] = string.format("  %-45s %s", name, get(name) ~= nil and "yes" or "-")
    end
    lines[#lines + 1] = ""
    probeQuestText(lines)
    local ctx = ns.Context()
    lines[#lines + 1] = string.format("class %s, raceBit %s, classBit %s, greenRange %s", tostring(ctx.class),
        tostring(ctx.raceBit), tostring(ctx.classBit), tostring(ctx.greenRange))
    local api = _G.Syndicator and _G.Syndicator.API
    lines[#lines + 1] = string.format("Syndicator: loaded=%s ready=%s current=%s name=%s", tostring(api ~= nil),
        tostring(api and api.IsReady and api.IsReady()), tostring(api and api.GetCurrentCharacter and api.GetCurrentCharacter()),
        tostring(ns.SyndicatorName(api)))
    local bank, bankError = ns.ReadBank()
    lines[#lines + 1] = string.format("bank: %s", bankError and ("ERROR " .. bankError) or (#bank .. " items"))
    local doneCheck = ns.IsQuestDone(783) -- "A Threat Within", the first Human quest; just exercises the call
    lines[#lines + 1] = "IsQuestDone(783) returned " .. tostring(doneCheck)
    return table.concat(lines, "\n")
end

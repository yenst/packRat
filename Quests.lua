local _, ns = ...

-- Reads the quest log: level, completion, objective lines and the quest text,
-- so items can be matched to the quests that need them.
local Quests = {}
ns.Quests = Quests

Quests.list, Quests.byID = {}, {}

local function hasModernLog()
    return C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries
end

-- Classic hides quests under collapsed headers, so expand everything while
-- reading and collapse the same headers again afterwards.
local function withExpandedLog(read)
    if not (ExpandQuestHeader and CollapseQuestHeader and GetQuestLogTitle) then
        return read()
    end
    local collapsed = {}
    for i = 1, GetNumQuestLogEntries() do
        local title, _, _, isHeader, isCollapsed = GetQuestLogTitle(i)
        if isHeader and isCollapsed then
            collapsed[title] = true
        end
    end
    if not next(collapsed) then
        return read()
    end
    Quests.expanding = true
    ExpandQuestHeader(0)
    local result = read()
    for i = GetNumQuestLogEntries(), 1, -1 do
        local title, _, _, isHeader = GetQuestLogTitle(i)
        if isHeader and collapsed[title] then
            CollapseQuestHeader(i)
        end
    end
    Quests.expanding = false
    return result
end

local function readClassic()
    local list = {}
    for i = 1, GetNumQuestLogEntries() do
        local title, level, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
        if not isHeader and title then
            local quest = { id = questID or -i, title = title, level = level, complete = isComplete == 1, objectives = {} }
            for j = 1, (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i)) or 0 do
                local text = GetQuestLogLeaderBoard(j, i)
                if text then
                    quest.objectives[#quest.objectives + 1] = text
                end
            end
            if SelectQuestLogEntry and GetQuestLogQuestText then
                SelectQuestLogEntry(i)
                -- Forever (retail UI code) reads the text of the quest selected by ID.
                if questID and C_QuestLog and C_QuestLog.SetSelectedQuest then
                    pcall(C_QuestLog.SetSelectedQuest, questID)
                end
                local description, objectiveText = GetQuestLogQuestText(i)
                quest.summary = objectiveText
                quest.text = (objectiveText or "") .. "\n" .. (description or "")
            end
            list[#list + 1] = quest
        end
    end
    return list
end

-- Reading the quest text needs each quest selected; put the old selection back
-- by title, since expanding headers shifts the indexes.
local function selectedTitle()
    local index = GetQuestLogSelection and GetQuestLogSelection()
    return index and index > 0 and GetQuestLogTitle(index) or nil
end

local function restoreSelection(title)
    if not (title and SelectQuestLogEntry) then
        return
    end
    for i = 1, GetNumQuestLogEntries() do
        if GetQuestLogTitle(i) == title then
            SelectQuestLogEntry(i)
            return
        end
    end
end

local function readModern()
    local list = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local quest = {
                id = info.questID, title = info.title, level = info.level,
                complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false, objectives = {},
            }
            for _, objective in ipairs(C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                if objective.text then
                    quest.objectives[#quest.objectives + 1] = objective.text
                end
            end
            list[#list + 1] = quest
        end
    end
    return list
end

function Quests.Scan()
    local list
    if GetQuestLogTitle then
        local title = selectedTitle()
        list = withExpandedLog(readClassic)
        restoreSelection(title)
    elseif hasModernLog() then
        list = readModern()
    else
        list = {}
    end
    local byID = {}
    for _, quest in ipairs(list) do
        byID[quest.id] = quest
    end
    Quests.list, Quests.byID = list, byID
    return list
end

-- Cheap fingerprint of the visible log (titles, completion, objective
-- progress), to tell real changes from the events our own scan causes.
function Quests.Signature()
    local parts = {}
    if GetQuestLogTitle then
        local entries, questCount = GetNumQuestLogEntries()
        parts[1] = tostring(questCount)
        for i = 1, entries do
            local title, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
            if not isHeader then
                parts[#parts + 1] = tostring(title) .. tostring(isComplete)
                for j = 1, (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i)) or 0 do
                    parts[#parts + 1] = tostring(GetQuestLogLeaderBoard(j, i))
                end
            end
        end
    elseif hasModernLog() then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                parts[#parts + 1] = info.questID .. tostring(C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID))
                for _, objective in ipairs(C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                    parts[#parts + 1] = tostring(objective.text)
                end
            end
        end
    end
    return table.concat(parts, "|")
end

function Quests.GreenRange(level)
    if GetQuestGreenRange then
        local ok, range = pcall(GetQuestGreenRange, "player")
        if ok and type(range) == "number" then
            return range
        end
    end
    return ns.Rules.GreenRange(level)
end

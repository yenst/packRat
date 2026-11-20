-- Loads the whole addon against a mocked WoW API and clicks through it, to
-- catch nil errors and typos without the game. Run from the repo root:
--   lua5.1 tests/smoke.lua
date, time = os.date, os.time

-- Mock frames: any unknown method is a no-op returning nil.
local Frame = {}
local function newFrame(kind)
    return setmetatable({ scripts = {}, shown = true, text = "", kind = kind }, Frame)
end
local returns = {
    GetWidth = 500, GetHeight = 300, GetVerticalScroll = 0, GetVerticalScrollRange = 100,
    GetFont = "Fonts\\FRIZQT__.TTF", NumLines = 0,
}
Frame.__index = function(_, key)
    if returns[key] ~= nil then
        return function() return returns[key] end
    end
    return rawget(Frame, key) or function() end
end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...)
        if old then old(...) end
        fn(...)
    end
end
function Frame:Fire(name, ...) if self.scripts[name] then self.scripts[name](self, ...) end end
function Frame:Show() self.shown = true; self:Fire("OnShow") end
function Frame:Hide() self.shown = false end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Frame:CreateTexture() return newFrame("Texture") end
function Frame:CreateFontString() return newFrame("FontString") end
function Frame:RegisterEvent(e) local ev = rawget(self, "events") or {}; rawset(self, "events", ev); ev[e] = true end
function Frame:GetItem() return "Wolf Pelt", "|cffffffff|Hitem:750::::::::30:::::|h[Wolf Pelt]|h|r" end
function Frame:AddLine(text) rawset(self, "lastLine", text) end

local allFrames = {}
function CreateFrame(kind, name, parent)
    local f = newFrame(kind)
    rawset(f, "parent", parent)
    allFrames[#allFrames + 1] = f
    if name then _G[name] = f end
    return f
end
UIParent, WorldFrame = newFrame("Frame"), newFrame("Frame")
GameTooltip = newFrame("GameTooltip")
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg)
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t ", "")
    chat[#chat + 1] = msg
    print("[chat] " .. msg)
end }
UISpecialFrames, SlashCmdList = {}, {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
ITEM_BIND_QUEST, ITEM_STARTS_QUEST, ITEM_SOULBOUND = "Quest Item", "This Item Begins a Quest", "Soulbound"
NUM_BAG_SLOTS = 4
tinsert, wipe = table.insert, function(t) for k in pairs(t) do t[k] = nil end return t end
C_AddOns = { IsAddOnLoaded = function(name) return name == "Baganator" end }
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function runTimers()
    for _ = 1, 5 do
        local list = timers
        timers = {}
        for _, fn in ipairs(list) do fn() end
    end
end
IsShiftKeyDown = function() return false end
UnitName = function() return "Tester" end
GetRealmName = function() return "Mirage" end
UnitClass = function() return "Mage", "MAGE", 8 end
UnitRace = function() return "Gnome", "Gnome", 7 end
GetBuildInfo = function() return "1.60.1", "69893", "Nov 2026", 16001 end
WOW_PROJECT_ID = 99
local doneQuests = {}
C_QuestLog = { IsQuestFlaggedCompleted = function(id) return doneQuests[id] == true end }
local player = { level = 30 }
UnitLevel = function() return player.level end
UnitXP, UnitXPMax, GetXPExhaustion, GetMoney = function() return 100 end, function() return 1000 end, function() return 0 end, function() return 12345 end
GetQuestGreenRange = function() return 8 end
-- Skill list with the Professions header collapsed until expanded.
local skillsExpanded = false
GetNumSkillLines = function() return skillsExpanded and 3 or 1 end
GetSkillLineInfo = function(i)
    if i == 1 then return "Professions", true, skillsExpanded end
    if i == 2 then return "Blacksmithing", false, nil, 230, 0, 0, 300 end
    return "Tailoring", false, nil, 75, 0, 0, 150
end
ExpandSkillHeader = function() skillsExpanded = true end
CollapseSkillHeader = function() skillsExpanded = false end
GetInventoryItemLink = function(_, slot) return slot == 1 and "|cff1eff00|Hitem:900::|h[Green Hat]|h|r" or nil end

-- Classic quest log: a header, one current quest, one low quest; the header
-- for the second zone is collapsed until expanded.
local log = {
    { "Duskwood", true, false }, { "Wolves of the Wood", false, false, 30, 101, { "Wolf Pelt: 3/8" } },
    { "Westfall", true, true }, { "Old Errand", false, false, 12, 102, { "Dusty Letter: 0/1" } },
    { "Tanaris", true, false }, { "Gahz'ridian", false, false, 48, 3161, { "Gahz'ridian Ornament: 1/30" } },
}
local expanded = false
local function visibleLog()
    local list = {}
    local hide = false
    for _, e in ipairs(log) do
        if e[2] then
            hide = e[3] and not expanded
            list[#list + 1] = e
        elseif not hide then
            list[#list + 1] = e
        end
    end
    return list
end
local selection = 2
GetNumQuestLogEntries = function() return #visibleLog(), 2 end
GetQuestLogTitle = function(i)
    local e = visibleLog()[i]
    if not e then return nil end
    if e[2] then return e[1], 0, nil, true, e[3] and not expanded end
    return e[1], e[4], nil, false, false, nil, nil, e[5]
end
GetNumQuestLeaderBoards = function(i) local e = visibleLog()[i]; return e and e[6] and #e[6] or 0 end
GetQuestLogLeaderBoard = function(j, i) return visibleLog()[i][6][j] end
GetQuestLogSelection = function() return selection end
SelectQuestLogEntry = function(i) selection = i end
GetQuestLogQuestText = function() return "Some text.", "Do the thing." end
ExpandQuestHeader = function() expanded = true end
CollapseQuestHeader = function() expanded = false end

-- Bags: bag 0 has 16 slots.
local bag = {
    [1] = { itemID = 750, name = "Wolf Pelt", count = 3, quality = 1, classID = 12, price = 0 },
    [2] = { itemID = 751, name = "Dusty Letter", count = 1, quality = 1, classID = 12, price = 0 },
    [3] = { itemID = 752, name = "Broken Fang", count = 4, quality = 0, classID = 15, price = 5 },
    [4] = { itemID = 2589, name = "Linen Cloth", count = 10, quality = 1, classID = 7, price = 13 },
    [5] = { itemID = 6948, name = "Hearthstone", count = 1, quality = 1, classID = 15, price = 0 },
    [6] = { itemID = 9978, name = "Gahz'ridian Detector", count = 1, quality = 1, classID = 12, price = 0 },
}
local function link(e) return "|cffffffff|Hitem:" .. e.itemID .. "::|h[" .. e.name .. "]|h|r" end
local cursor
C_Container = {
    GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
    GetContainerNumFreeSlots = function(b) return b == 0 and 11 or 0 end,
    GetContainerItemInfo = function(b, s)
        local e = b == 0 and bag[s]
        if not e then return nil end
        return { itemID = e.itemID, stackCount = e.count, quality = e.quality, hyperlink = link(e), hasNoValue = e.price == 0 }
    end,
    PickupContainerItem = function(b, s) cursor = { b, s } end,
    UseContainerItem = function(b, s) bag[s] = nil end,
}
GetCursorInfo = function() return cursor and "item" or nil end
ClearCursor = function() cursor = nil end
DeleteCursorItem = function() bag[cursor[2]] = nil; cursor = nil end
local byIDs = {}
for _, e in pairs(bag) do byIDs[e.itemID] = e end
byIDs[900] = { itemID = 900, name = "Green Hat", quality = 2, classID = 4, price = 100 }
GetItemInfo = function(x)
    local id = type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)"))
    local e = byIDs[id]
    if not e then return nil end
    return e.name, link(e), e.quality, 20, 15, "Type", "Sub", 20, "", 134400, e.price, e.classID, 0
end
GetItemInfoInstant = function() return nil end
-- Like WoW Forever (retail UI code): item info only under C_Item.
C_Item = { GetItemInfo = GetItemInfo, GetItemInfoInstant = GetItemInfoInstant }
GetItemInfo, GetItemInfoInstant = nil, nil

-- Baganator stand-in.
local baganator = { regions = {}, corners = {}, junk = {}, refreshes = 0 }
-- LibDataBroker / LibDBIcon and Syndicator stand-ins.
local broker = {}
local libs = {
    ["LibDataBroker-1.1"] = { NewDataObject = function(_, _, obj) broker.obj = obj; return obj end },
    ["LibDBIcon-1.0"] = { Register = function(_, name) broker.icon = name end, Show = function() end, Hide = function() end },
}
LibStub = setmetatable({}, { __call = function(_, name) return libs[name] end })
Syndicator = { API = {
    IsReady = function() return true end,
    GetInventoryInfoByItemID = function(id)
        if id == 2589 then
            return { characters = { { character = "Tester", bags = 10, bank = 40, mail = 0 }, { character = "Alt", bags = 5, bank = 0, mail = 0 } } }
        end
        return { characters = {} }
    end,
    GetCurrentCharacter = function() return "Tester-Mirage" end,
    GetByCharacterFullName = function() return { bank = { { { itemID = 2589, itemCount = 20, itemLink = "[Linen Cloth]" } } },
        bankTabs = { { name = "Tab 1", slots = { { itemID = 2589, itemCount = 20 } } } } } end,
} }

Baganator = { API = {
    RegisterRegion = function(_, id, _, _, frame) baganator.regions[id] = frame end,
    RegisterCornerWidget = function(_, id, onUpdate, onInit) baganator.corners[id] = { onUpdate = onUpdate, onInit = onInit } end,
    RegisterJunkPlugin = function(_, id, fn) baganator.junk[id] = fn end,
    RegisterUpgradePlugin = function(_, id, fn) baganator.upgrade = fn end,
    RequestItemButtonsRefresh = function() baganator.refreshes = baganator.refreshes + 1 end,
} }

local ns = {}
for line in io.lines("packRat.toc") do
    if line:match("%.lua$") then
        assert(loadfile(line))("packRat", ns)
    end
end
local eventFrame
for _, f in ipairs(allFrames) do
    if rawget(f, "events") and f.events.PLAYER_LOGIN then eventFrame = f end
end
local function fire(event, ...) eventFrame.scripts.OnEvent(eventFrame, event, ...) end

local function check(cond, msg)
    if not cond then error(msg, 2) end
end

-- Verdicts saved before the claude -> agent rename.
packRatDB = { chars = { ["Tester-Mirage"] = { verdicts = {
    [4444] = { action = "toss", source = "claude" },
    [4445] = { action = "keep", source = "manual", claude = { action = "toss", source = "claude" } },
} } } }
fire("ADDON_LOADED", "packRat")
fire("PLAYER_LOGIN")
runTimers()
check(ns.char.verdicts[4444].source == "agent", "old agent verdict migrated")
check(ns.char.verdicts[4445].agent.source == "agent" and ns.char.verdicts[4445].claude == nil, "nested verdict migrated")

check(#ns.items == 6, "6 items scanned, got " .. #ns.items)
check(ns.statuses[9978].action == "keep", "detector kept while Gahz'ridian is in the log: " .. ns.statuses[9978].reason)
check(ns.statuses[9978].reason:find("Handed out"), "detector is handed out by its quest")
check(ns.statuses[750].action == "keep", "wolf pelt kept for an active quest")
check(ns.statuses[751].action == "flag", "letter flagged for the gray quest (under a collapsed header)")
check(ns.statuses[752].action == "toss", "gray tossed")
check(ns.statuses[2589].action == "unsorted", "cloth left for agent")
check(not expanded, "collapsed header collapsed again")
check(selection == 2, "quest selection restored")

-- Baganator hooks
check(baganator.regions.packrat, "bag button registered")
check(baganator.junk.packrat(0, 3, 752) == true and baganator.junk.packrat(0, 1, 750) == false, "junk plugin")
local corner = baganator.corners.packrat
local cf = corner.onInit(newFrame("Button"))
check(corner.onUpdate(cf, { itemID = 751 }) == true and corner.onUpdate(cf, { itemID = 750 }) == false, "corner widget")

-- Tooltip line
GameTooltip:Fire("OnTooltipSetItem")
check(tostring(rawget(GameTooltip, "lastLine")):find("Needed for Wolves of the Wood"), "tooltip line")

-- Window + export round trip
SlashCmdList.PACKRAT("")
check(_G.packRatWindow:IsShown(), "window open")
SlashCmdList.PACKRAT("export")
check(_G.packRatExport and _G.packRatExport:IsShown(), "export window")
local doc = ns.JSON.Decode(ns.Export.ToJSON(ns.Snapshot()))
check(doc.character.level == 30 and doc.character.professions[1].name == "Blacksmithing" and #doc.character.professions == 2, "professions read under a collapsed header")
check(not skillsExpanded, "skill header collapsed again")
check(#doc.quests == 3 and #doc.items == 6 and doc.equipped[1].name == "Green Hat", "quests/items/equipped in export")

SlashCmdList.PACKRAT("import")
local reply = '```json\n{"format":"packrat-verdicts","version":1,"summary":"tidy","items":[{"id":2589,"action":"toss","reason":"No tailoring needed"},{"id":750,"action":"toss","reason":"meh"},{"id":6948,"action":"toss"}]}\n```'
local result = assert(ns.Export.ReadVerdicts(reply))
ns.ImportVerdicts(result)
check(ns.statuses[2589].action == "toss", "agent toss applied")
check(ns.statuses[750].action == "flag", "agent toss on active quest item downgraded")
check(ns.statuses[6948].action == "keep", "hearthstone protected")

-- Manual choice wins, and clearing it restores agent's verdict
ns.SetManual(2589, "keep")
check(ns.statuses[2589].action == "keep" and ns.statuses[2589].source == "manual", "manual keep")
ns.SetManual(2589, nil)
check(ns.statuses[2589].action == "toss" and ns.statuses[2589].source == "agent", "agent verdict restored")

-- Delete next takes the no-value / cheapest stack first, then Sell needs a vendor
SlashCmdList.PACKRAT("next")
runTimers()
check(bag[3] == nil or bag[4] == nil, "a tossed stack was deleted")
SlashCmdList.PACKRAT("sell")
check(chat[#chat]:find("vendor"), "sell needs a vendor")
fire("MERCHANT_SHOW")
SlashCmdList.PACKRAT("sell")
runTimers()
check(bag[3] == nil and bag[4] == nil, "tossed items sold")
check(bag[1] and bag[2] and bag[5], "kept and flagged items untouched")

-- Level up turns the pelt quest gray at a fixed gap
SlashCmdList.PACKRAT("gap 5")
player.level = 36
fire("PLAYER_LEVEL_UP")
runTimers()
check(ns.statuses[750].action == "flag", "pelt flagged after outleveling its quest")

-- Export: bank and other characters via Syndicator
bag[4] = { itemID = 2589, name = "Linen Cloth", count = 10, quality = 1, classID = 7, price = 13 }
local doc2 = ns.JSON.Decode(ns.Export.ToJSON(ns.Snapshot()))
check(doc2.bank and doc2.bank[1].count == 40, "bank exported")
local linen
for _, it in ipairs(doc2.items) do if it.id == 2589 then linen = it end end
check(linen and linen.elsewhere.bank == 40 and linen.elsewhere.alts == 5, "elsewhere counts")

-- Minimap / LDB feed
check(broker.obj and broker.icon, "broker and minimap icon registered")
broker.obj.OnTooltipShow(GameTooltip)
check(type(broker.obj.text) == "string", "broker text")
check(baganator.upgrade ~= nil, "upgrade plugin registered")

-- Never-toss list via the slash command, then auto-sell skips it
fire("MERCHANT_CLOSED")
ns.Rescan()
ns.SetManual(2589, "toss")
SlashCmdList.PACKRAT("protect |cffffffff|Hitem:2589::|h[Linen Cloth]|h|r")
check(ns.statuses[2589].action == "keep" and ns.statuses[2589].source == "protected", "protected beats your toss")
SlashCmdList.PACKRAT("autosell")
fire("MERCHANT_SHOW")
runTimers()
check(bag[4] ~= nil, "auto-sell left the protected item alone")
SlashCmdList.PACKRAT("protect 2589")
runTimers()
check(ns.statuses[2589].action == "toss", "unprotected again")
fire("MERCHANT_CLOSED")
fire("MERCHANT_SHOW")
runTimers()
check(bag[4] == nil, "auto-sold your own toss")
check(ns.char.history[1].kind == "sold" and ns.char.history[1].id == 2589, "history records the sale")
fire("MERCHANT_CLOSED")

-- Turn in Gahz'ridian: the prompt lists the detector it handed out
for i, e in ipairs(log) do if e[5] == 3161 then table.remove(log, i) break end end
doneQuests[3161] = true
fire("QUEST_LOG_UPDATE")
runTimers()
check(_G.packRatPrompt and _G.packRatPrompt:IsShown(), "turn-in prompt shown")
check(ns.statuses[9978].action == "toss", "detector tossable after turn-in: " .. ns.statuses[9978].reason)
-- Delete from the prompt's first row
local promptRow
for _, f in ipairs(allFrames) do
    if rawget(f, "parent") == _G.packRatPrompt and rawget(f, "item") then promptRow = f end
end
check(promptRow and promptRow.item.id == 9978, "prompt row holds the detector")
ns.DeleteSlot(promptRow.item, promptRow.item.slots[1])
runTimers()
check(bag[6] == nil, "detector deleted from the prompt")
check(not _G.packRatPrompt:IsShown(), "prompt closes when nothing is left")
check(ns.char.history[1].kind == "deleted", "history records the delete")

-- Options, history and debug windows
SlashCmdList.PACKRAT("options")
check(_G.packRatOptions:IsShown(), "options window")
SlashCmdList.PACKRAT("history")
check(_G.packRatExport:IsShown(), "history window")
SlashCmdList.PACKRAT("debug")
local report = ns.Debug.Report()
check(report:find("C_Item.DeleteItem") and report:find("1.60.1"), "debug report")

SlashCmdList.PACKRAT("clear")
SlashCmdList.PACKRAT("help")
fire("QUEST_LOG_UPDATE")
runTimers()
print("smoke OK")

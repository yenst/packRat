-- Builds QuestData.lua (item -> quest links) from a QuestieDB checkout.
--   lua5.1 tools/build-questdata.lua /path/to/QuestieDB [Forever]
--
-- Only data is read: every QuestieDB file runs in a sandbox without io, os,
-- loadfile or require, and with stubs for the Questie modules it imports.
-- Layer order follows QuestieDB's Static Corrections for Forever:
--   raw base -> inherited legacy -> generated delta-base -> traces -> authored fixes.
-- Dynamic (per-character) corrections are skipped.
--
-- The output is derived from QuestieDB, which is GPL-3.0; so is packRat.
local root, flavor = arg[1], arg[2] or "Forever"
assert(root, "usage: lua5.1 tools/build-questdata.lua /path/to/QuestieDB [Forever]")

-- Sandbox -------------------------------------------------------------------

-- A value that absorbs anything: index, call, arithmetic, concatenation.
local stub
local stubMeta = {}
stubMeta.__index = function() return stub end
stubMeta.__call = function() return stub end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat" }) do
    stubMeta[op] = function() return stub end
end
stub = setmetatable({}, stubMeta)
local function isStub(v) return rawequal(v, stub) end

-- Enums whose values don't matter here (races, classes, zones...): any name is 0.
local function zeroEnum() return setmetatable({}, { __index = function() return 0 end }) end

-- Race and class masks, as QuestieDB's Forever enums define them (races are
-- 2^(raceID-1); Skyborne uses bits 32/33). Unknown names fall back to 0 = all,
-- which only ever widens a quest's audience.
local function enum(t) return setmetatable(t, { __index = function() return 0 end }) end
local RACE = { HUMAN = 1, ORC = 2, DWARF = 4, NIGHT_ELF = 8, UNDEAD = 16, TAUREN = 32, GNOME = 64, TROLL = 128,
    SKYBORNE_ALLIANCE = 4294967296, SKYBORNE_HORDE = 8589934592 }
RACE.ALL_ALLIANCE = RACE.HUMAN + RACE.DWARF + RACE.NIGHT_ELF + RACE.GNOME + RACE.SKYBORNE_ALLIANCE
RACE.ALL_HORDE = RACE.ORC + RACE.UNDEAD + RACE.TAUREN + RACE.TROLL + RACE.SKYBORNE_HORDE
local CLASS = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256,
    DRUID = 1024, ALL_CLASSES = 1503 }

local QuestieDB = {
    raceKeys = enum(RACE), classKeys = enum(CLASS), sortKeys = zeroEnum(), specialFlags = zeroEnum(),
    factionIDs = zeroEnum(), itemClasses = zeroEnum(), npcRanks = zeroEnum(), npcFlags = zeroEnum(),
}
local modules = {
    QuestieDB = QuestieDB,
    ZoneDB = { zoneIDs = zeroEnum() },
}
local created = {}
local QuestieLoader = {
    CreateModule = function(_, name)
        created[name] = created[name] or {}
        return created[name]
    end,
    ImportModule = function(_, name)
        return modules[name] or created[name] or stub
    end,
}

local SAFE = { "pairs", "ipairs", "next", "type", "tostring", "tonumber", "select", "unpack", "error", "assert",
    "pcall", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal" }

local function sandbox()
    local env = { QuestieLoader = QuestieLoader, string = string, table = table, math = math }
    for _, name in ipairs(SAFE) do
        env[name] = _G[name]
    end
    -- Unknown globals (Questie, UnitFactionGroup, ...) become stubs.
    return setmetatable(env, { __index = function() return stub end })
end

local function readFile(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function run(path, ...)
    local chunk = assert(loadstring(readFile(path), "@" .. path))
    setfenv(chunk, sandbox())
    return chunk(...)
end

local function loadData(text, name)
    local chunk = assert(loadstring(text, name))
    setfenv(chunk, sandbox())
    return chunk()
end

-- Add / remove aliases: index + 1000 and index - 1000 (QuestieDB ADR 0016).
local function withOps(keys)
    local out = {}
    for name, index in pairs(keys) do
        out[name] = index
        out[name .. "_add"] = index + 1000
        out[name .. "_remove"] = index - 1000
    end
    return out
end

-- Base data -----------------------------------------------------------------

local lower = flavor:lower()
run(string.format("%s/data/%s/%sQuestDB.lua", root, flavor, lower))
run(string.format("%s/data/%s/%sItemDB.lua", root, flavor, lower))
local quests = loadData(QuestieDB.questData, "questData")
local items = loadData(QuestieDB.itemData, "itemData")
local Q, I = QuestieDB.questKeys, QuestieDB.itemKeys
QuestieDB.questKeys, QuestieDB.itemKeys = withOps(Q), withOps(I)

-- Merging the fields packRat uses ---------------------------------------------

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function rowKey(row)
    return type(row) == "table" and row[1] or row
end

-- Grouped fields (startedBy, objectives): apply within each supplied group.
local function addGrouped(target, operand)
    target = target or {}
    for group, values in pairs(operand) do
        target[group] = target[group] or {}
        for _, v in ipairs(values) do
            local found = false
            for _, existing in ipairs(target[group]) do
                if rowKey(existing) == rowKey(v) then found = true end
            end
            if not found then table.insert(target[group], v) end
        end
    end
    return target
end

local function removeGrouped(target, operand)
    if not target then return nil end
    for group, values in pairs(operand) do
        local kept = {}
        for _, existing in ipairs(target[group] or {}) do
            local drop = false
            for _, v in ipairs(values) do
                if rowKey(existing) == rowKey(v) then drop = true end
            end
            if not drop then table.insert(kept, existing) end
        end
        target[group] = kept
    end
    return target
end

local function addList(target, operand)
    target = target or {}
    for _, v in ipairs(operand) do
        if not contains(target, v) then table.insert(target, v) end
    end
    return target
end

local function removeList(target, operand)
    if not target then return nil end
    local kept = {}
    for _, v in ipairs(target) do
        if not contains(operand, v) then table.insert(kept, v) end
    end
    return kept
end

local QUEST_SCALARS = { [Q.name] = "string", [Q.questLevel] = "number", [Q.sourceItemId] = "number", [Q.specialFlags] = "number",
    [Q.requiredRaces] = "number", [Q.requiredClasses] = "number" }
local QUEST_GROUPED = { [Q.startedBy] = true, [Q.objectives] = true }
local QUEST_LISTS = { [Q.requiredSourceItems] = true }

local function applyQuest(id, fix)
    local row = quests[id] or {}
    quests[id] = row
    for key, value in pairs(fix) do
        if type(key) == "number" and not isStub(value) then
            local base = key > 500 and key - 1000 or key < -500 and key + 1000 or key
            local op = key > 500 and "add" or key < -500 and "remove" or "set"
            if QUEST_SCALARS[base] and op == "set" then
                if type(value) == QUEST_SCALARS[base] then row[base] = value end
            elseif (QUEST_GROUPED[base] or QUEST_LISTS[base]) and type(value) == "table" then
                if op == "set" then
                    row[base] = value
                elseif QUEST_GROUPED[base] then
                    row[base] = (op == "add" and addGrouped or removeGrouped)(row[base], value)
                else
                    row[base] = (op == "add" and addList or removeList)(row[base], value)
                end
            end
        end
    end
end

local function applyItem(id, fix)
    local value = fix[I.startQuest]
    if type(value) == "number" then
        items[id] = items[id] or {}
        items[id][I.startQuest] = value ~= 0 and value or nil
    end
end

local function applyLayer(path, module, method, apply)
    created[module] = nil
    run(root .. "/src/corrections/" .. flavor .. "/" .. path)
    local m = assert(created[module], "module " .. module .. " not created by " .. path)
    local ok, fixes = pcall(m[method], m)
    if not ok then
        error(path .. ": " .. tostring(fixes))
    end
    local n = 0
    for id, fix in pairs(fixes or {}) do
        if type(id) == "number" and type(fix) == "table" then
            apply(id, fix)
            n = n + 1
        end
    end
    io.stderr:write(string.format("  %-45s %5d rows\n", path, n))
end

io.stderr:write("Applying " .. flavor .. " corrections:\n")
applyLayer("legacy/classicQuestFixes.lua", "QuestieQuestFixes", "Load", applyQuest)
applyLayer("legacy/classicItemFixes.lua", "QuestieItemFixes", "Load", applyItem)
applyLayer("legacy/itemStartFixes.lua", "QuestieItemStartFixes", "LoadAutomaticQuestStarts", applyItem)
applyLayer("generated/foreverBaseQuest.lua", "ForeverBaseQuest", "Load", applyQuest)
applyLayer("generated/foreverBaseItem.lua", "ForeverBaseItem", "Load", applyItem)
applyLayer("traces/foreverQuestTraces.lua", "ForeverQuestTraces", "Load", applyQuest)
applyLayer("traces/foreverQuestRelationTraces.lua", "ForeverQuestRelationTraces", "Load", applyQuest)
applyLayer("traces/foreverItemTraces.lua", "ForeverItemTraces", "Load", applyItem)
applyLayer("foreverQuestFixes.lua", "ForeverQuestFixes", "Load", applyQuest)
applyLayer("foreverItemFixes.lua", "ForeverItemFixes", "Load", applyItem)

-- Item -> quest links ---------------------------------------------------------

-- uses: the quest needs the item (objective or required source item).
-- given: the quest only hands it out when you accept it.
local uses, given, starts, usedQuests = {}, {}, {}, {}
local function link(map, itemID, questID)
    if type(itemID) ~= "number" or itemID <= 0 then return end
    map[itemID] = map[itemID] or {}
    if not contains(map[itemID], questID) then table.insert(map[itemID], questID) end
    usedQuests[questID] = true
end

for questID, row in pairs(quests) do
    if type(row[Q.name]) == "string" then
        local objectives = row[Q.objectives]
        for _, objective in ipairs(type(objectives) == "table" and type(objectives[3]) == "table" and objectives[3] or {}) do
            link(uses, rowKey(objective), questID)
        end
        for _, itemID in ipairs(type(row[Q.requiredSourceItems]) == "table" and row[Q.requiredSourceItems] or {}) do
            link(uses, itemID, questID)
        end
        local source = row[Q.sourceItemId]
        if type(source) == "number" and not (uses[source] and contains(uses[source], questID)) then
            link(given, source, questID)
        end
        local startedBy = row[Q.startedBy]
        for _, itemID in ipairs(type(startedBy) == "table" and type(startedBy[3]) == "table" and startedBy[3] or {}) do
            if type(itemID) == "number" then
                starts[itemID] = starts[itemID] or questID
                usedQuests[questID] = true
            end
        end
    end
end
for itemID, row in pairs(items) do
    local questID = row[I.startQuest]
    if type(questID) == "number" and quests[questID] and type(quests[questID][Q.name]) == "string" then
        starts[itemID] = starts[itemID] or questID
        usedQuests[questID] = true
    end
end

-- Output ------------------------------------------------------------------------

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local commit = io.popen and io.popen('git -C "' .. root .. '" rev-parse --short HEAD 2>/dev/null'):read("*l") or "?"
local out = {}
local function w(s) out[#out + 1] = s end
w("-- GENERATED by tools/build-questdata.lua from QuestieDB " .. flavor .. " @ " .. tostring(commit) .. ". Do not edit.")
w("-- Data derived from QuestieDB (https://github.com/Questie/QuestieDB), GPL-3.0.")
w("local _, ns = ...")
w("ns.QuestData = {")
w(string.format("source = %q,", "QuestieDB " .. flavor .. " @ " .. tostring(commit)))
w("-- [questID] = { name, level, repeatable (1/0), raceMask (0 = all), classMask (0 = all) }")
w("quests = {")
local nQuests = 0
for _, id in ipairs(sortedKeys(usedQuests)) do
    local row = quests[id]
    local flags = row[Q.specialFlags]
    local repeatable = type(flags) == "number" and flags % 2 == 1 and 1 or 0
    local races = tonumber(row[Q.requiredRaces]) or 0
    local classes = tonumber(row[Q.requiredClasses]) or 0
    local tail = ""
    if classes ~= 0 then
        tail = string.format(",%d,%.0f,%d", repeatable, races, classes)
    elseif races ~= 0 then
        tail = string.format(",%d,%.0f", repeatable, races)
    elseif repeatable == 1 then
        tail = ",1"
    end
    w(string.format("[%d]={%q,%d%s},", id, row[Q.name], tonumber(row[Q.questLevel]) or 0, tail))
    nQuests = nQuests + 1
end
w("},")
w("-- [itemID] = { questIDs that need or hand out this item }")
w("uses = {")
local nUses = 0
for _, id in ipairs(sortedKeys(uses)) do
    table.sort(uses[id])
    w(string.format("[%d]={%s},", id, table.concat(uses[id], ",")))
    nUses = nUses + 1
end
w("},")
w("-- [itemID] = { questIDs that only hand out this item when accepted }")
w("given = {")
local nGiven = 0
for _, id in ipairs(sortedKeys(given)) do
    table.sort(given[id])
    w(string.format("[%d]={%s},", id, table.concat(given[id], ",")))
    nGiven = nGiven + 1
end
w("},")
w("-- [itemID] = questID this item starts")
w("starts = {")
local nStarts = 0
for _, id in ipairs(sortedKeys(starts)) do
    w(string.format("[%d]=%d,", id, starts[id]))
    nStarts = nStarts + 1
end
w("},")
w("}")
io.write(table.concat(out, "\n"), "\n")
io.stderr:write(string.format("%d quests, %d needed-item links, %d handed-out items, %d quest starters\n", nQuests, nUses, nGiven, nStarts))

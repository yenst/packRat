local _, ns = ...

-- Pure decision logic, no WoW API calls: which items to keep, use, flag or
-- toss. Used by the bag scan and by the tests.
--
-- Priority for an item's status:
--   0. your never-toss list ("protected"), which nothing overrides
--   1. your own choice in the packRat window ("manual")
--   2. the AI agent's imported verdict ("agent"), except that a toss for a quest
--      item is turned into a flag unless the quest data shows it's done
--   3. the built-in rules below ("rule")
--   4. nothing: the item is "unsorted" until you or the agent decide
local Rules = {}
ns.Rules = Rules

Rules.ACTIONS = { "keep", "use", "flag", "toss" }
Rules.VALID = { keep = true, use = true, flag = true, toss = true }

-- Never tossed, whatever a verdict says.
Rules.PROTECTED = {
    [6948] = true, -- Hearthstone
}

Rules.QUALITY_POOR, Rules.QUALITY_RARE = 0, 3
Rules.CLASS_QUEST = 12

-- Levels below you at which a quest turns gray. Only an approximation for
-- clients without GetQuestGreenRange(); the game's value is used when present.
function Rules.GreenRange(level)
    if level <= 5 then
        return 5
    elseif level <= 39 then
        return 5 + math.floor(level / 10)
    elseif level <= 59 then
        return 5 + math.floor(level / 5) - 4
    end
    return 12
end

-- "red" | "orange" | "yellow" | "green" | "gray", like the quest log colours.
function Rules.QuestColor(questLevel, playerLevel, greenRange)
    local diff = questLevel - playerLevel
    if diff >= 5 then
        return "red"
    elseif diff >= 3 then
        return "orange"
    elseif diff >= -2 then
        return "yellow"
    elseif -diff <= (greenRange or Rules.GreenRange(playerLevel)) then
        return "green"
    end
    return "gray"
end

-- gap = 0: low means gray. gap > 0: low means at least `gap` levels below you.
function Rules.IsLowQuest(quest, playerLevel, gap, greenRange)
    if not quest.level or quest.level <= 0 then
        return false
    end
    if gap and gap > 0 then
        return playerLevel - quest.level >= gap
    end
    return Rules.QuestColor(quest.level, playerLevel, greenRange) == "gray"
end

local function questLabel(quest)
    return string.format("%s (%d)", quest.title or quest[1] or "?", quest.level or quest[2] or 0)
end

-- mask contains bit? Masks can exceed 32 bits (Forever's Skyborne races use
-- bits 32/33), so this avoids the client's 32-bit bit library.
function Rules.HasBit(mask, bit)
    return math.floor(mask / bit) % 2 == 1
end

-- Can this character take the quest at all? dbQuest = { name, level,
-- repeatable, raceMask, classMask }; 0 or missing = everyone.
function Rules.Eligible(dbQuest, ctx)
    local races, classes = dbQuest[4] or 0, dbQuest[5] or 0
    if races ~= 0 and ctx.raceBit and not Rules.HasBit(races, ctx.raceBit) then
        return false
    end
    if classes ~= 0 and ctx.classBit and not Rules.HasBit(classes, ctx.classBit) then
        return false
    end
    return true
end

-- Every quest the item belongs to, from the quest database (needs it, hands
-- it out, or is started by it) and from name matches in your quest log.
-- Quests your race or class can't take are left out unless they're in your log.
-- Returns a list of { id, title, level, inLog, done, repeatable, starts, given }.
function Rules.QuestLinks(item, ctx)
    local links, seen = {}, {}
    local db = ctx.db
    local function add(questID, role)
        local link = seen[questID]
        if link then
            if role == "starts" then link.starts = true end
            if role == "uses" then link.given = false end
            return
        end
        local logQuest = ctx.quests[questID]
        local dbQuest = db and db.quests[questID]
        if not logQuest and dbQuest and not Rules.Eligible(dbQuest, ctx) then
            return
        end
        link = {
            id = questID,
            title = logQuest and logQuest.title or dbQuest and dbQuest[1] or ("quest " .. questID),
            level = logQuest and logQuest.level or dbQuest and dbQuest[2] or 0,
            inLog = logQuest ~= nil,
            repeatable = dbQuest and dbQuest[3] == 1 or false,
            starts = role == "starts",
            given = role == "given",
        }
        link.done = not link.inLog and ctx.isDone ~= nil and ctx.isDone(questID) or false
        seen[questID] = link
        links[#links + 1] = link
    end
    local known = false
    if db then
        for _, questID in ipairs(db.uses[item.id] or {}) do
            add(questID, "uses")
        end
        for _, questID in ipairs(db.given and db.given[item.id] or {}) do
            add(questID, "given")
        end
        if db.starts[item.id] then
            add(db.starts[item.id], "starts")
        end
        known = db.uses[item.id] ~= nil or db.starts[item.id] ~= nil or (db.given ~= nil and db.given[item.id] ~= nil)
    end
    for _, questID in ipairs(item.quests or {}) do
        add(questID, "uses")
    end
    return links, known
end

local function isLow(link, ctx)
    return Rules.IsLowQuest(link, ctx.level, ctx.gap, ctx.greenRange)
end

-- The quest part of the rules. Returns a judgement or nil when the item has
-- nothing to do with quests.
local function judgeQuests(item, ctx)
    local links, known = Rules.QuestLinks(item, ctx)
    item.questLinks = links
    -- 1. A quest in your log uses it.
    local active, low
    for _, link in ipairs(links) do
        if link.inLog then
            if isLow(link, ctx) then
                low = low or link
            else
                active = active or link
            end
        end
    end
    if active then
        local verb = active.given and "Handed out by " or "Needed for "
        return { action = "keep", reason = verb .. questLabel(active), quest = true }
    elseif low then
        return { action = "flag", reason = "Low-level quest: " .. questLabel(low) .. ", you're " .. ctx.level, lowQuest = true }
    end
    -- Only quest-type items are judged by the quests they belong to; a stack
    -- of cloth that some old quest asked for is not junk because of it.
    local questish = item.questItem or item.startsQuest or (ctx.db and ctx.db.starts[item.id] ~= nil)
    if not (known and questish) then
        if item.questItem then
            return { action = "flag", reason = "Quest item packRat has no quest data for" }
        elseif item.startsQuest then
            return { action = "flag", reason = "Starts a quest: accept it or toss it" }
        end
        return nil
    end
    -- 2. None of its quests is in your log: done, or still open?
    local open, openLow = {}, true
    for _, link in ipairs(links) do
        if not link.done or link.repeatable then
            open[#open + 1] = link
            openLow = openLow and isLow(link, ctx)
        end
    end
    if #open == 0 then
        if #links == 0 then
            return { action = "flag", reason = "Its quests are for another race or class", otherFaction = true }
        end
        local names = {}
        for i = 1, math.min(2, #links) do
            names[#names + 1] = links[i].title
        end
        local verb = links[1].given and "Handed out by a done quest: " or "Quest done: "
        return { action = "toss", reason = verb .. table.concat(names, ", ") .. (#links > 2 and "..." or ""), questDone = true }
    end
    local first = open[1]
    if first.starts and #open == 1 then
        -- A starter you can trade (crafting writs, BoE letters) is worth
        -- selling or giving away rather than only accepting.
        local tradeable = not item.bound
        if openLow then
            return { action = "flag", reason = "Starts low-level quest " .. questLabel(first) .. ", you're " .. ctx.level, lowQuest = true, tradeable = tradeable }
        elseif tradeable then
            return { action = "flag", reason = "Starts " .. questLabel(first) .. "; tradeable, sell or give it away", startsOpen = true, tradeable = true }
        end
        return { action = "flag", reason = "Starts " .. questLabel(first) .. ": accept it", startsOpen = true }
    end
    if openLow then
        return { action = "flag", reason = "For low-level quest " .. questLabel(first) .. ", not in your log", lowQuest = true }
    end
    return { action = "flag", reason = "For " .. questLabel(first) .. ", not in your log yet", openQuest = true }
end

-- Armor and weapon types each class can ever use (Classic rules). Item class
-- 4 = armor, 2 = weapon; subclass IDs as in GetItemInfo. Anything not listed
-- for any class (misc, fishing poles...) counts as usable.
local ARMOR, WEAPON = 4, 2
local ARMOR_TYPES = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shield", [7] = "Libram", [8] = "Idol", [9] = "Totem" }
local WEAPON_TYPES = {
    [0] = "One-Handed Axe", [1] = "Two-Handed Axe", [2] = "Bow", [3] = "Gun", [4] = "One-Handed Mace", [5] = "Two-Handed Mace",
    [6] = "Polearm", [7] = "One-Handed Sword", [8] = "Two-Handed Sword", [10] = "Staff", [13] = "Fist Weapon", [15] = "Dagger",
    [16] = "Thrown", [18] = "Crossbow", [19] = "Wand",
}
local function set(list)
    local t = {}
    for _, v in ipairs(list) do t[v] = true end
    return t
end
Rules.PROFICIENCY = {
    WARRIOR = { armor = set({ 1, 2, 3, 4, 6 }), weapon = set({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }) },
    PALADIN = { armor = set({ 1, 2, 3, 4, 6, 7 }), weapon = set({ 0, 1, 4, 5, 7, 8 }) },
    HUNTER = { armor = set({ 1, 2, 3 }), weapon = set({ 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }) },
    ROGUE = { armor = set({ 1, 2 }), weapon = set({ 2, 3, 4, 7, 13, 15, 16, 18 }) },
    PRIEST = { armor = set({ 1 }), weapon = set({ 4, 10, 15, 19 }) },
    SHAMAN = { armor = set({ 1, 2, 3, 6, 9 }), weapon = set({ 0, 1, 4, 5, 10, 13, 15 }) },
    MAGE = { armor = set({ 1 }), weapon = set({ 7, 10, 15, 19 }) },
    WARLOCK = { armor = set({ 1 }), weapon = set({ 7, 10, 15, 19 }) },
    DRUID = { armor = set({ 1, 2, 8 }), weapon = set({ 4, 5, 10, 13, 15 }) },
}

-- nil if the class can use it, else the type name it can't use.
function Rules.Unusable(item, class)
    if item.classes and class and not item.classes[class] then
        return "class-restricted"
    end
    local prof = class and Rules.PROFICIENCY[class]
    if not prof or not item.equipLoc then
        return nil
    end
    if item.classID == ARMOR and ARMOR_TYPES[item.subClassID] and not prof.armor[item.subClassID] then
        return ARMOR_TYPES[item.subClassID]
    elseif item.classID == WEAPON and WEAPON_TYPES[item.subClassID] and not prof.weapon[item.subClassID] then
        return WEAPON_TYPES[item.subClassID]
    end
end

-- The built-in rules. ctx = { level, quests = { [questID] = log quest }, gap,
-- greenRange, tossGrays, db = ns.QuestData or nil, isDone = function(questID),
-- raceBit, classBit, class = "PALADIN" }. Returns { action, reason, ... } or nil.
function Rules.Judge(item, ctx)
    local quest = judgeQuests(item, ctx)
    if quest then
        return quest
    end
    if item.sets and #item.sets > 0 then
        return { action = "keep", reason = "In equipment set " .. table.concat(item.sets, ", "), inSet = true }
    end
    local cannot = Rules.Unusable(item, ctx.class)
    if cannot then
        local what = cannot == "class-restricted" and "Your class can't use it" or ("Your class can't use " .. cannot)
        if item.bound then
            return { action = "toss", reason = what, unusable = true }
        end
        return { action = "flag", reason = what .. "; sell it on the auction house", unusable = true }
    end
    if item.rxpJunk then
        return { action = "toss", reason = "Marked as junk in RestedXP" }
    elseif item.quality == Rules.QUALITY_POOR and ctx.tossGrays and not item.noValue then
        return { action = "toss", reason = "Gray vendor trash" }
    end
end

function Rules.IsProtected(itemID, ctx)
    return Rules.PROTECTED[itemID] or (ctx.protected ~= nil and ctx.protected[itemID] == true)
end

-- Final status for one item. `verdict` is the stored entry for its itemID
-- ({ action, reason, source }) or nil.
function Rules.Status(item, verdict, ctx)
    local rule = Rules.Judge(item, ctx)
    -- Your never-toss list beats everything, your own Toss included.
    if Rules.IsProtected(item.id, ctx) then
        return { action = "keep", reason = "On your never-toss list", source = "protected" }
    end
    local status
    if verdict and verdict.source == "manual" then
        status = { action = verdict.action, reason = verdict.reason or "Your choice", source = "manual" }
    elseif verdict then
        status = { action = verdict.action, reason = verdict.reason or "", source = "agent" }
        -- The agent never tosses a quest item on its own word: only when the
        -- quest data confirms every quest it belongs to is done. Anything
        -- else (needed, low-level, open, unknown) becomes a flag. Tradeable
        -- quest starters and the other safeguards follow the same idea.
        local guarded = rule and (rule.quest or rule.lowQuest or rule.openQuest or (rule.startsOpen and not rule.tradeable) or rule.inSet)
        if status.action == "toss" and guarded then
            status = { action = "flag", reason = "Agent says toss, but: " .. rule.reason, source = "agent" }
        elseif status.action == "toss" and item.questItem and not (rule and (rule.questDone or rule.otherFaction)) then
            status = { action = "flag", reason = "Agent says toss; quest data can't confirm it's done", source = "agent" }
        end
    elseif rule then
        status = { action = rule.action, reason = rule.reason, source = "rule" }
    else
        status = { action = "unsorted", reason = "", source = "none" }
    end
    return status
end

-- Marks items an objective or quest text mentions by name. `items` is the
-- list of grouped items, `quests` the quest list. Fills item.quests (IDs)
-- and quest.items (item IDs).
function Rules.LinkQuests(items, quests)
    for _, quest in ipairs(quests) do
        quest.items = {}
    end
    for _, item in ipairs(items) do
        item.quests = {}
        local name = item.name and item.name:lower()
        if name and #name >= 4 then
            for _, quest in ipairs(quests) do
                local hit = false
                for _, objective in ipairs(quest.objectives or {}) do
                    if objective:lower():find(name, 1, true) then
                        hit = true
                    end
                end
                if not hit and quest.text and quest.text:lower():find(name, 1, true) then
                    hit = true
                end
                if hit then
                    item.quests[#item.quests + 1] = quest.id
                    quest.items[#quest.items + 1] = item.id
                end
            end
        end
    end
end

-- The next stack "Delete next" should remove: only tossed items below rare,
-- items with no vendor value first, then the cheapest stack.
function Rules.NextToDelete(items, statuses, protected)
    local best, bestSlot, bestValue
    for _, item in ipairs(items) do
        local status = statuses[item.id]
        if status and status.action == "toss" and (item.quality or 0) < Rules.QUALITY_RARE
            and not Rules.IsProtected(item.id, { protected = protected }) then
            for _, slot in ipairs(item.slots) do
                local value = item.noValue and -1 or (item.sellPrice or 0) * slot.count
                if not bestValue or value < bestValue then
                    best, bestSlot, bestValue = item, slot, value
                end
            end
        end
    end
    return best, bestSlot
end

-- Stacks to sell at a vendor: tossed items that have a sell price.
-- noAgent = true skips tosses that only the agent decided (used by auto-sell).
function Rules.ToSell(items, statuses, limit, protected, noAgent)
    local list = {}
    for _, item in ipairs(items) do
        local status = statuses[item.id]
        if status and status.action == "toss" and not item.noValue and (item.sellPrice or 0) > 0
            and not Rules.IsProtected(item.id, { protected = protected })
            and not (noAgent and status.source == "agent") then
            for _, slot in ipairs(item.slots) do
                if #list < limit then
                    list[#list + 1] = { item = item, slot = slot }
                end
            end
        end
    end
    return list
end

function Rules.Counts(items, statuses)
    local counts = { keep = 0, use = 0, flag = 0, toss = 0, unsorted = 0, total = #items }
    for _, item in ipairs(items) do
        local status = statuses[item.id]
        local action = status and status.action or "unsorted"
        counts[action] = (counts[action] or 0) + 1
    end
    return counts
end

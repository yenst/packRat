local _, ns = ...

-- The export you paste into the agent, and the verdict JSON the agent pastes back.
--
-- Export: { _instructions, format = "packrat-export", version, exportedAt,
--   character = { name, realm, class, race, level, xp, xpMax, restedXP, money,
--     professions = [ { name, rank, max } ], bagSlots = { free, total }, rxpGuide },
--   settings = { lowQuestGap, tossGrays },
--   quests = [ { id, title, level, color, complete, objectives, summary, items } ],
--   equipped = [ { slot, id, name, quality, ilvl, reqLevel, subType } ],
--   bank = [ { id, name, count, quality } ] (from Syndicator, if installed),
--   items = [ { id, name, count, stacks, quality, type, subType, ilvl, reqLevel,
--     equipLoc, sellPrice, bound, unique, questItem, startsQuest, useText,
--     tooltip, questLinks = [ { id, title, level, state, repeatable, startsIt, handedOut } ], rxpJunk,
--     equipmentSets, neverToss, elsewhere = { bank, mail, alts }, pawnUpgrade,
--     current = { action, reason, source } } ] }
--
-- Verdicts: { format = "packrat-verdicts", version = 1, summary?,
--   items = [ { id, action = "keep"|"use"|"flag"|"toss", reason } ] }
local Export = {}
ns.Export = Export

local JSON = ns.JSON

Export.FORMAT = "packrat-export"
Export.REPLY_FORMAT = "packrat-verdicts"
Export.VERSION = 1

Export.INSTRUCTIONS = table.concat({
    "This is a bag dump from the World of Warcraft addon packRat (Classic-era rules: WoW Forever / Classic Era).",
    "Help the player clean their bags. For every entry in `items`, decide one action:",
    "keep = worth keeping now; use = use, open, equip, eat or learn it now rather than carry it;",
    "flag = player should look at it (unsure, situational, or tied to a low-level quest); toss = sell or delete.",
    "Use the character's level, class and professions, the quest log (`quests`, with level, colour and the item IDs",
    "each quest needs) and the equipped gear. Quest items for active quests that are not gray are keep, never toss.",
    "Each item's `questLinks` comes from a quest database: state log = in the quest log, done = turned in,",
    "open = not started or abandoned. Never toss an item with a log or open quest link; packRat turns quest-item",
    "tosses into flags unless every linked quest is done. Items with no questLinks but questItem = true are unknown: flag.",
    "handedOut = the quest gave the item when accepted; it is often not needed to finish. Quests the character's race or",
    "class can't take are already left out. Items with equipmentSets or neverToss are keep. `elsewhere` counts copies in the",
    "bank, mail and on alts; `bank` lists the bank (for context: verdicts only apply to `items`). pawnUpgrade = Pawn says",
    "it's an upgrade.",
    "Profession materials are keep if the character has that profession; otherwise toss, or flag if they are worth",
    "selling on the auction house. Gear worse than what is equipped, and not useful for another spec, is toss.",
    "Dungeon keys, portal items and attunement items for content at or above the character's level are keep.",
    "Flavor items with no use are toss. `current` shows what packRat already decided on its own; you may override it.",
    "Reply with ONLY one JSON code block in this format, one entry per item ID, reasons under 60 characters:",
    '{"format":"packrat-verdicts","version":1,"summary":"one line","items":[{"id":2589,"action":"toss","reason":"Linen Cloth, no tailoring"}]}',
}, " ")

local function sortedQuests(list)
    local out = JSON.Array()
    for _, quest in ipairs(list) do
        out[#out + 1] = quest
    end
    table.sort(out, function(a, b) return (a.level or 0) < (b.level or 0) end)
    return out
end

local function exportQuest(quest, ctx)
    return {
        id = quest.id > 0 and quest.id or nil,
        title = quest.title,
        level = quest.level,
        color = quest.level and ns.Rules.QuestColor(quest.level, ctx.level, ctx.greenRange) or nil,
        complete = quest.complete or nil,
        objectives = JSON.Array(quest.objectives),
        summary = quest.summary,
        items = JSON.Array(quest.items or {}),
    }
end

-- state: "log" (in your quest log), "done" (turned in), "open" (neither yet).
local function exportLinks(links)
    local out = JSON.Array()
    for _, link in ipairs(links) do
        out[#out + 1] = {
            id = link.id, title = link.title, level = link.level,
            state = link.inLog and "log" or link.done and "done" or "open",
            repeatable = link.repeatable or nil, startsIt = link.starts or nil, handedOut = link.given or nil,
        }
    end
    return out
end

local function exportItem(item, status)
    return {
        id = item.id,
        name = item.name,
        count = item.count,
        stacks = #item.slots > 1 and #item.slots or nil,
        quality = item.quality,
        type = item.type,
        subType = item.subType,
        ilvl = item.ilvl,
        reqLevel = item.reqLevel and item.reqLevel > 1 and item.reqLevel or nil,
        equipLoc = item.equipLoc,
        sellPrice = item.sellPrice,
        bound = item.bound or nil,
        unique = item.unique or nil,
        questItem = item.questItem or nil,
        startsQuest = item.startsQuest or nil,
        useText = item.useText,
        tooltip = item.tooltip and #item.tooltip > 0 and JSON.Array(item.tooltip) or nil,
        questLinks = item.questLinks and #item.questLinks > 0 and exportLinks(item.questLinks) or nil,
        rxpJunk = item.rxpJunk or nil,
        equipmentSets = item.sets and #item.sets > 0 and JSON.Array(item.sets) or nil,
        neverToss = item.protected or nil,
        elsewhere = item.elsewhere,
        pawnUpgrade = item.upgrade or nil,
        current = status and status.action ~= "unsorted" and { action = status.action, reason = status.reason, source = status.source } or nil,
    }
end

-- snapshot = { character, settings, quests, items, statuses, equipped, ctx }
function Export.Document(snapshot)
    local quests = JSON.Array()
    for _, quest in ipairs(sortedQuests(snapshot.quests)) do
        quests[#quests + 1] = exportQuest(quest, snapshot.ctx)
    end
    local items = JSON.Array()
    for _, item in ipairs(snapshot.items) do
        items[#items + 1] = exportItem(item, snapshot.statuses[item.id])
    end
    return {
        _instructions = Export.INSTRUCTIONS,
        format = Export.FORMAT,
        version = Export.VERSION,
        exportedAt = date("!%Y-%m-%dT%H:%M:%SZ"),
        character = snapshot.character,
        settings = snapshot.settings,
        quests = quests,
        equipped = JSON.Array(snapshot.equipped or {}),
        bank = snapshot.bank,
        bankError = snapshot.bankError,
        items = items,
    }
end

function Export.ToJSON(snapshot)
    return JSON.Encode(Export.Document(snapshot), false)
end

-- Reading the agent's reply ----------------------------------------------------

-- The agent may wrap the JSON in a ```json fence or add a sentence around it;
-- take the outermost {...}.
local function extractJSON(text)
    local first = text:find("{", 1, true)
    local last
    for i = #text, 1, -1 do
        if text:sub(i, i) == "}" then
            last = i
            break
        end
    end
    if first and last and last > first then
        return text:sub(first, last)
    end
end

-- Returns { verdicts = { [itemID] = { action, reason } }, count, summary,
-- skipped } or nil, error.
function Export.ReadVerdicts(text)
    local body = type(text) == "string" and extractJSON(text)
    if not body then
        return nil, "No JSON found. Paste the agent's whole reply."
    end
    local doc, err = JSON.Decode(body)
    if type(doc) ~= "table" then
        return nil, "Couldn't read the JSON: " .. tostring(err)
    end
    if doc.format == Export.FORMAT then
        return nil, "That's the packRat export. Paste the agent's reply instead."
    end
    if doc.format and doc.format ~= Export.REPLY_FORMAT then
        return nil, "Unknown format \"" .. tostring(doc.format) .. "\"."
    end
    if type(doc.items) ~= "table" then
        return nil, "The reply has no \"items\" list."
    end
    local result = { verdicts = {}, count = 0, skipped = 0, summary = type(doc.summary) == "string" and doc.summary or nil }
    for _, entry in ipairs(doc.items) do
        local id = type(entry) == "table" and tonumber(entry.id)
        local action = type(entry) == "table" and type(entry.action) == "string" and entry.action:lower()
        if id and action and ns.Rules.VALID[action] then
            local reason = type(entry.reason) == "string" and entry.reason:sub(1, 120) or nil
            if not result.verdicts[id] then
                result.count = result.count + 1
            end
            result.verdicts[id] = { action = action, reason = reason }
        else
            result.skipped = result.skipped + 1
        end
    end
    if result.count == 0 then
        return nil, "The reply has no usable verdicts."
    end
    return result
end

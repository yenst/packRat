local _, ns = ...

-- Reads the bags into one record per item ID (stacks merged), with the
-- facts the rules and the export need. All WoW item API calls live here.
local Bags = {}
ns.Bags = Bags

local C = C_Container or {}
local GetNumSlots = C.GetContainerNumSlots or GetContainerNumSlots
local GetFreeSlots = C.GetContainerNumFreeSlots or GetContainerNumFreeSlots
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

Bags.FIRST, Bags.LAST = 0, NUM_BAG_SLOTS or 4

-- Same shape on every client: { itemID, count, quality, link, bound, noValue }.
function Bags.SlotInfo(bag, slot)
    if C.GetContainerItemInfo then
        local info = C.GetContainerItemInfo(bag, slot)
        if not info or not info.itemID then
            return nil
        end
        return {
            itemID = info.itemID, count = info.stackCount or 1, quality = info.quality,
            link = info.hyperlink, bound = info.isBound, noValue = info.hasNoValue,
        }
    end
    local _, count, _, quality, _, _, link, _, noValue, itemID = GetContainerItemInfo(bag, slot)
    if not itemID then
        return nil
    end
    return { itemID = itemID, count = count or 1, quality = quality, link = link, noValue = noValue }
end

-- Tooltip text, cached per item link ------------------------------------------

local tooltipCache = {}
local scanTip

local function tooltipLines(bag, slot)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local data = C_TooltipInfo.GetBagItem(bag, slot)
        for i, line in ipairs(data and data.lines or {}) do
            if i > 1 and line.leftText and line.leftText ~= "" then
                lines[#lines + 1] = line.leftText
            end
        end
        return lines
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "packRatScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetBagItem(bag, slot)
    for i = 2, scanTip:NumLines() or 0 do
        local fs = _G["packRatScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text and text ~= "" then
            lines[#lines + 1] = text
        end
    end
    scanTip:Hide()
    return lines
end

local USE_PREFIX = ITEM_SPELL_TRIGGER_ONUSE or "Use:"

-- "Equipment Sets: %s" / "Classes: %s" turned into Lua patterns.
local function prefixPattern(format, fallback)
    local text = (format or fallback):gsub("%%s", "\0")
    text = text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%z", "(.+)")
    return "^" .. text .. "$"
end
local SETS_PATTERN = prefixPattern(EQUIPMENT_SETS, "Equipment Sets: %s")
local CLASSES_PATTERN = prefixPattern(ITEM_CLASSES_ALLOWED, "Classes: %s")

-- Localized class name -> class file name ("Paladin" -> "PALADIN").
local classTokens
local function classToken(name)
    if not classTokens then
        classTokens = {}
        for token, localized in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
            classTokens[localized] = token
        end
        for token, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
            classTokens[localized] = token
        end
    end
    return classTokens[name] or name:upper()
end

local function splitList(text)
    local list = {}
    for part in text:gmatch("[^,]+") do
        list[#list + 1] = part:gsub("^%s+", ""):gsub("%s+$", "")
    end
    return list
end

-- Reads the flags packRat cares about out of the tooltip lines.
function Bags.ParseTooltip(lines)
    local facts = { lines = {} }
    for _, text in ipairs(lines) do
        local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if plain == (ITEM_BIND_QUEST or "Quest Item") then
            facts.questItem = true
        elseif plain == (ITEM_STARTS_QUEST or "This Item Begins a Quest") then
            facts.startsQuest = true
        elseif plain == (ITEM_SOULBOUND or "Soulbound") then
            facts.bound = true
        elseif plain:find("^" .. (ITEM_UNIQUE or "Unique")) then
            facts.unique = true
        elseif plain:sub(1, #USE_PREFIX) == USE_PREFIX then
            facts.useText = plain:sub(#USE_PREFIX + 1):gsub("^%s+", "")
        elseif plain:match(SETS_PATTERN) then
            facts.sets = splitList(plain:match(SETS_PATTERN))
        elseif plain:match(CLASSES_PATTERN) then
            facts.classes = {}
            for _, name in ipairs(splitList(plain:match(CLASSES_PATTERN))) do
                facts.classes[classToken(name)] = true
            end
        end
        if #facts.lines < 10 then
            facts.lines[#facts.lines + 1] = plain
        end
    end
    return facts
end

local function tooltipFacts(bag, slot, link)
    local facts = link and tooltipCache[link]
    if not facts then
        facts = Bags.ParseTooltip(tooltipLines(bag, slot))
        if link then
            tooltipCache[link] = facts
        end
    end
    return facts
end

local function questInfo(bag, slot)
    if not C.GetContainerItemQuestInfo then
        return nil
    end
    local ok, info = pcall(C.GetContainerItemQuestInfo, bag, slot)
    return ok and info or nil
end

-- Scan ------------------------------------------------------------------------

-- Returns items (list, one per item ID, sorted by name), byID, and bag space
-- { free, total }. `incomplete` is true when some item info wasn't cached yet.
function Bags.Scan()
    local items, byID = {}, {}
    local space = { free = 0, total = 0 }
    local incomplete = false
    for bag = Bags.FIRST, Bags.LAST do
        local slots = GetNumSlots(bag) or 0
        space.total = space.total + slots
        space.free = space.free + ((GetFreeSlots and GetFreeSlots(bag)) or 0)
        for slot = 1, slots do
            local info = Bags.SlotInfo(bag, slot)
            if info then
                local item = byID[info.itemID]
                if not item then
                    local name, _, quality, ilvl, reqLevel, itemType, subType, _, equipLoc, icon, sellPrice, classID, subClassID =
                        GetItemInfo(info.link or info.itemID)
                    if not name then
                        incomplete = true
                        local _, instType, instSub, instLoc, instIcon, instClass = GetItemInfoInstant(info.itemID)
                        itemType, subType, equipLoc, icon, classID = instType, instSub, instLoc, instIcon, instClass
                        name = info.link and info.link:match("%[(.-)%]")
                    end
                    local facts = tooltipFacts(bag, slot, info.link)
                    item = {
                        id = info.itemID, name = name or ("item:" .. info.itemID), link = info.link,
                        quality = quality or info.quality, ilvl = ilvl, reqLevel = reqLevel,
                        type = itemType, subType = subType, classID = classID, subClassID = subClassID,
                        equipLoc = equipLoc ~= "" and equipLoc or nil, icon = icon, sellPrice = sellPrice,
                        noValue = info.noValue or sellPrice == 0,
                        questItem = facts.questItem or classID == ns.Rules.CLASS_QUEST,
                        startsQuest = facts.startsQuest, unique = facts.unique, useText = facts.useText,
                        bound = info.bound or facts.bound, tooltip = facts.lines,
                        sets = facts.sets, classes = facts.classes,
                        count = 0, slots = {},
                    }
                    local quest = questInfo(bag, slot)
                    if quest then
                        item.questItem = item.questItem or quest.isQuestItem
                        if quest.questID and quest.questID > 0 and not quest.isActive then
                            item.startsQuest = true
                            item.startsQuestID = quest.questID
                        end
                    end
                    byID[info.itemID] = item
                    items[#items + 1] = item
                end
                item.count = item.count + info.count
                item.slots[#item.slots + 1] = { bag = bag, slot = slot, count = info.count }
            end
        end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    return items, byID, space, incomplete
end

function Bags.ClearCache()
    wipe(tooltipCache)
end

-- Equipped gear, for the agent to judge upgrades.
local SLOT_NAMES = {
    [1] = "head", [2] = "neck", [3] = "shoulder", [4] = "shirt", [5] = "chest", [6] = "waist", [7] = "legs",
    [8] = "feet", [9] = "wrist", [10] = "hands", [11] = "finger1", [12] = "finger2", [13] = "trinket1",
    [14] = "trinket2", [15] = "back", [16] = "mainhand", [17] = "offhand", [18] = "ranged", [19] = "tabard",
}

function Bags.Equipped()
    local list = {}
    for slotID = 1, 19 do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local name, _, quality, ilvl, reqLevel, _, subType = GetItemInfo(link)
            list[#list + 1] = {
                slot = SLOT_NAMES[slotID], id = tonumber(link:match("item:(%d+)")),
                name = name or link:match("%[(.-)%]"), quality = quality, ilvl = ilvl, reqLevel = reqLevel, subType = subType,
            }
        end
    end
    return list
end

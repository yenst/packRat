local ADDON, ns = ...

local Bags, Quests, Rules, Export = ns.Bags, ns.Quests, ns.Rules, ns.Export

-- Forever runs retail's UI code, where the global GetItemInfo is gone.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local DEFAULT_SETTINGS = {
    tossGrays = true,
    lowQuestGap = 0, -- 0 = flag quests once they're gray; N = N or more levels below you
    floatingButton = true, -- shown when Baganator isn't loaded
    tooltips = true,
    autoSell = false, -- sell tossed items (not agent-only ones) when a vendor opens
    turnInPrompt = true, -- list a quest's leftovers after you turn it in or abandon it
    minimapButton = true,
}

local HISTORY_SIZE = 300

ns.items, ns.byID, ns.statuses = {}, {}, {}
ns.space = { free = 0, total = 0 }
ns.counts = Rules.Counts({}, {})
ns.atMerchant = false

local function initDB()
    packRatDB = packRatDB or {}
    local db = packRatDB
    db.version = 1
    db.settings = db.settings or {}
    for key, value in pairs(DEFAULT_SETTINGS) do
        if db.settings[key] == nil then
            db.settings[key] = value
        end
    end
    db.chars = db.chars or {}
    db.protected = db.protected or {} -- account-wide never-toss list: [itemID] = true
    ns.db = db
end

local function loadCharacter()
    local key = UnitName("player") .. "-" .. GetRealmName()
    local c = ns.db.chars[key] or {}
    c.verdicts = c.verdicts or {}
    c.history = c.history or {}
    -- Verdicts saved before the rename used "claude"; they're agent verdicts now.
    for _, v in pairs(c.verdicts) do
        if v.source == "claude" then
            v.source = "agent"
        end
        if v.claude then
            v.agent, v.claude = v.claude, nil
            v.agent.source = "agent"
        end
    end
    ns.db.chars[key] = c
    ns.char = c
end

-- Scanning --------------------------------------------------------------------

-- Bits for the quest database's race / class masks. Races are 2^(raceID-1);
-- Forever's Skyborne races (IDs 95/96) use bits 32/33.
local function playerBits()
    local _, _, raceID = UnitRace("player")
    local _, class, classID = UnitClass("player")
    local raceBit
    if raceID then
        raceBit = raceID >= 95 and 2 ^ (raceID - 63) or 2 ^ (raceID - 1)
    end
    return raceBit, classID and 2 ^ (classID - 1) or nil, class
end

function ns.Context()
    local level = UnitLevel("player")
    local raceBit, classBit, class = playerBits()
    return {
        raceBit = raceBit,
        classBit = classBit,
        class = class,
        protected = ns.db.protected,
        level = level,
        quests = Quests.byID,
        gap = ns.db.settings.lowQuestGap,
        greenRange = Quests.GreenRange(level),
        tossGrays = ns.db.settings.tossGrays,
        db = ns.QuestData,
        isDone = ns.IsQuestDone,
    }
end

-- Turned-in quests. Repeatable ones never count (see Rules).
local isFlaggedCompleted = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
function ns.IsQuestDone(questID)
    if not isFlaggedCompleted or questID <= 0 then
        return false
    end
    local ok, done = pcall(isFlaggedCompleted, questID)
    return ok and done == true
end

local function rxpJunk(itemID)
    local data = _G.RXPCData
    return type(data) == "table" and type(data.discardPile) == "table" and data.discardPile[itemID] == true
end

-- Recomputes every item's status from the last scan, without rescanning.
function ns.Judge()
    local ctx = ns.Context()
    local statuses = {}
    for _, item in ipairs(ns.items) do
        statuses[item.id] = Rules.Status(item, ns.char.verdicts[item.id], ctx)
    end
    ns.statuses = statuses
    ns.counts = Rules.Counts(ns.items, statuses)
    ns.Refresh()
end

local retryQueued = false

function ns.Rescan(withQuests)
    if not ns.char then
        return
    end
    local removed
    if withQuests then
        local before = Quests.byID
        Quests.Scan()
        -- Quests that left the log since the last scan: turned in or abandoned.
        if ns.questsSeen then
            for id in pairs(before) do
                if id > 0 and not Quests.byID[id] then
                    removed = removed or {}
                    removed[#removed + 1] = { id = id, title = before[id].title }
                end
            end
        end
        ns.questsSeen = true
    end
    local items, byID, space, incomplete = Bags.Scan()
    for _, item in ipairs(items) do
        item.rxpJunk = rxpJunk(item.id) or nil
    end
    Rules.LinkQuests(items, Quests.list)
    ns.items, ns.byID, ns.space, ns.incomplete = items, byID, space, incomplete
    ns.Judge()
    if removed and ns.Prompt then
        ns.Prompt.QuestsLeft(removed)
    end
    -- Item info that wasn't cached arrives a moment later.
    if incomplete and not retryQueued then
        retryQueued = true
        C_Timer.After(1, function()
            retryQueued = false
            ns.Rescan()
        end)
    end
end

-- Bag and quest events come in bursts; rescan once they settle.
local queued, queuedQuests = false, false
function ns.QueueRescan(withQuests)
    queuedQuests = queuedQuests or withQuests
    if queued then
        return
    end
    queued = true
    C_Timer.After(0.3, function()
        queued = false
        local quests = queuedQuests
        queuedQuests = false
        ns.Rescan(quests)
    end)
end

function ns.StatusFor(itemID)
    return itemID and ns.statuses[itemID]
end

-- Never-toss list ---------------------------------------------------------------

function ns.IsProtected(itemID)
    return itemID and (Rules.PROTECTED[itemID] or ns.db.protected[itemID]) and true or false
end

function ns.ToggleProtected(itemID, name)
    if not itemID then
        return
    end
    if Rules.PROTECTED[itemID] then
        ns.Print((name or "That item") .. " is always protected.")
        return
    end
    ns.db.protected[itemID] = not ns.db.protected[itemID] or nil
    ns.Print((name or ("item " .. itemID)) .. (ns.db.protected[itemID] and " is on your never-toss list." or " is off your never-toss list."))
    ns.Judge()
end

-- Key binding: protect the item under the mouse (its tooltip is showing).
function ns.ProtectHovered()
    local _, link = GameTooltip:GetItem()
    local itemID = link and tonumber(link:match("item:(%d+)"))
    if not itemID then
        ns.Print("Hover over an item first.")
        return
    end
    ns.ToggleProtected(itemID, link)
end

-- History -----------------------------------------------------------------------

-- kind = "sold" | "deleted"
function ns.Log(kind, item, count, value, reason)
    local history = ns.char.history
    table.insert(history, 1, {
        t = time(), kind = kind, id = item.id, name = item.name, link = item.link,
        count = count, value = value, reason = reason,
    })
    for i = #history, HISTORY_SIZE + 1, -1 do
        history[i] = nil
    end
end

function ns.HistoryText()
    local lines = {}
    for _, e in ipairs(ns.char.history) do
        lines[#lines + 1] = string.format("%s  %-7s %s%s%s%s", date("%d %b %H:%M", e.t), e.kind, e.name,
            e.count > 1 and (" x" .. e.count) or "",
            e.kind == "sold" and ("  " .. ns.FormatMoney(e.value)) or "",
            e.reason and e.reason ~= "" and ("  (" .. e.reason .. ")") or "")
    end
    if #lines == 0 then
        return "Nothing sold or deleted yet."
    end
    return table.concat(lines, "\n")
end

-- Verdicts --------------------------------------------------------------------

-- action = nil clears your choice, so the agent's verdict or the rules apply again.
function ns.SetManual(itemID, action)
    local old = ns.char.verdicts[itemID]
    local agent = old and (old.source == "agent" and old or old.agent) or nil
    if action then
        ns.char.verdicts[itemID] = { action = action, reason = "Your choice", source = "manual", at = time(), agent = agent }
    else
        local v = ns.char.verdicts[itemID]
        if v and v.source == "manual" then
            ns.char.verdicts[itemID] = v.agent
        end
    end
    ns.Judge()
end

-- A new import replaces the agent's previous verdicts; your own choices stay
-- (the agent's verdict is kept underneath, so clearing your choice restores it).
function ns.ImportVerdicts(result)
    local verdicts = ns.char.verdicts
    for id, v in pairs(verdicts) do
        if v.source == "manual" then
            v.agent = nil
        else
            verdicts[id] = nil
        end
    end
    local now = time()
    for id, v in pairs(result.verdicts) do
        local entry = { action = v.action, reason = v.reason, source = "agent", at = now }
        if verdicts[id] then
            verdicts[id].agent = entry
        else
            verdicts[id] = entry
        end
    end
    ns.char.importedAt = now
    ns.char.summary = result.summary
    ns.Judge()
end

-- which = "agent" | "manual" | nil (all)
function ns.ClearVerdicts(which)
    for id, v in pairs(ns.char.verdicts) do
        if not which or v.source == which then
            ns.char.verdicts[id] = which == "manual" and v.agent or nil
        elseif which == "agent" then
            v.agent = nil
        end
    end
    if which ~= "manual" then
        ns.char.importedAt, ns.char.summary = nil, nil
    end
    ns.Judge()
end

-- Export ----------------------------------------------------------------------

local PROFESSIONS = {
    Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Herbalism = true,
    Leatherworking = true, Mining = true, Skinning = true, Tailoring = true, Jewelcrafting = true,
    Inscription = true, Cooking = true, ["First Aid"] = true, Fishing = true, Lockpicking = true,
}

-- Same shape on every client: name, isHeader, isExpanded, rank, max. Some
-- clients return one table instead of separate values.
local function skillLine(i)
    local getInfo = (C_SkillInfo and C_SkillInfo.GetSkillLineInfo) or GetSkillLineInfo
    local name, isHeader, isExpanded, rank, _, _, max = getInfo(i)
    if type(name) == "table" then
        local t = name
        return t.name, t.isHeader, t.isExpanded, t.rank or t.skillRank, t.maxRank or t.skillMaxRank
    end
    return name, isHeader, isExpanded, rank, max
end

local function numSkillLines()
    local getNum = (C_SkillInfo and C_SkillInfo.GetNumSkillLines) or GetNumSkillLines
    return getNum and getNum() or 0
end

-- Professions sit under headers in the skill list, and collapsed headers hide
-- them, so expand everything while reading and collapse the same headers again.
local function professions()
    local list = ns.JSON.Array()
    if not ((C_SkillInfo and C_SkillInfo.GetSkillLineInfo) or GetSkillLineInfo) then
        return list
    end
    local collapsed = {}
    for i = 1, numSkillLines() do
        local name, isHeader, isExpanded = skillLine(i)
        if isHeader and not isExpanded then
            collapsed[name] = true
        end
    end
    local canExpand = ExpandSkillHeader and CollapseSkillHeader and next(collapsed)
    if canExpand then
        ExpandSkillHeader(0)
    end
    local header
    local tradeHeaders = { [TRADE_SKILLS or "Professions"] = true, [SECONDARY_SKILLS or "Secondary Skills"] = true,
        Professions = true, ["Secondary Skills"] = true }
    local toCollapse, seen = {}, {}
    for i = 1, numSkillLines() do
        local name, isHeader, _, rank, max = skillLine(i)
        if isHeader then
            header = name
            if collapsed[name] then
                toCollapse[#toCollapse + 1] = i
            end
        elseif name and not seen[name] and (PROFESSIONS[name] or tradeHeaders[header or ""]) then
            -- Some clients list a skill twice (once per expanded header); keep the first.
            seen[name] = true
            list[#list + 1] = { name = name, rank = rank, max = max }
        end
    end
    if canExpand then
        for j = #toCollapse, 1, -1 do
            CollapseSkillHeader(toCollapse[j])
        end
    end
    return list
end

-- Syndicator (ships with Baganator) knows the bank and other characters.
local function syndicator()
    local api = _G.Syndicator and _G.Syndicator.API
    if api and (not api.IsReady or api.IsReady()) then
        return api
    end
end

-- Your name as Syndicator stores it. Forever characters have surnames
-- ("Billy Joel"), so it's taken from Syndicator's own "Name-Realm" key.
function ns.SyndicatorName(api)
    local full = api and api.GetCurrentCharacter and api.GetCurrentCharacter()
    return type(full) == "string" and full:match("^([^-]+)%-") or UnitName("player")
end

-- { bank, mail, alts } counts of an item outside your bags, or nil.
function ns.Elsewhere(itemID)
    local api = syndicator()
    if not (api and api.GetInventoryInfoByItemID) then
        return nil
    end
    local ok, info = pcall(api.GetInventoryInfoByItemID, itemID, true, false)
    if not ok or type(info) ~= "table" or type(info.characters) ~= "table" then
        return nil
    end
    local me = ns.SyndicatorName(api)
    local out = { bank = 0, mail = 0, alts = 0 }
    for _, c in ipairs(info.characters) do
        if c.character == me or c.character == UnitName("player") then
            out.bank, out.mail = out.bank + (c.bank or 0), out.mail + (c.mail or 0)
        else
            out.alts = out.alts + (c.bags or 0) + (c.bank or 0) + (c.mail or 0)
        end
    end
    if out.bank + out.mail + out.alts == 0 then
        return nil
    end
    return out
end

-- Your bank as last seen by Syndicator: list of { id, name, count, quality }.
function ns.BankItems()
    local api = syndicator()
    local data = api and api.GetCurrentCharacter and api.GetByCharacterFullName
        and api.GetByCharacterFullName(api.GetCurrentCharacter())
    if type(data) ~= "table" then
        return nil
    end
    -- Classic keeps bank bags in `bank`; Forever (retail UI) keeps bank tabs
    -- in `bankTabs`, each with its `slots`.
    local containers = {}
    for _, bag in pairs(type(data.bank) == "table" and data.bank or {}) do
        containers[#containers + 1] = bag
    end
    for _, tab in pairs(type(data.bankTabs) == "table" and data.bankTabs or {}) do
        containers[#containers + 1] = type(tab) == "table" and tab.slots or nil
    end
    local byID, list = {}, ns.JSON.Array()
    for _, bag in ipairs(containers) do
        for _, slot in pairs(type(bag) == "table" and bag or {}) do
            if type(slot) == "table" and slot.itemID then
                local entry = byID[slot.itemID]
                if not entry then
                    local name, _, quality = GetItemInfo(slot.itemLink or slot.itemID)
                    entry = { id = slot.itemID, name = name or (slot.itemLink and slot.itemLink:match("%[(.-)%]")), count = 0, quality = quality }
                    byID[slot.itemID] = entry
                    list[#list + 1] = entry
                end
                entry.count = entry.count + (slot.itemCount or 1)
            end
        end
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    return list
end

-- Bank list for the export; a failure is reported instead of breaking it.
function ns.ReadBank()
    local ok, bank = pcall(ns.BankItems)
    if ok then
        ns.bankItems, ns.bankError = bank, (bank == nil and "Syndicator has no bank data for this character" or nil)
    else
        ns.bankItems, ns.bankError = nil, tostring(bank)
    end
    return ns.bankItems, ns.bankError
end

function ns.Snapshot()
    ns.Rescan(true)
    ns.ReadBank()
    for _, item in ipairs(ns.items) do
        -- Syndicator data is a bonus; a problem there must not break the export.
        local ok, elsewhere = pcall(ns.Elsewhere, item.id)
        item.elsewhere = ok and elsewhere or nil
        item.protected = ns.IsProtected(item.id) or nil
        -- With Pawn installed, let it say which gear is an upgrade.
        item.upgrade = nil
        if _G.PawnIsItemAnUpgrade and item.link and item.equipLoc then
            local ok, upgrade = pcall(_G.PawnIsItemAnUpgrade, item.link)
            item.upgrade = ok and upgrade and true or nil
        end
    end
    local ctx = ns.Context()
    local rxp = _G.RXPCData
    return {
        character = {
            name = (function()
                local first, surname = UnitName("player")
                return surname and surname ~= "" and (first .. " " .. surname) or first
            end)(),
            realm = GetRealmName(),
            class = select(2, UnitClass("player")),
            race = select(2, UnitRace("player")),
            level = ctx.level,
            xp = UnitXP("player"),
            xpMax = UnitXPMax("player"),
            restedXP = GetXPExhaustion and GetXPExhaustion() or 0,
            money = GetMoney(),
            professions = professions(),
            bagSlots = { free = ns.space.free, total = ns.space.total },
            rxpGuide = type(rxp) == "table" and type(rxp.currentGuideName) == "string" and rxp.currentGuideName or nil,
        },
        settings = { lowQuestGap = ctx.gap, tossGrays = ctx.tossGrays },
        quests = Quests.list,
        items = ns.items,
        statuses = ns.statuses,
        equipped = Bags.Equipped(),
        bank = ns.bankItems,
        bankError = ns.bankError,
        ctx = ctx,
    }
end

-- Tossing ---------------------------------------------------------------------

local C = C_Container or {}
local PickupItem = C.PickupContainerItem or PickupContainerItem
local UseItem = C.UseContainerItem or UseContainerItem

local function stillThere(item, slot)
    local info = Bags.SlotInfo(slot.bag, slot.slot)
    return info and info.itemID == item.id
end

-- Deletes one stack. WoW only allows this from a click or key press, so it's
-- one stack per click.
function ns.DeleteSlot(item, slot)
    if GetCursorInfo() then
        ns.Print("Your cursor is holding something; put it down first.")
        return false
    end
    if not stillThere(item, slot) then
        ns.Rescan()
        return false
    end
    PickupItem(slot.bag, slot.slot)
    if GetCursorInfo() ~= "item" then
        ClearCursor()
        return false
    end
    DeleteCursorItem()
    local status = ns.statuses[item.id]
    ns.Log("deleted", item, slot.count, 0, status and status.reason)
    ns.Print("Deleted " .. (item.link or item.name) .. (slot.count > 1 and (" x" .. slot.count) or "") .. ".")
    ns.QueueRescan()
    return true
end

function ns.NextToDelete()
    return Rules.NextToDelete(ns.items, ns.statuses, ns.db.protected)
end

function ns.DeleteNext()
    local item, slot = ns.NextToDelete()
    if not item then
        ns.Print("Nothing left to toss below rare quality.")
        return
    end
    ns.DeleteSlot(item, slot)
end

-- Sells up to 12 tossed stacks per click (the vendor's buyback holds 12).
-- auto = true (vendor just opened): only tosses from the rules or your own
-- choices, never ones the agent alone decided, and quiet when there's nothing.
function ns.SellTossed(auto)
    if not ns.atMerchant then
        ns.Print("Open a vendor first.")
        return
    end
    local list = Rules.ToSell(ns.items, ns.statuses, 12, ns.db.protected, auto)
    if #list == 0 then
        if not auto then
            ns.Print("Nothing to sell.")
        end
        return
    end
    local total, sold = 0, 0
    for _, entry in ipairs(list) do
        if stillThere(entry.item, entry.slot) then
            UseItem(entry.slot.bag, entry.slot.slot)
            local value = (entry.item.sellPrice or 0) * entry.slot.count
            local status = ns.statuses[entry.item.id]
            ns.Log("sold", entry.item, entry.slot.count, value, status and status.reason)
            total, sold = total + value, sold + 1
        end
    end
    ns.Print(string.format("%s %s for %s. Changed your mind? They're in this vendor's buyback until you leave.",
        auto and "Auto-sold" or "Sold", ns.Plural(sold, "stack"), ns.FormatMoney(total)))
    ns.QueueRescan()
end

-- Gold the tossed items would fetch at a vendor.
function ns.TossValue()
    local total = 0
    for _, entry in ipairs(Rules.ToSell(ns.items, ns.statuses, 1000, ns.db.protected)) do
        total = total + (entry.item.sellPrice or 0) * entry.slot.count
    end
    return total
end

-- Key binding (Bindings.xml).
BINDING_HEADER_PACKRAT = "packRat"
BINDING_NAME_PACKRAT_DELETE_NEXT = "Delete next tossed item"
BINDING_NAME_PACKRAT_TOGGLE = "Open packRat"
BINDING_NAME_PACKRAT_PROTECT = "Never toss the item under the mouse (toggle)"
function packRat_Protect()
    ns.ProtectHovered()
end
function packRat_DeleteNext()
    ns.DeleteNext()
end
function packRat_Toggle()
    ns.Window.Toggle()
end

-- Events ----------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
    if name == ADDON then
        initDB()
        events:UnregisterEvent("ADDON_LOADED")
    end
end

function handlers.PLAYER_LOGIN()
    loadCharacter()
    ns.Theme.Load()
    ns.Rescan(true)
    ns.Integrations.Setup()
end

function handlers.BAG_UPDATE_DELAYED()
    ns.QueueRescan()
end

local lastQuestSignature
function handlers.QUEST_LOG_UPDATE()
    -- Reading the log (expanding headers, selecting quests) fires this event
    -- too, so only rescan when what's visible actually changed.
    local signature = Quests.Signature()
    if signature ~= lastQuestSignature then
        lastQuestSignature = signature
        ns.QueueRescan(true)
    end
end

function handlers.PLAYER_LEVEL_UP()
    C_Timer.After(0.5, ns.Judge)
end

function handlers.GET_ITEM_INFO_RECEIVED()
    if ns.incomplete then
        ns.QueueRescan()
    end
end

function handlers.MERCHANT_SHOW()
    ns.atMerchant = true
    ns.Refresh()
    if ns.db.settings.autoSell then
        -- Let the merchant frame finish opening first.
        C_Timer.After(0.3, function()
            if ns.atMerchant then
                ns.SellTossed(true)
            end
        end)
    end
end

function handlers.MERCHANT_CLOSED()
    ns.atMerchant = false
    ns.Refresh()
end

for event in pairs(handlers) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)

-- Slash command ---------------------------------------------------------------

local HELP = {
    "/packrat - open the bag triage window",
    "/packrat export | import - copy your bags for an AI agent / paste its reply",
    "/packrat next - delete the next tossed stack (or bind a key: Key Bindings > packRat)",
    "/packrat sell - sell tossed items at an open vendor",
    "/packrat gap <levels> - flag quest items once the quest is this many levels below you (0 = when gray)",
    "/packrat grays - toggle auto-tossing gray items",
    "/packrat button - show / hide the floating button",
    "/packrat protect <item link> - add / remove an item on your never-toss list (shift-click the item into chat)",
    "/packrat history - what packRat sold and deleted",
    "/packrat options - settings (auto-sell, turn-in prompt, ...)",
    "/packrat autosell - toggle selling tossed items when a vendor opens",
    "/packrat debug - check which game APIs this client has",
    "/packrat clear - forget agent verdicts and your choices",
}

local COMMANDS = {
    [""] = function() ns.Window.Toggle() end,
    export = function() ns.ExportWindow.Open("export") end,
    import = function() ns.ExportWindow.Open("import") end,
    next = function() ns.DeleteNext() end,
    sell = function() ns.SellTossed(false) end,
    gap = function(args)
        local gap = tonumber(args)
        if not gap or gap < 0 or gap > 60 then
            ns.Print("Usage: /packrat gap 10  (0 = flag when the quest is gray)")
            return
        end
        ns.db.settings.lowQuestGap = math.floor(gap)
        ns.Judge()
        ns.Print(gap == 0 and "Quest items are flagged once their quest is gray."
            or string.format("Quest items are flagged once their quest is %d+ levels below you.", gap))
    end,
    grays = function()
        ns.db.settings.tossGrays = not ns.db.settings.tossGrays
        ns.Judge()
        ns.Print("Gray items: " .. (ns.db.settings.tossGrays and "tossed automatically." or "left unsorted."))
    end,
    button = function()
        ns.db.settings.floatingButton = not ns.db.settings.floatingButton
        ns.Refresh()
    end,
    clear = function()
        ns.ClearVerdicts()
        ns.Print("Verdicts cleared.")
    end,
    protect = function(args)
        local itemID = tonumber(args:match("item:(%d+)") or args:match("^(%d+)$"))
        if not itemID then
            local names = {}
            for id in pairs(ns.db.protected) do
                local name = GetItemInfo(id)
                names[#names + 1] = name or ("item " .. id)
            end
            table.sort(names)
            ns.Print(#names == 0 and "Your never-toss list is empty. Usage: /packrat protect [shift-click an item]"
                or ("Never toss: " .. table.concat(names, ", ")))
            return
        end
        ns.ToggleProtected(itemID, args:match("|h(%[.-%])|h") or nil)
    end,
    history = function() ns.ExportWindow.ShowText("History", "Last sold and deleted items. Sold items stay in buyback until you leave that vendor.", ns.HistoryText()) end,
    options = function() ns.Options.Open() end,
    autosell = function()
        ns.db.settings.autoSell = not ns.db.settings.autoSell
        ns.Print("Auto-sell at vendors: " .. (ns.db.settings.autoSell and "on (rule and own tosses only, 12 stacks)." or "off."))
        ns.Refresh()
    end,
    debug = function() ns.ExportWindow.ShowText("Debug", "Client and API check. Ctrl+C to copy.", ns.Debug.Report()) end,
}

SLASH_PACKRAT1, SLASH_PACKRAT2 = "/packrat", "/rat"
SlashCmdList.PACKRAT = function(input)
    local command, args = input:match("^%s*(%S*)%s*(.-)%s*$")
    local handler = COMMANDS[command:lower()]
    if handler then
        handler(args)
    else
        for _, line in ipairs(HELP) do
            ns.Print(line)
        end
    end
end

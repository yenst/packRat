local _, ns = ...

local Theme, W = ns.Theme, ns.W

-- After you turn in or abandon a quest: a small window listing only that
-- quest's leftovers in your bags, with a Delete button per item (one stack
-- per click, as WoW requires) and Keep. Items another quest still needs stay
-- off the list.
local Prompt = {}
ns.Prompt = Prompt

local WIDTH, ROW_HEIGHT, MAX_ROWS = 460, 26, 8
local frame
local entries = {} -- { itemID, questTitle }
local header = ""

local function buildRow(index)
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 12, -64 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", -12, -64 - (index - 1) * ROW_HEIGHT)
    row:EnableMouse(true)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.delete = W.Button(row, "Delete", 56, 20, function(self)
        local item = self:GetParent().item
        if item then
            ns.DeleteSlot(item, item.slots[1])
        end
    end)
    row.delete:SetPoint("RIGHT")
    row.keep = W.Button(row, "Keep", 44, 20, function(self)
        local item = self:GetParent().item
        if item then
            ns.SetManual(item.id, "keep")
            Prompt.Forget(item.id)
        end
    end)
    row.keep:SetPoint("RIGHT", row.delete, "LEFT", -4, 0)
    row.name = W.Text(row, 12)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.keep, "LEFT", -8, 0)
    row:SetScript("OnEnter", function(self)
        local slot = self.item and self.item.slots[1]
        if slot then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetBagItem(slot.bag, slot.slot)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function build()
    frame = W.Window("packRatPrompt", WIDTH, 120, "Quest leftovers")
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    frame.header = W.Text(frame, 12)
    frame.header:SetPoint("TOPLEFT", 14, -42)
    frame.header:SetPoint("RIGHT", -14, 0)
    frame.rows = {}
    for i = 1, MAX_ROWS do
        frame.rows[i] = buildRow(i)
    end
    frame.hint = W.Text(frame, 11, Theme.muted)
    frame.hint:SetPoint("BOTTOMLEFT", 14, 12)
    frame.hint:SetText("Delete removes one stack per click (WoW allows no more).")
    frame:HookScript("OnHide", function() wipe(entries) end)
end

-- Items still in your bags, still linked to one of the quests, and not
-- needed by anything else (packRat says toss or flag).
local function current()
    local list = {}
    for _, entry in ipairs(entries) do
        local item = ns.byID[entry.itemID]
        local status = item and ns.statuses[item.id]
        if status and (status.action == "toss" or status.action == "flag") and status.source ~= "protected" then
            list[#list + 1] = { item = item, status = status }
        end
    end
    return list
end

function Prompt.Update()
    if not (frame and frame:IsShown()) then
        return
    end
    local list = current()
    if #list == 0 then
        frame:Hide()
        return
    end
    frame.header:SetText(header)
    for i, row in ipairs(frame.rows) do
        local entry = list[i]
        row.item = entry and entry.item
        row:SetShown(entry ~= nil)
        if entry then
            local item = entry.item
            row.icon:SetTexture(item.icon or 134400)
            row.name:SetText(Theme.QualityHex(item.quality) .. item.name .. "|r"
                .. (item.count > 1 and (" x" .. item.count) or "") .. "  "
                .. Theme.ActionText(entry.status.action) .. " " .. Theme.Hex(Theme.muted) .. entry.status.reason .. "|r")
        end
    end
    frame:SetHeight(64 + math.min(#list, MAX_ROWS) * ROW_HEIGHT + 34)
end

function Prompt.Forget(itemID)
    for i = #entries, 1, -1 do
        if entries[i].itemID == itemID then
            table.remove(entries, i)
        end
    end
    Prompt.Update()
end

-- removed = { { id, title } } quests that just left the log.
function Prompt.QuestsLeft(removed)
    if not ns.db.settings.turnInPrompt then
        return
    end
    -- The game removes quest items and flags the quest completed a moment
    -- after the log changes; judge once that has settled.
    C_Timer.After(1.5, function()
        ns.Rescan()
        local found, labels = {}, {}
        for _, quest in ipairs(removed) do
            local done = ns.IsQuestDone(quest.id)
            labels[#labels + 1] = (done and "Turned in: " or "Abandoned: ") .. Theme.Hex(Theme.accent) .. (quest.title or ("quest " .. quest.id)) .. "|r"
            for _, item in ipairs(ns.items) do
                for _, link in ipairs(item.questLinks or {}) do
                    if link.id == quest.id and not found[item.id] then
                        found[item.id] = true
                        entries[#entries + 1] = { itemID = item.id }
                    end
                end
            end
        end
        if #current() == 0 then
            return
        end
        if not frame then
            build()
        end
        header = table.concat(labels, "   ")
        frame:Show()
        Prompt.Update()
    end)
end

ns.OnRefresh(Prompt.Update)

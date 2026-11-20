local _, ns = ...

local Theme, W = ns.Theme, ns.W

-- The triage window: every item in your bags with its status, filters,
-- per-item Keep / Toss / Delete, and the export / import / sell / delete buttons.
local Window = {}
ns.Window = Window

local WIDTH, HEIGHT = 700, 520
local ROW_HEIGHT, LIST_TOP, LIST_BOTTOM = 26, 112, 56
local ROWS = math.floor((HEIGHT - LIST_TOP - LIST_BOTTOM - 8) / ROW_HEIGHT)
local FILTERS = { "all", "toss", "flag", "use", "unsorted", "keep" }
local ORDER = { toss = 1, flag = 2, use = 3, unsorted = 4, keep = 5 }

local frame
local filter, offset = "all", 0
local visible = {}

local function filtered()
    local list = {}
    for _, item in ipairs(ns.items) do
        local status = ns.statuses[item.id]
        local action = status and status.action or "unsorted"
        if filter == "all" or filter == action then
            list[#list + 1] = item
        end
    end
    table.sort(list, function(a, b)
        local sa, sb = ns.statuses[a.id], ns.statuses[b.id]
        local oa, ob = ORDER[sa and sa.action or "unsorted"], ORDER[sb and sb.action or "unsorted"]
        if oa ~= ob then
            return oa < ob
        end
        return a.name < b.name
    end)
    return list
end

local function sourceLabel(status)
    return status.source == "agent" and "Agent: " or ""
end

local function buildRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 4, -4 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", -4, -4 - (index - 1) * ROW_HEIGHT)
    local hover = row:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.04)
    hover:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.name = W.Text(row, 12)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetWidth(190)
    row.badge = W.Text(row, 12, Theme.text, "CENTER")
    row.badge:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.badge:SetWidth(40)

    local B = Theme.BUTTON
    local function manual(action)
        return function(self)
            local item, status = self:GetParent().item, self:GetParent().status
            ns.SetManual(item.id, not (status.source == "manual" and status.action == action) and action or nil)
        end
    end
    local function isMine(button, action)
        local status = button:GetParent().status
        return status and status.source == "manual" and status.action == action
    end

    row.delete = W.IconButton(row, 22, B.delete, "Del", function()
        return "Delete", "Destroy one stack of this item now. Can't be undone."
    end, function(self)
        local item = self:GetParent().item
        if item then
            ns.DeleteSlot(item, item.slots[1])
        end
    end)
    row.delete:SetPoint("RIGHT", -2, 0)
    row.toss = W.IconButton(row, 22, B.toss, "T", function(self)
        if isMine(self, "toss") then
            return "Toss (your choice)", "Click again to undo."
        end
        return "Toss", "Mark this item to sell or delete. Beats the rules and agent verdicts."
    end, manual("toss"))
    row.toss:SetPoint("RIGHT", row.delete, "LEFT", -4, 0)
    row.keep = W.IconButton(row, 22, B.keep, "K", function(self)
        if isMine(self, "keep") then
            return "Keep (your choice)", "Click again to undo."
        end
        return "Keep", "Mark this item to keep. Beats the rules and agent verdicts."
    end, manual("keep"))
    row.keep:SetPoint("RIGHT", row.toss, "LEFT", -4, 0)
    row.lock = W.IconButton(row, 22, B.lock, "L", function(self)
        local item = self:GetParent().item
        if item and ns.IsProtected(item.id) then
            return "Locked", "On your never-toss list. Click to unlock."
        end
        return "Lock", "Never toss this item: beats every rule, agent verdicts and your own Toss. Account-wide."
    end, function(self)
        local item = self:GetParent().item
        if item then
            ns.ToggleProtected(item.id, item.link or item.name)
        end
    end)
    row.lock:SetPoint("RIGHT", row.keep, "LEFT", -4, 0)

    row.reason = W.Text(row, 11, Theme.muted)
    row.reason:SetPoint("LEFT", row.badge, "RIGHT", 8, 0)
    row.reason:SetPoint("RIGHT", row.lock, "LEFT", -8, 0)

    row:SetScript("OnEnter", function(self)
        hover:Show()
        local slot = self.item and self.item.slots[1]
        if slot then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetBagItem(slot.bag, slot.slot)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        hover:Hide()
        GameTooltip:Hide()
    end)
    -- Shift-click links the item in chat, like a bag slot.
    row:SetScript("OnClick", function(self)
        if self.item and self.item.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            ChatEdit_InsertLink(self.item.link)
        end
    end)
    return row
end

local function updateRow(row, item)
    row.item = item
    row:SetShown(item ~= nil)
    if not item then
        return
    end
    local status = ns.statuses[item.id] or { action = "unsorted", reason = "", source = "none" }
    row.status = status
    row.icon:SetTexture(item.icon or 134400) -- question mark
    row.name:SetText(Theme.QualityHex(item.quality) .. item.name .. "|r" .. (item.count > 1 and (Theme.Hex(Theme.muted) .. " x" .. item.count .. "|r") or ""))
    row.badge:SetText(Theme.ActionText(status.action))
    local reason = status.reason or ""
    row.reason:SetText(reason ~= "" and (sourceLabel(status) .. reason) or "")
    row.keep:SetSelected(status.source == "manual" and status.action == "keep")
    row.toss:SetSelected(status.source == "manual" and status.action == "toss")
    -- Keep the slot so the other icons don't shift; only show Delete for tossed items.
    row.delete:SetAlpha(status.action == "toss" and 1 or 0)
    row.delete:EnableMouse(status.action == "toss")
    local locked = ns.IsProtected(item.id)
    row.lock:SetSelected(locked)
    row.lock:SetIcon(locked and Theme.BUTTON.locked or Theme.BUTTON.lock, locked and "L!" or "L")
end

local function summaryText()
    local c = ns.counts
    local parts = {
        "Level " .. UnitLevel("player"),
        string.format("%d/%d slots free", ns.space.free, ns.space.total),
    }
    for _, action in ipairs({ "toss", "flag", "use", "unsorted" }) do
        if (c[action] or 0) > 0 then
            parts[#parts + 1] = Theme.ActionText(action) .. " " .. c[action]
        end
    end
    return table.concat(parts, Theme.Hex(Theme.muted) .. "  ·  |r")
end

local function agentText()
    local c = ns.char
    if not c.importedAt then
        return "No agent verdicts yet: Export for agent, paste it into your AI agent, then Import its reply."
    end
    local line = "Agent verdicts from " .. date("%d %b %H:%M", c.importedAt)
    if c.summary then
        line = line .. ": " .. c.summary
    end
    return line
end

local function build()
    frame = W.Window("packRatWindow", WIDTH, HEIGHT, "Bag triage")

    frame.summary = W.Text(frame, 12)
    frame.summary:SetPoint("TOPLEFT", 16, -42)
    frame.agent = W.Text(frame, 11, Theme.muted)
    frame.agent:SetPoint("TOPLEFT", 16, -62)
    frame.agent:SetPoint("RIGHT", -16, 0)

    frame.filters = {}
    local previous
    for _, key in ipairs(FILTERS) do
        local label = key == "all" and "All" or key == "unsorted" and "Unsorted" or Theme.ACTION[key].label
        local button = W.Button(frame, label, 76, 22, function()
            filter, offset = key, 0
            Window.Update()
        end)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", 16, -82)
        end
        button.key = key
        frame.filters[#frame.filters + 1] = button
        previous = button
    end

    local list = W.Panel(frame, { 0, 0, 0, 0.35 })
    list:SetPoint("TOPLEFT", 12, -LIST_TOP)
    list:SetPoint("BOTTOMRIGHT", -12, LIST_BOTTOM)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(math.max(0, #visible - ROWS), offset - delta * 3))
        Window.Update()
    end)
    frame.empty = W.Text(list, 12, Theme.muted, "CENTER")
    frame.empty:SetPoint("CENTER")
    frame.rows = {}
    for i = 1, ROWS do
        frame.rows[i] = buildRow(list, i)
    end
    -- Top right, on the summary line: the footer is full of buttons.
    frame.scrollInfo = W.Text(frame, 12, Theme.muted, "RIGHT")
    frame.scrollInfo:SetPoint("TOPRIGHT", -16, -42)

    frame.options = W.Button(frame, "Options", 70, 22, function() ns.Options.Open() end)
    frame.options:SetPoint("TOPRIGHT", -16, -82)
    frame.history = W.Button(frame, "History", 70, 22, function()
        ns.ExportWindow.ShowText("History", "Last sold and deleted items. Sold items stay in buyback until you leave that vendor.", ns.HistoryText())
    end)
    frame.history:SetPoint("RIGHT", frame.options, "LEFT", -4, 0)

    frame.export = W.Button(frame, "Export for agent", 130, 26, function() ns.ExportWindow.Open("export") end)
    frame.export:SetPoint("BOTTOMLEFT", 12, 16)
    frame.import = W.Button(frame, "Import reply", 100, 26, function() ns.ExportWindow.Open("import") end)
    frame.import:SetPoint("LEFT", frame.export, "RIGHT", 6, 0)
    frame.clear = W.Button(frame, "Clear", 60, 26, function()
        ns.ClearVerdicts()
        ns.Print("Agent verdicts and your choices are cleared.")
    end)
    frame.clear:SetPoint("LEFT", frame.import, "RIGHT", 6, 0)
    W.Tooltip(frame.clear, function(tip)
        tip:AddLine("Forget the agent's verdicts and your Keep / Toss choices")
        tip:AddLine("The built-in rules still apply.", 0.7, 0.7, 0.7)
    end)

    frame.next = W.Button(frame, "Delete next", 220, 26, function() ns.DeleteNext() end)
    frame.next:SetPoint("BOTTOMRIGHT", -12, 16)
    W.Tooltip(frame.next, function(tip)
        tip:AddLine("Delete the next tossed stack")
        tip:AddLine("One stack per click; WoW doesn't let addons delete in bulk.", 0.7, 0.7, 0.7, true)
        tip:AddLine("Rare and better items are never deleted here.", 0.7, 0.7, 0.7, true)
        tip:AddLine("You can bind a key to it under Key Bindings > Packrat.", 0.7, 0.7, 0.7, true)
    end)
    frame.sell = W.Button(frame, "Sell tossed", 100, 26, function() ns.SellTossed() end)
    frame.sell:SetPoint("RIGHT", frame.next, "LEFT", -6, 0)
    W.Tooltip(frame.sell, function(tip)
        tip:AddLine("Sell tossed items to the open vendor")
        tip:AddLine("Up to 12 stacks per click, so all of them stay in buyback.", 0.7, 0.7, 0.7, true)
    end)

    frame:SetScript("OnShow", function()
        ns.Rescan(true)
    end)
end

function Window.Update()
    if not (frame and frame:IsShown()) then
        return
    end
    frame.summary:SetText(summaryText())
    frame.agent:SetText(agentText())
    for _, button in ipairs(frame.filters) do
        button:SetSelected(button.key == filter)
    end
    visible = filtered()
    offset = math.max(0, math.min(offset, #visible - ROWS))
    for i, row in ipairs(frame.rows) do
        updateRow(row, visible[offset + i])
    end
    frame.empty:SetText(#visible == 0 and (filter == "all" and "Your bags are empty." or "Nothing here.") or "")
    frame.scrollInfo:SetText(#visible > ROWS and string.format("%d-%d of %d  (scroll)", offset + 1, math.min(#visible, offset + ROWS), #visible) or "")

    local item, slot = ns.NextToDelete()
    frame.next:SetDisabled(item == nil)
    frame.next:SetLabel(item and ("Delete: " .. (#item.name > 22 and (item.name:sub(1, 21) .. "…") or item.name) .. (slot.count > 1 and (" x" .. slot.count) or "")) or "Nothing to delete")
    frame.sell:SetDisabled(not ns.atMerchant)
end

function Window.Toggle()
    if not frame then
        build()
    end
    frame:SetShown(not frame:IsShown())
    Window.Update()
end

function Window.Open(filterKey)
    if not frame then
        build()
    end
    filter, offset = filterKey or filter, 0
    frame:Show()
    Window.Update()
end

ns.OnRefresh(Window.Update)

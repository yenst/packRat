local _, ns = ...

local Theme, W = ns.Theme, ns.W

-- Where packRat shows up outside its own window:
--   * Baganator: a button in the backpack view, an icon in an item corner
--     (Flag / Toss / Use) and a junk plugin so tossed items get the junk coin.
--   * Without Baganator: a floating button you can drag anywhere.
--   * Item tooltips: a "packRat: Toss - reason" line.
local Integrations = {}
ns.Integrations = Integrations

local function isLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    return IsAddOnLoaded and IsAddOnLoaded(name)
end

-- The packRat button --------------------------------------------------------

local function buttonTooltip(tip)
    local c = ns.counts
    tip:AddLine(Theme.Hex(Theme.accent) .. "packRat|r")
    tip:AddLine(string.format("%s %d   %s %d   %s %d   %s %d",
        Theme.ActionText("toss"), c.toss, Theme.ActionText("flag"), c.flag,
        Theme.ActionText("use"), c.use, Theme.ActionText("unsorted"), c.unsorted))
    tip:AddLine("Click: open bag triage", 0.7, 0.7, 0.7)
    tip:AddLine("Right-click: delete the next tossed stack", 0.7, 0.7, 0.7)
    if ns.atMerchant then
        tip:AddLine("Shift-click: sell tossed items", 0.7, 0.7, 0.7)
    end
end

local function makeButton(parent, size)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(size, size)
    W.Skin(button, Theme.bgRaised)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture(ns.ICON)
    button.count = W.Text(button, 10, Theme.text, "RIGHT")
    W.SetFont(button.count, 10, "OUTLINE")
    button.count:SetPoint("BOTTOMRIGHT", 1, 0)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            ns.DeleteNext()
        elseif IsShiftKeyDown() and ns.atMerchant then
            ns.SellTossed()
        else
            ns.Window.Toggle()
        end
    end)
    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(Theme.accent))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        buttonTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(Theme.border))
        GameTooltip:Hide()
    end)
    ns.OnRefresh(function()
        local pending = ns.counts.toss + ns.counts.flag
        button.count:SetText(pending > 0 and pending or "")
    end)
    return button
end

-- Baganator -----------------------------------------------------------------

local function setupBaganator()
    local api = _G.Baganator and _G.Baganator.API
    if not api then
        return false
    end
    if api.RegisterRegion then
        local button = makeButton(UIParent, 22)
        local ok = pcall(api.RegisterRegion, "packRat", "packrat", "backpack", "bottom_left", button)
        if not ok then
            button:Hide()
        end
    end
    if api.RegisterCornerWidget then
        pcall(api.RegisterCornerWidget, "packRat", "packrat",
            function(corner, details)
                local status = ns.StatusFor(details and details.itemID)
                local look = status and Theme.ACTION[status.action]
                if not (look and look.icon) then
                    return false
                end
                corner.texture:SetTexture(look.icon)
                return true
            end,
            function(itemButton)
                local corner = CreateFrame("Frame", nil, itemButton)
                corner:SetSize(14, 14)
                corner.texture = corner:CreateTexture(nil, "OVERLAY")
                corner.texture:SetAllPoints()
                return corner
            end,
            { corner = "top_left", priority = 1 }, true)
    end
    if api.RegisterJunkPlugin then
        pcall(api.RegisterJunkPlugin, "packRat", "packrat", function(_, _, itemID)
            local status = ns.StatusFor(itemID)
            return status and status.action == "toss" or false
        end)
    end
    -- Baganator's upgrade arrow on gear packRat says to "use" (equip).
    if api.RegisterUpgradePlugin then
        pcall(api.RegisterUpgradePlugin, "packRat (Use verdicts)", "packrat", function(itemLink)
            local itemID = itemLink and tonumber(itemLink:match("item:(%d+)"))
            local item = itemID and ns.byID[itemID]
            local status = ns.StatusFor(itemID)
            return item ~= nil and item.equipLoc ~= nil and status ~= nil and status.action == "use"
        end)
    end
    if api.RequestItemButtonsRefresh then
        ns.OnRefresh(function() api.RequestItemButtonsRefresh() end)
    end
    return true
end

-- Floating button (no Baganator) ------------------------------------------------

local function setupFloating()
    local button = makeButton(UIParent, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", button.StartMoving)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.settings.buttonPos = { point, relPoint, x, y }
    end)
    local pos = ns.db.settings.buttonPos
    if pos then
        button:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 120)
    end
    ns.OnRefresh(function()
        button:SetShown(ns.db.settings.floatingButton)
    end)
    button:SetShown(ns.db.settings.floatingButton)
end

-- Tooltips --------------------------------------------------------------------

local function addTooltipLine(tooltip)
    if not ns.db.settings.tooltips or not tooltip.GetItem then
        return
    end
    local _, link = tooltip:GetItem()
    local itemID = link and tonumber(link:match("item:(%d+)"))
    local status = ns.StatusFor(itemID)
    if not status or status.action == "unsorted" then
        return
    end
    local reason = status.reason ~= "" and (" " .. Theme.Hex(Theme.muted) .. status.reason .. "|r") or ""
    tooltip:AddLine(Theme.Hex(Theme.accent) .. "packRat:|r " .. Theme.ActionText(status.action) .. reason, 1, 1, 1, true)
end

local function setupTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            if tooltip == GameTooltip or tooltip == ItemRefTooltip then
                addTooltipLine(tooltip)
            end
        end)
    elseif GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", addTooltipLine)
        if ItemRefTooltip then
            ItemRefTooltip:HookScript("OnTooltipSetItem", addTooltipLine)
        end
    end
end

function Integrations.Setup()
    local baganator = isLoaded("Baganator") and setupBaganator()
    if not baganator then
        setupFloating()
    end
    setupTooltips()
    ns.Broker.Build()
end

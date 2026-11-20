local _, ns = ...

local Theme = ns.Theme

-- LibDataBroker feed (Titan Panel, ElvUI / EllesmereUI data bars...) and a
-- LibDBIcon minimap button from the same object: "12 toss · 3g 40s".
-- The release zip embeds the libraries (.pkgmeta externals); a copy loaded
-- by another addon works too.
local Broker = {}
ns.Broker = Broker

local dataObject, icon

-- LibDBIcon names the button "LibDBIcon10_" .. this; it must not end in a
-- digit (EllesmereUI's minimap flyout skips such names).
local ICON_NAME = ns.TITLE .. "MinimapButton"

local function brokerText()
    local c = ns.counts
    if c.toss == 0 and c.flag == 0 then
        return Theme.Hex(Theme.muted) .. "bags tidy|r"
    end
    local parts = {}
    if c.toss > 0 then
        parts[#parts + 1] = Theme.ActionText("toss") .. " " .. c.toss
    end
    if c.flag > 0 then
        parts[#parts + 1] = Theme.ActionText("flag") .. " " .. c.flag
    end
    local value = ns.TossValue()
    if value > 0 then
        parts[#parts + 1] = Theme.Hex(Theme.muted) .. ns.FormatMoney(value) .. "|r"
    end
    return table.concat(parts, "  ")
end

function Broker.Build()
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    if not ldb then
        return
    end
    dataObject = ldb:NewDataObject(ns.TITLE, {
        type = "data source",
        label = ns.TITLE,
        text = ns.TITLE,
        icon = ns.ICON,
        OnClick = function(_, button)
            if button == "RightButton" then
                ns.DeleteNext()
            elseif IsShiftKeyDown() and ns.atMerchant then
                ns.SellTossed()
            else
                ns.Window.Toggle()
            end
        end,
        OnTooltipShow = function(tip)
            local c = ns.counts
            tip:AddLine(Theme.Hex(Theme.accent) .. ns.TITLE .. "|r")
            tip:AddLine(string.format("%s %d   %s %d   %s %d   %s %d", Theme.ActionText("toss"), c.toss,
                Theme.ActionText("flag"), c.flag, Theme.ActionText("use"), c.use, Theme.ActionText("unsorted"), c.unsorted))
            tip:AddLine("Tossed items sell for " .. ns.FormatMoney(ns.TossValue()), 0.7, 0.7, 0.7)
            tip:AddLine(" ")
            tip:AddLine(Theme.Hex(Theme.muted) .. "Click|r open bag triage")
            tip:AddLine(Theme.Hex(Theme.muted) .. "Right-click|r delete the next tossed stack")
            tip:AddLine(Theme.Hex(Theme.muted) .. "Shift-click|r at a vendor: sell tossed items")
        end,
    })
    icon = LibStub("LibDBIcon-1.0", true)
    if icon then
        ns.db.minimap = ns.db.minimap or {}
        ns.db.minimap.hide = not ns.db.settings.minimapButton
        icon:Register(ICON_NAME, dataObject, ns.db.minimap)
    end
    ns.OnRefresh(Broker.Update)
    Broker.Update()
end

function Broker.Update()
    if not dataObject then
        return
    end
    dataObject.text = brokerText()
    if icon then
        local show = ns.db.settings.minimapButton
        if show == ns.db.minimap.hide then
            ns.db.minimap.hide = not show
            if show then
                icon:Show(ICON_NAME)
            else
                icon:Hide(ICON_NAME)
            end
        end
    end
end

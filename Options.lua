local _, ns = ...

local Theme, W = ns.Theme, ns.W

-- Settings window (/packrat options, or Options in the main window).
local Options = {}
ns.Options = Options

local frame

local function setting(key, after)
    return function() return ns.db.settings[key] end, function(value)
        ns.db.settings[key] = value
        if after then after() end
        ns.Refresh()
    end
end

local function build()
    frame = W.Window("packRatOptions", 420, 330, "Options")
    frame.toggles = {}
    local y = -44
    local function note(text)
        local fs = W.Text(frame, 11, Theme.muted)
        fs:SetPoint("TOPLEFT", 40, y + 2)
        fs:SetPoint("RIGHT", -16, 0)
        fs:SetText(text)
        y = y - 18
    end
    local function toggle(label, key, help, after)
        local get, set = setting(key, after)
        local t = W.Toggle(frame, label, get, set)
        t:SetWidth(360)
        t:SetPoint("TOPLEFT", 16, y)
        y = y - 22
        if help then note(help) end
        frame.toggles[#frame.toggles + 1] = t
    end

    toggle("Sell tossed items when a vendor opens", "autoSell",
        "Up to 12 stacks, all in buyback. Skips agent-only tosses.")
    toggle("List a quest's leftovers after turn-in or abandon", "turnInPrompt")
    toggle("Toss gray items automatically", "tossGrays", nil, ns.Judge)
    toggle("Packrat line in item tooltips", "tooltips")
    toggle("Minimap button", "minimapButton")
    toggle("Floating button (when Baganator isn't loaded)", "floatingButton")

    local label = W.Text(frame, 12)
    label:SetPoint("TOPLEFT", 16, y - 8)
    label:SetText("Flag quest items when their quest is")
    local stepper = W.Stepper(frame, 130, W.Range(0, 20), function(v)
        return v == 0 and "gray" or (v .. "+ below you")
    end, function() return ns.db.settings.lowQuestGap end, function(v)
        ns.db.settings.lowQuestGap = v
        ns.Judge()
    end)
    stepper:SetPoint("LEFT", label, "RIGHT", 10, 0)
    frame.stepper = stepper
    y = y - 34

    local protectedLabel = W.Text(frame, 11, Theme.muted)
    protectedLabel:SetPoint("TOPLEFT", 16, y - 6)
    protectedLabel:SetPoint("RIGHT", -16, 0)
    frame.protectedLabel = protectedLabel
end

function Options.Update()
    if not (frame and frame:IsShown()) then
        return
    end
    for _, t in ipairs(frame.toggles) do
        t:Update()
    end
    frame.stepper:Update()
    local n = 0
    for _ in pairs(ns.db.protected) do n = n + 1 end
    frame.protectedLabel:SetText(string.format("Never-toss list: %s (Lock in the main window, /packrat protect, or a key binding).", ns.Plural(n, "item")))
end

function Options.Open()
    if not frame then
        build()
    end
    frame:Show()
    Options.Update()
end

ns.OnRefresh(Options.Update)

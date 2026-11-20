local _, ns = ...

local Theme = ns.Theme
local W = {}
ns.W = W

W.FLAT = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = { bgFile = W.FLAT, edgeFile = W.FLAT, edgeSize = 1 }

function W.Skin(frame, bg, border)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(unpack(bg or Theme.bg))
    frame:SetBackdropBorderColor(unpack(border or Theme.border))
end

function W.Panel(parent, bg)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    W.Skin(frame, bg)
    return frame
end

-- Falls back to the game font if the theme font path doesn't load.
function W.SetFont(fontString, size, flags)
    fontString:SetFont(Theme.font, size, flags or "")
    if not fontString:GetFont() then
        fontString:SetFont(STANDARD_TEXT_FONT, size, flags or "")
    end
end

function W.Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    W.SetFont(fs, size or 12)
    fs:SetTextColor(unpack(color or Theme.text))
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

function W.Line(parent, color)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(color or Theme.hairline))
    line:SetHeight(1)
    return line
end

function W.Tooltip(frame, build)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        build(GameTooltip)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function buttonColors(button)
    local bg = button.selected and Theme.bgHover or (button.hover and Theme.bgHover or Theme.bgRaised)
    button:SetBackdropColor(unpack(bg))
    button:SetBackdropBorderColor(unpack((button.hover or button.selected) and Theme.accent or Theme.border))
    button.text:SetTextColor(unpack(button.selected and Theme.accent or Theme.text))
end

function W.Button(parent, label, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height or 22)
    W.Skin(button, Theme.bgRaised)
    button.text = W.Text(button, 12, Theme.text, "CENTER")
    button.text:SetPoint("CENTER")
    button.text:SetText(label)
    button:SetScript("OnEnter", function(self)
        self.hover = true
        buttonColors(self)
    end)
    button:SetScript("OnLeave", function(self)
        self.hover = false
        buttonColors(self)
    end)
    button:SetScript("OnClick", function(self, ...)
        if not self.disabled then
            onClick(self, ...)
        end
    end)
    function button:SetDisabled(disabled)
        self.disabled = disabled
        self:SetAlpha(disabled and 0.4 or 1)
    end
    function button:SetSelected(selected)
        self.selected = selected
        buttonColors(self)
    end
    function button:SetLabel(text)
        self.text:SetText(text)
    end
    return button
end

-- Square button showing a game texture instead of a word; the word and an
-- explanation go in its tooltip. Unselected icons are dimmed so a selected
-- one stands out. tooltip = function(button) -> title, description.
function W.IconButton(parent, size, texture, fallback, tooltip, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(size, size)
    W.Skin(button, Theme.bgRaised)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 3, -3)
    button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.label = W.Text(button, 10, Theme.text, "CENTER")
    button.label:SetPoint("CENTER")
    local function paint(self)
        local lit = self.hover or self.selected
        self:SetBackdropColor(unpack(lit and Theme.bgHover or Theme.bgRaised))
        self:SetBackdropBorderColor(unpack(lit and Theme.accent or Theme.border))
        self.icon:SetAlpha(lit and 1 or 0.6)
    end
    function button:SetIcon(path, text)
        -- Fall back to a short word if the client doesn't have the texture.
        local ok = self.icon:SetTexture(path)
        local missing = ok == false
        self.icon:SetShown(not missing)
        self.label:SetText(missing and (text or fallback) or "")
    end
    function button:SetSelected(selected)
        self.selected = selected
        paint(self)
    end
    function button:SetDisabled(disabled)
        self.disabled = disabled
        self:SetAlpha(disabled and 0.4 or 1)
    end
    button:SetScript("OnEnter", function(self)
        self.hover = true
        paint(self)
        local title, text = tooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, 1, 1, 1)
        if text then
            GameTooltip:AddLine(text, 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        self.hover = false
        paint(self)
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(self, ...)
        if not self.disabled then
            onClick(self, ...)
        end
    end)
    button:SetIcon(texture)
    paint(button)
    return button
end

-- [-] value [+]  over a fixed list of values.
function W.Stepper(parent, width, values, format, get, set)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, 22)
    local value = W.Text(frame, 12, Theme.text, "CENTER")
    value:SetPoint("LEFT", 20, 0)
    value:SetPoint("RIGHT", -20, 0)

    local function indexOf(v)
        local best, bestDiff = 1, math.huge
        for i, candidate in ipairs(values) do
            if math.abs(candidate - v) < bestDiff then
                best, bestDiff = i, math.abs(candidate - v)
            end
        end
        return best
    end
    local function step(delta)
        local i = math.max(1, math.min(#values, indexOf(get()) + delta))
        set(values[i])
        frame:Update()
    end

    local minus = W.Button(frame, "-", 18, 22, function() step(-1) end)
    minus:SetPoint("LEFT")
    local plus = W.Button(frame, "+", 18, 22, function() step(1) end)
    plus:SetPoint("RIGHT")
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) step(delta) end)

    function frame:Update()
        value:SetText(format(get()))
    end
    frame:Update()
    return frame
end

function W.Range(from, to, by)
    local list = {}
    for v = from, to, by or 1 do
        list[#list + 1] = v
    end
    return list
end

function W.Toggle(parent, label, get, set)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(220, 20)
    local box = W.Panel(button, Theme.bgRaised)
    box:SetSize(14, 14)
    box:SetPoint("LEFT")
    local check = box:CreateTexture(nil, "OVERLAY")
    check:SetPoint("TOPLEFT", 3, -3)
    check:SetPoint("BOTTOMRIGHT", -3, 3)
    local text = W.Text(button, 12)
    text:SetPoint("LEFT", box, "RIGHT", 8, 0)
    text:SetText(label)

    function button:Update()
        check:SetColorTexture(unpack(Theme.accent))
        check:SetShown(get())
    end
    button:SetScript("OnClick", function(self)
        set(not get())
        self:Update()
    end)
    button:SetScript("OnEnter", function() box:SetBackdropBorderColor(unpack(Theme.accent)) end)
    button:SetScript("OnLeave", function() box:SetBackdropBorderColor(unpack(Theme.border)) end)
    button:Update()
    return button
end

-- Movable dialog with a title bar and close button; closes on Escape.
function W.Window(globalName, width, height, title)
    local frame = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    W.Skin(frame)
    frame:Hide()
    tinsert(UISpecialFrames, globalName)

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(30)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local divider = W.Line(frame, Theme.border)
    divider:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
    divider:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT")

    local logo = bar:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ns.ICON)
    logo:SetSize(20, 20)
    logo:SetPoint("LEFT", 8, 0)
    frame.title = W.Text(bar, 13)
    frame.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    frame.title:SetText(Theme.Hex(Theme.accent) .. ns.TITLE .. "|r" .. (title and (Theme.Hex(Theme.muted) .. "  ·  " .. title .. "|r") or ""))
    frame.subtitle = W.Text(bar, 11, Theme.muted, "RIGHT")
    frame.subtitle:SetPoint("RIGHT", -36, 0)

    local close = W.Button(bar, "x", 20, 20, function() frame:Hide() end)
    close:SetPoint("RIGHT", -6, 0)
    return frame
end

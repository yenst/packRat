local _, ns = ...

local Theme, W = ns.Theme, ns.W

-- Copy/paste window: the export for the agent, and the agent's reply coming back.
local ExportWindow = {}
ns.ExportWindow = ExportWindow

local WIDTH, HEIGHT = 620, 460
local window
local mode = "export"

local function runImport()
    local result, err = ns.Export.ReadVerdicts(window.edit:GetText())
    if not result then
        window.status:SetText(Theme.Hex(Theme.bad) .. err .. "|r")
        return
    end
    ns.ImportVerdicts(result)
    local unknown = 0
    for id in pairs(result.verdicts) do
        if not ns.byID[id] then
            unknown = unknown + 1
        end
    end
    local c = ns.counts
    local msg = string.format("Imported %s. Toss %d · Flag %d · Use %d · Keep %d.",
        ns.Plural(result.count, "verdict"), c.toss, c.flag, c.use, c.keep)
    if unknown > 0 then
        msg = msg .. string.format(" %d no longer in your bags.", unknown)
    end
    ns.Print(msg)
    window:Hide()
    ns.Window.Open("toss")
end

local function build()
    window = W.Window("packRatExport", WIDTH, HEIGHT, "Agent")
    window:SetFrameStrata("FULLSCREEN_DIALOG")

    window.hint = W.Text(window, 11, Theme.muted)
    window.hint:SetPoint("TOPLEFT", 16, -42)
    window.hint:SetPoint("RIGHT", -16, 0)

    local box = W.Panel(window, { 0, 0, 0, 0.5 })
    box:SetPoint("TOPLEFT", 16, -64)
    box:SetPoint("BOTTOMRIGHT", -16, 52)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFont("Fonts\\ARIALN.TTF", 12, "")
    edit:SetTextColor(unpack(Theme.text))
    edit:SetWidth(WIDTH - 50)
    edit:SetScript("OnEscapePressed", function() window:Hide() end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        -- The export view is read-only; typing restores the export.
        if userInput and mode ~= "import" then
            self:SetText(window.exported)
            self:HighlightText()
        end
    end)
    edit:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local top, visible = scroll:GetVerticalScroll(), scroll:GetHeight()
        y = -y
        if y < top then
            scroll:SetVerticalScroll(y)
        elseif y + height > top + visible then
            scroll:SetVerticalScroll(y + height - visible)
        end
    end)
    scroll:SetScrollChild(edit)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 48
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), target)))
    end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    window.edit = edit

    window.status = W.Text(window, 11)
    window.status:SetPoint("BOTTOMLEFT", 16, 22)
    window.status:SetPoint("RIGHT", window, "RIGHT", -150, 0)
    window.action = W.Button(window, "", 120, 26, function()
        if mode == "import" then
            runImport()
        else
            edit:SetFocus()
            edit:HighlightText()
        end
    end)
    window.action:SetPoint("BOTTOMRIGHT", -16, 14)
end

local function setTitle(title)
    window.title:SetText(Theme.Hex(Theme.accent) .. ns.TITLE .. "|r" .. Theme.Hex(Theme.muted) .. "  ·  " .. title .. "|r")
end

function ExportWindow.Update()
    window.status:SetText("")
    setTitle(mode == "text" and window.textTitle or "Agent")
    if mode == "text" then
        window.hint:SetText(window.textHint or "")
        window.exported = window.text or ""
        window.edit:SetText(window.exported)
        window.edit:SetFocus()
        window.edit:HighlightText()
        window.action:SetLabel("Select all")
    elseif mode == "export" then
        window.hint:SetText("Already selected: Ctrl+C, then paste it into any AI chat or agent. Its reply goes into Import reply.")
        -- Never show an empty box silently: if building the export fails,
        -- show the error so it can be reported.
        local ok, result = xpcall(function() return ns.Export.ToJSON(ns.Snapshot()) end, function(err)
            return tostring(err) .. "\n" .. (debugstack and debugstack(2, 8, 0) or "")
        end)
        if not ok then
            window.exported = "Packrat export failed. Copy this and send it over:\n\n" .. result
            window.edit:SetText(window.exported)
            window.status:SetText(Theme.Hex(Theme.bad) .. "Export failed; the error is in the box.|r")
            ns.Print("Export failed: " .. tostring(result):match("^[^\n]*"))
            return
        end
        window.exported = result
        window.edit:SetText(window.exported)
        window.edit:SetFocus()
        window.edit:HighlightText()
        window.action:SetLabel("Select all")
        window.status:SetText(Theme.Hex(Theme.muted) .. string.format("%s, %s, %d characters.",
            ns.Plural(#ns.items, "item"), ns.Plural(#ns.Quests.list, "quest"), #window.exported) .. "|r")
    else
        window.hint:SetText("Paste the agent's whole reply (Ctrl+V). Your own Keep / Toss choices stay.")
        window.edit:SetText("")
        window.edit:SetFocus()
        window.action:SetLabel("Import")
    end
end

-- Read-only text (history, debug report) in the same copyable box.
function ExportWindow.ShowText(title, hint, text)
    if not window then
        build()
    end
    mode = "text"
    window.textTitle, window.textHint, window.text = title, hint, text
    window:Show()
    ExportWindow.Update()
end

function ExportWindow.Open(newMode)
    if not window then
        build()
    end
    mode = newMode
    window:Show()
    ExportWindow.Update()
end

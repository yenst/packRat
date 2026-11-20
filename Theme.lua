local _, ns = ...

-- Flat dark panels, 1px black borders and one accent colour, in the style of
-- EllesmereUI. When EllesmereUI is loaded, its accent, font and panel colour
-- are used instead of the defaults below.
local Theme = {
    bg = { 0.05, 0.07, 0.09, 0.94 },
    bgRaised = { 0.09, 0.11, 0.14, 1 },
    bgHover = { 0.13, 0.16, 0.20, 1 },
    border = { 0, 0, 0, 1 },
    hairline = { 1, 1, 1, 0.06 },
    text = { 0.92, 0.93, 0.95, 1 },
    muted = { 0.55, 0.58, 0.63, 1 },
    accent = { 0.95, 0.66, 0.23, 1 },
    warn = { 1, 0.71, 0.25, 1 },
    bad = { 1, 0.36, 0.36, 1 },
    font = STANDARD_TEXT_FONT,
    ellesmere = false,
}
ns.Theme = Theme

local function readColor(c)
    if type(c) ~= "table" then
        return nil
    end
    local r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        return r, g, b
    end
end

function Theme.Load()
    local eui = _G.EllesmereUI
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUI")
    if not (loaded and type(eui) == "table") then
        return
    end
    Theme.ellesmere = true
    local r, g, b = readColor(eui.ELLESMERE_GREEN)
    if r then
        Theme.accent = { r, g, b, 1 }
    end
    r, g, b = readColor(eui.DARK_BG)
    if r then
        Theme.bg = { r, g, b, 0.94 }
    end
    if type(eui.GetFontPath) == "function" then
        local ok, path = pcall(eui.GetFontPath, "packRat")
        if ok and type(path) == "string" and path ~= "" then
            Theme.font = path
        end
    end
end

function Theme.Hex(color)
    return string.format("|cff%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
end

-- How each action looks in lists, badges and bag icons.
Theme.ACTION = {
    keep = { label = "Keep", color = { 0.55, 0.58, 0.63, 1 }, icon = nil },
    use = { label = "Use", color = { 0.30, 0.80, 0.45, 1 }, icon = "Interface\\RaidFrame\\ReadyCheck-Ready" },
    flag = { label = "Flag", color = { 1, 0.82, 0.25, 1 }, icon = "Interface\\RaidFrame\\ReadyCheck-Waiting" },
    toss = { label = "Toss", color = { 1, 0.36, 0.36, 1 }, icon = "Interface\\RaidFrame\\ReadyCheck-NotReady" },
    unsorted = { label = "-", color = { 0.40, 0.42, 0.46, 1 }, icon = nil },
}

-- Button icons: textures every client has (Classic Era and Forever).
Theme.BUTTON = {
    lock = "Interface\\Buttons\\LockButton-Unlocked-Up",
    locked = "Interface\\Buttons\\LockButton-Locked-Up",
    keep = "Interface\\RaidFrame\\ReadyCheck-Ready",
    toss = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    delete = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
}

function Theme.ActionText(action)
    local a = Theme.ACTION[action] or Theme.ACTION.unsorted
    return Theme.Hex(a.color) .. a.label .. "|r"
end

local QUALITY_FALLBACK = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000" }

function Theme.QualityHex(quality)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    if c and c.hex then
        return c.hex
    end
    return "|c" .. (QUALITY_FALLBACK[quality or 1] or "ffffffff")
end

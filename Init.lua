local ADDON, ns = ...

ns.name = ADDON
ns.TITLE = "Packrat"
ns.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon" -- 64x64

local listeners = {}

-- UI pieces subscribe here; Core calls ns.Refresh() whenever bag data or
-- verdicts change.
function ns.OnRefresh(fn)
    listeners[#listeners + 1] = fn
end

function ns.Refresh()
    for _, fn in ipairs(listeners) do
        fn()
    end
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|T" .. ns.ICON .. ":14:14|t |cfff2a93b" .. ns.TITLE .. "|r " .. msg)
end

-- 12345 copper -> "1g 23s 45c"
function ns.FormatMoney(copper)
    copper = math.floor(copper or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

function ns.Plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

-- Plain-Lua tests for packRat's non-UI modules. Run from the repo root:
--   lua5.1 tests/run.lua
date, time = os.date, os.time

local ns = {}
for _, file in ipairs({ "Init", "JSON", "Rules", "Export" }) do
    assert(loadfile(file .. ".lua"))("packRat", ns)
end
local Rules, Export, JSON = ns.Rules, ns.Export, ns.JSON

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end
local function eq(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function item(id, name, extra)
    local t = { id = id, name = name, quality = 1, count = 1, slots = { { bag = 0, slot = id % 16 + 1, count = 1 } }, sellPrice = 10 }
    for k, v in pairs(extra or {}) do
        t[k] = v
    end
    return t
end

local quests = {
    { id = 1, title = "Wolves of the Wood", level = 30, objectives = { "Wolf Pelt: 3/8" }, text = "Bring me 8 Wolf Pelts." },
    { id = 2, title = "Old Errand", level = 12, objectives = { "Dusty Letter: 0/1" }, text = "" },
    { id = 3, title = "The Lost Ring", level = 31, objectives = {}, text = "Find the Silver Ring near the lake." },
}
local byID = {}
for _, q in ipairs(quests) do byID[q.id] = q end
local function ctx(level, extra)
    local c = { level = level, quests = byID, gap = 0, tossGrays = true }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

test("quest colours follow the quest log", function()
    eq(Rules.QuestColor(35, 30, 5), "red")
    eq(Rules.QuestColor(33, 30, 5), "orange")
    eq(Rules.QuestColor(28, 30, 5), "yellow")
    eq(Rules.QuestColor(26, 30, 5), "green")
    eq(Rules.QuestColor(24, 30, 5), "gray")
end)

test("low quests: gray by default, or a fixed gap", function()
    eq(Rules.IsLowQuest({ level = 12 }, 30, 0, 8), true, "gray")
    eq(Rules.IsLowQuest({ level = 25 }, 30, 0, 8), false, "green")
    eq(Rules.IsLowQuest({ level = 25 }, 30, 5, 8), true, "gap 5")
    eq(Rules.IsLowQuest({ level = 26 }, 30, 5, 8), false, "gap 5, 4 below")
end)

test("items are linked to quests by objective and quest text", function()
    local items = { item(10, "Wolf Pelt"), item(11, "Dusty Letter"), item(12, "Silver Ring"), item(13, "Linen Cloth"), item(14, "Ash") }
    Rules.LinkQuests(items, quests)
    eq(items[1].quests[1], 1, "pelt")
    eq(items[2].quests[1], 2, "letter")
    eq(items[3].quests[1], 3, "ring via text")
    eq(#items[4].quests, 0, "cloth")
    eq(#items[5].quests, 0, "short names never match")
    eq(quests[1].items[1], 10)
end)

test("rules: keep for active quests, flag for low ones", function()
    local items = { item(10, "Wolf Pelt", { questItem = true }), item(11, "Dusty Letter", { questItem = true }) }
    Rules.LinkQuests(items, quests)
    local c = ctx(30, { greenRange = 8 })
    eq(Rules.Judge(items[1], c).action, "keep")
    local low = Rules.Judge(items[2], c)
    eq(low.action, "flag")
    assert(low.reason:find("Old Errand"), low.reason)
end)

-- A tiny quest database in the generated shape, plus which quests are turned in.
local db = {
    quests = { [1] = { "Wolves of the Wood", 30 }, [2] = { "Old Errand", 12 }, [50] = { "Done Deal", 28 },
        [51] = { "Far Future", 40 }, [52] = { "Ancient History", 10 }, [53] = { "Cloth Turn-in", 30, 1 },
        [54] = { "Read Me", 31 } },
    uses = { [60] = { 1 }, [61] = { 50 }, [62] = { 51 }, [63] = { 52 }, [64] = { 53 }, [65] = { 50 }, [66] = { 50, 51 } },
    starts = { [70] = 50, [71] = 54 },
}
local done = { [50] = true, [53] = true }
local function dbctx(level)
    return ctx(level or 30, { greenRange = 8, db = db, isDone = function(id) return done[id] == true end })
end
local function qitem(id, name, extra)
    local t = item(id, name, { questItem = true, quests = {}, noValue = true, sellPrice = 0 })
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

test("quest data: keeps items a logged quest needs, even without a name match", function()
    local r = Rules.Judge(qitem(60, "Gahz'ridian Detector"), dbctx())
    eq(r.action, "keep")
    assert(r.reason:find("Wolves of the Wood"), r.reason)
end)

test("quest data: tosses quest items only when every quest is done", function()
    local r = Rules.Judge(qitem(61, "Old Token"), dbctx())
    eq(r.action, "toss", "single done quest")
    eq(r.questDone, true)
    eq(Rules.Judge(qitem(66, "Shared Token"), dbctx()).action, "flag", "one done, one open")
    eq(Rules.Judge(qitem(64, "Cloth Token"), dbctx()).action, "flag", "repeatable never counts as done")
    eq(Rules.Judge(qitem(70, "Done Starter", { startsQuest = true }), dbctx()).action, "toss", "starter of a done quest")
end)

test("quest data: open quests are flagged, low ones say so", function()
    local open = Rules.Judge(qitem(62, "Future Key"), dbctx())
    eq(open.action, "flag")
    eq(open.openQuest, true)
    local low = Rules.Judge(qitem(63, "Old Map"), dbctx())
    eq(low.lowQuest, true)
    assert(low.reason:find("low%-level"), low.reason)
    local starter = Rules.Judge(qitem(71, "Letter", { startsQuest = true }), dbctx())
    eq(starter.action, "flag")
    assert(starter.reason:find("Read Me"), starter.reason)
end)

test("quest data: ordinary items aren't junk because a done quest once asked for them", function()
    eq(Rules.Judge(item(65, "Linen Cloth", { quests = {} }), dbctx()), nil)
end)

test("quest data: agent's toss on a quest item needs the data to agree", function()
    local verdict = { action = "toss", reason = "useless", source = "agent" }
    eq(Rules.Status(qitem(61, "Old Token"), verdict, dbctx()).action, "toss", "done: allowed")
    eq(Rules.Status(qitem(62, "Future Key"), verdict, dbctx()).action, "flag", "open: flagged")
    eq(Rules.Status(qitem(99, "Mystery Item"), verdict, dbctx()).action, "flag", "no data: flagged")
    eq(Rules.Status(item(98, "Flavor Rock", { quests = {} }), verdict, dbctx()).action, "toss", "not a quest item")
end)

test("the generated quest data loads and covers known items", function()
    local data = {}
    assert(loadfile("QuestData.lua"))("packRat", data)
    local D = data.QuestData
    eq(D.given[9978][1], 3161, "Gahz'ridian Detector, handed out by its quest")
    eq(D.given[4650][1], 736, "Bel'dugur's Note, handed out by its quest")
    eq(D.starts[8623], 351, "OOX-17/TN Distress Beacon")
    eq(D.quests[3161][1], "Gahz'ridian")
end)

test("rules: orphan quest items and quest starters are flagged, grays tossed", function()
    local c = ctx(30)
    eq(Rules.Judge(item(20, "Strange Orb", { questItem = true, quests = {} }), c).action, "flag")
    eq(Rules.Judge(item(21, "Torn Page", { startsQuest = true, quests = {} }), c).action, "flag")
    eq(Rules.Judge(item(22, "Broken Fang", { quality = 0, quests = {} }), c).action, "toss")
    eq(Rules.Judge(item(22, "Broken Fang", { quality = 0, quests = {} }), ctx(30, { tossGrays = false })), nil)
    eq(Rules.Judge(item(23, "Nice Gloves", { rxpJunk = true, quests = {} }), c).action, "toss")
    eq(Rules.Judge(item(24, "Copper Bar", { quests = {} }), c), nil)
end)

test("status: manual beats agent beats rules; agent can't toss active quest items", function()
    local pelt = item(10, "Wolf Pelt", { questItem = true })
    local copper = item(24, "Copper Bar", { quests = {} })
    Rules.LinkQuests({ pelt }, quests)
    local c = ctx(30, { greenRange = 8 })
    eq(Rules.Status(copper, nil, c).action, "unsorted")
    eq(Rules.Status(copper, { action = "toss", source = "agent" }, c).action, "toss")
    eq(Rules.Status(copper, { action = "keep", source = "manual" }, c).action, "keep")
    local s = Rules.Status(pelt, { action = "toss", reason = "junk", source = "agent" }, c)
    eq(s.action, "flag", "downgraded")
    eq(Rules.Status(pelt, { action = "toss", source = "manual" }, c).action, "toss", "you can still toss it")
    eq(Rules.Status(item(6948, "Hearthstone"), { action = "toss", source = "agent" }, c).action, "keep", "protected")
end)

test("delete order: no-value items first, then cheapest; never rare", function()
    local items = {
        item(30, "Cheap", { sellPrice = 5 }),
        item(31, "Worthless", { noValue = true, sellPrice = 0 }),
        item(32, "Epic Junk", { quality = 4, sellPrice = 0 }),
        item(33, "Kept", { sellPrice = 0 }),
    }
    local statuses = { [30] = { action = "toss" }, [31] = { action = "toss" }, [32] = { action = "toss" }, [33] = { action = "keep" } }
    eq(Rules.NextToDelete(items, statuses).id, 31)
    statuses[31] = { action = "keep" }
    eq(Rules.NextToDelete(items, statuses).id, 30)
    statuses[30] = { action = "keep" }
    eq(Rules.NextToDelete(items, statuses), nil, "rare+ is skipped")
end)

test("sell list skips items without value and stops at the limit", function()
    local items = { item(40, "A", { slots = { { bag = 0, slot = 1, count = 1 }, { bag = 0, slot = 2, count = 1 } } }), item(41, "B", { noValue = true }) }
    local statuses = { [40] = { action = "toss" }, [41] = { action = "toss" } }
    eq(#Rules.ToSell(items, statuses, 12), 2)
    eq(#Rules.ToSell(items, statuses, 1), 1)
end)

test("export holds the instructions, character, quests and items", function()
    local items = { item(10, "Wolf Pelt", { questItem = true }) }
    Rules.LinkQuests(items, quests)
    local c = ctx(30, { greenRange = 8 })
    local text = Export.ToJSON({
        character = { name = "Tester", level = 30 }, settings = { lowQuestGap = 0 },
        quests = quests, items = items, statuses = { [10] = Rules.Status(items[1], nil, c) }, equipped = {}, ctx = c,
    })
    local doc = assert(JSON.Decode(text))
    eq(doc.format, "packrat-export")
    assert(doc._instructions:find("packrat%-verdicts"), "instructions name the reply format")
    eq(text:sub(1, 17), '{"_instructions":', "instructions come first")
    eq(doc.items[1].current.action, "keep")
    eq(doc.items[1].questLinks[1].id, 1)
    eq(doc.items[1].questLinks[1].state, "log")
    eq(doc.quests[1].level, 12, "sorted by level")
    eq(doc.quests[1].color, "gray")
end)

test("reading agent's reply, fenced and with chatter around it", function()
    local reply = 'Here you go:\n```json\n{"format":"packrat-verdicts","version":1,"summary":"Sold the junk",'
        .. '"items":[{"id":2589,"action":"Toss","reason":"No tailoring"},{"id":10,"action":"keep"},{"id":"x","action":"toss"},{"id":11,"action":"burn"}]}\n```\nEnjoy!'
    local result = assert(Export.ReadVerdicts(reply))
    eq(result.count, 2)
    eq(result.skipped, 2)
    eq(result.verdicts[2589].action, "toss")
    eq(result.summary, "Sold the junk")
end)

test("reading rejects the export itself and garbage", function()
    local _, err = Export.ReadVerdicts('{"format":"packrat-export","items":[]}')
    assert(err and err:find("export"), err)
    _, err = Export.ReadVerdicts("no json here")
    assert(err, "no json")
    _, err = Export.ReadVerdicts('{"items":[]}')
    assert(err and err:find("no usable"), err)
end)

-- Faction, class and the other new safeguards -----------------------------------
local HORDE_UNDEAD, PALADIN_BIT = 16, 2
local ALLIANCE = 1 + 4 + 8 + 64 + 4294967296
local HORDE = 2 + 16 + 32 + 128 + 8589934592
local db2 = {
    quests = { [80] = { "Alliance Bounty", 45, 0, ALLIANCE }, [81] = { "Horde Bounty", 45, 0, HORDE },
        [82] = { "Mage Only", 40, 0, 0, 128 }, [83] = { "Handed Out", 40 }, [84] = { "Writ", 60 } },
    uses = { [90] = { 80, 81 }, [91] = { 80 }, [92] = { 82 }, [94] = { 84 } },
    given = { [93] = { 83 } },
    starts = { [94] = 84 },
}
local function ctx2(extra)
    local c = ctx(45, { greenRange = 8, db = db2, raceBit = HORDE_UNDEAD, classBit = PALADIN_BIT, class = "PALADIN",
        isDone = function(id) return id == 83 end })
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

test("masks above 32 bits", function()
    eq(Rules.HasBit(HORDE, 8589934592), true, "skyborne horde bit")
    eq(Rules.HasBit(HORDE, 16), true, "undead")
    eq(Rules.HasBit(ALLIANCE, 16), false)
end)

test("quests your race or class can't take are ignored", function()
    local links = Rules.QuestLinks(qitem(90, "Troll Necklace"), ctx2())
    eq(#links, 1)
    eq(links[1].id, 81, "only the Horde quest")
    local r = Rules.Judge(qitem(91, "Alliance Token"), ctx2())
    eq(r.action, "flag")
    eq(r.otherFaction, true)
    eq(#Rules.QuestLinks(qitem(92, "Mage Thing"), ctx2()), 0, "class mask")
    eq(Rules.Status(qitem(91, "Alliance Token"), { action = "toss", source = "agent" }, ctx2()).action, "toss",
        "agent may toss items only other factions can use")
end)

test("items a quest only handed out say so", function()
    local r = Rules.Judge(qitem(93, "Old Letter"), ctx2())
    eq(r.action, "toss")
    assert(r.reason:find("Handed out"), r.reason)
end)

test("tradeable quest starters: flagged, but agent may toss them", function()
    local writ = qitem(94, "Craftsman's Writ", { startsQuest = true, questItem = false, bound = false })
    local r = Rules.Judge(writ, ctx2())
    eq(r.action, "flag")
    eq(r.tradeable, true)
    assert(r.reason:find("tradeable"), r.reason)
    eq(Rules.Status(writ, { action = "toss", source = "agent" }, ctx2()).action, "toss")
    local bound = qitem(94, "Bound Letter", { startsQuest = true, questItem = false, bound = true })
    eq(Rules.Status(bound, { action = "toss", source = "agent" }, ctx2()).action, "flag", "soulbound starter stays flagged")
end)

test("equipment sets are kept, even against agent", function()
    local ring = item(95, "Purified Ring", { quests = {}, sets = { "prot" } })
    eq(Rules.Judge(ring, ctx2()).action, "keep")
    eq(Rules.Status(ring, { action = "toss", source = "agent" }, ctx2()).action, "flag")
    eq(Rules.Status(ring, { action = "toss", source = "manual" }, ctx2()).action, "toss", "your own toss still works")
end)

test("gear the class can never use", function()
    local bow = item(96, "Bow", { quests = {}, equipLoc = "INVTYPE_RANGED", classID = 2, subClassID = 2, bound = true })
    local r = Rules.Judge(bow, ctx2())
    eq(r.action, "toss")
    assert(r.reason:find("Bow"), r.reason)
    bow.bound = false
    eq(Rules.Judge(bow, ctx2()).action, "flag", "BoE: sell it")
    local mail = item(97, "Mail Bracers", { quests = {}, equipLoc = "INVTYPE_WRIST", classID = 4, subClassID = 3, bound = true })
    eq(Rules.Judge(mail, ctx2()), nil, "paladins wear mail")
    local robe = item(98, "Mage Robe", { quests = {}, equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 1, bound = true, classes = { MAGE = true } })
    eq(Rules.Judge(robe, ctx2()).action, "toss", "class-restricted")
end)

test("the never-toss list beats everything and blocks selling and deleting", function()
    local junk = item(99, "Lucky Rock", { quality = 0, quests = {}, sellPrice = 5 })
    local c = ctx2({ protected = { [99] = true } })
    local s = Rules.Status(junk, { action = "toss", source = "manual" }, c)
    eq(s.action, "keep")
    eq(s.source, "protected")
    local statuses = { [99] = { action = "toss" } }
    eq(Rules.NextToDelete({ junk }, statuses, { [99] = true }), nil)
    eq(#Rules.ToSell({ junk }, statuses, 12, { [99] = true }), 0)
    eq(#Rules.ToSell({ junk }, statuses, 12, {}), 1)
end)

test("auto-sell skips tosses only agent decided", function()
    local a, b = item(100, "A"), item(101, "B")
    local statuses = { [100] = { action = "toss", source = "agent" }, [101] = { action = "toss", source = "rule" } }
    local list = Rules.ToSell({ a, b }, statuses, 12, {}, true)
    eq(#list, 1)
    eq(list[1].item.id, 101)
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)

# packRat

Bag triage for WoW Forever and Classic Era. packRat sorts everything in your bags into **Keep**, **Use**, **Flag** or **Toss**, knows which quest every quest item belongs to, exports your bags for any AI agent (Claude, ChatGPT, ...) and imports its verdicts. Slash command: `/packrat` (or `/rat`).

## How it decides

For each item, the first of these that applies wins:

0. **Your never-toss list.** Use the Lock button in the window, `/packrat protect [item]`, or the key binding for the item under the mouse. Nothing overrides it: not the rules, not the agent, not your own Toss. It's account-wide. The Hearthstone is always on it.
1. **Your choice.** The Keep / Toss buttons in the window. Click the same button again to undo it.
2. **The agent's verdict**, from the last import. The agent can't toss on its own say-so:
   - a quest item whose quests aren't all done → flag;
   - an item in one of your equipment sets → flag.
3. **Built-in rules:**
   - **Quest items are judged by a quest database** (`QuestData.lua`, built from [QuestieDB](https://github.com/Questie/QuestieDB)'s Forever data). For each item it knows which quests need it, hand it out, or are started by it. It ignores quests your race or class can't take, then checks the rest against your quest log and your turned-in quests:
     - A quest in your log needs it → **Keep** ("Needed for Gahz'ridian (48)"), or "Handed out by …" if the quest only gave it to you.
     - That quest is gray, or N+ levels below you → **Flag**.
     - Every quest it belongs to is turned in, and none is repeatable → **Toss** ("Quest done: …"). This is the only way a quest item gets tossed automatically.
     - A quest it belongs to is neither in your log nor done → **Flag**: "not in your log yet", or "low-level".
     - A quest starter you can trade, like a Craftsman's Writ → **Flag** ("sell or give it away"). The agent may toss these.
     - Only other races or classes can do its quests → **Flag**. The agent may toss these.
     - Quest items the database doesn't know → **Flag**.
   - In an equipment set (the tooltip's "Equipment Sets:" line) → **Keep**.
   - Soulbound gear your class can never use (armor type, weapon type, or "Classes:" line) → **Toss**. If it's BoE → **Flag** (sell it).
   - Marked as junk in RestedXP → **Toss**.
   - Gray quality → **Toss** (turn off in Options).
4. Otherwise the item is **Unsorted** until you or the agent decide.

## AI agent round trip

1. **Export for agent** (or `/packrat export`). Paste it into any AI chat or agent. The export starts with instructions for the agent, then:
   - your level, class, professions, money, bag space and RestedXP guide;
   - your quest log;
   - equipped gear;
   - your bank (via Syndicator);
   - every bag item, with its tooltip, linked quests (in log / done / open), equipment sets, never-toss flag, copies in your bank, mail and on alts, and Pawn's upgrade opinion.
2. The agent replies with a `packrat-verdicts` JSON block.
3. **Import reply** (or `/packrat import`) and paste the whole reply. A new import replaces the agent's previous verdicts. Your own choices stay.

## Cleaning up

- **After a turn-in or abandon**, a small window lists only that quest's leftovers, each with Delete and Keep buttons. Items another quest still needs don't show up. You can turn this off in Options.
- **Sell tossed** (at a vendor): sells up to 12 stacks per click, so they all stay in buyback.
- **Auto-sell** (Options, off by default): does the same when a vendor opens, but only for tosses from the rules or from you, never ones the agent alone decided.
- **Delete next**: deletes one tossed stack per click, starting with items that have no vendor value, then the cheapest. WoW only lets addons delete items on a click or key press. Rare and better items are never deleted this way; use a row's Delete button for those.
- **History** (button or `/packrat history`): every sale and delete, with the reason. Sold items can be bought back until you leave that vendor.

## Where it shows up

- **Baganator:**
  - a packRat button in the backpack (click: window, right-click: delete next, shift-click at a vendor: sell);
  - Flag / Toss / Use icons in an item corner;
  - the junk plugin;
  - the upgrade arrow on gear packRat says to use.
- **Minimap button and LDB feed** (Titan Panel, ElvUI / EllesmereUI data bars): "Toss 5 Flag 3 1g 20s". Without Baganator there's also a floating button.
- **Tooltips:** a "packRat: Toss — reason" line on items.
- **Key bindings** (Key Bindings → packRat): open the window, delete next, never-toss the item under the mouse.

## Commands

`/packrat` · `export` · `import` · `next` · `sell` · `protect [item]` · `history` · `options` · `autosell` · `gap <levels>` · `grays` · `button` · `clear` · `debug`

`/packrat debug` lists which game APIs the client has, plus what the quest-text calls return. WoW Forever shares retail's UI code, so it differs from Classic Era in places.

## Develop

```sh
tools/install.sh          # symlink the repo into AddOns/packRat for every Forever/Classic install; /reload picks up edits
tools/install.sh --copy   # copy the addon files instead
lua5.1 tests/run.lua      # rules, export, reply parsing, quest data
lua5.1 tests/smoke.lua    # whole addon against a mocked WoW API
lua5.1 tools/build-questdata.lua ~/path/to/QuestieDB Forever > QuestData.lua   # refresh the quest data
```

`tools/build-questdata.lua` reads a QuestieDB checkout: the raw Forever data plus its static corrections, in Questie's order (legacy → generated delta-base → traces → authored fixes). Dynamic per-character corrections are skipped. It evaluates the data files in a sandbox without `io`/`os`.

The libraries in `Libs/` (LibStub, CallbackHandler, LibDataBroker, LibDBIcon) are not in git; the packager pulls them in from the `.pkgmeta` externals. Without them the minimap button only appears if another addon has loaded LibDBIcon.

Release works like planTo60: push a `v*` tag and GitHub Actions runs the tests and packages the zip.

## License

GPL-3.0. `QuestData.lua` is derived from QuestieDB, which is GPL-3.0.

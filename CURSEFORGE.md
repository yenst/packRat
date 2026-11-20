# Packrat: bag triage that knows your quests

**Full bags, and no idea which quest items you can still throw away?** Packrat checks every item in your bags against your quest log, a quest database, your professions and your gear. It tells you what to **Keep**, **Use**, **Flag** or **Toss**, and why.

Made for **WoW Forever** and **Classic Era**.

## Quest items, sorted out

Packrat ships with a quest database of about 4,000 quests, built from QuestieDB's Forever data. For every quest item it knows which quests **need** it, **hand it out** or are **started** by it. It checks those quests against your quest log and the quests you've already turned in:

- **Keep:** a quest in your log needs it ("Needed for Gahz'ridian (48)").
- **Flag:** the quest has gone gray, or you haven't picked it up yet.
- **Toss:** every quest it belongs to is turned in ("Quest done: Hippogryph Muisek").
- Quests your race or class can't take are ignored, so Alliance turn-ins don't keep junk in a Horde bag.

**After you turn in or abandon a quest**, a small window pops up listing just that quest's leftovers, each with a Delete button.

## Ask an AI agent about the rest

Not sure about that recipe, the old gear or the flavor items? Click **Export for agent**, paste the text into any AI chat or agent (Claude, ChatGPT, …), and paste its reply back with **Import reply**.

The export includes your level, class, professions, quest log, equipped gear, bank (via Syndicator) and every item's tooltip, plus instructions for the agent. It answers with a keep / use / flag / toss verdict and a short reason for each item.

**The agent can't toss anything risky.** It can't toss a quest item whose quests aren't done, an item in one of your equipment sets, or anything on your never-toss list. Those verdicts turn into flags.

## Cleaning up

- **Sell tossed** at a vendor sells 12 stacks per click, so everything stays in buyback.
- **Auto-sell** when a vendor opens is optional and off by default. It only sells items you or Packrat's rules marked toss, never ones the agent alone decided.
- **Delete next** removes one tossed stack per click, starting with items that have no vendor value. Bind a key to it. Rare and better items are never deleted this way.
- **History** shows everything Packrat sold or deleted, and why.

## Safety first

- **Never-toss list:** lock any item and nothing will sell or delete it. Use the Lock button, `/packrat protect` or a key binding. It applies to all your characters.
- Gear in your **equipment sets** is always kept.
- The **Hearthstone** is always protected.
- Nothing is deleted without a click. WoW only allows one deleted stack per click anyway.

## Also

- **Baganator:** a Packrat button in the bag window, Toss / Flag / Use icons on items, Baganator's junk marking, and the upgrade arrow on gear to equip.
- **Minimap button and data-bar feed** (Titan Panel, ElvUI, EllesmereUI): "Toss 5 · Flag 3 · 1g 20s".
- **Tooltips:** "Packrat: Toss — Quest done: …"
- Soulbound gear your class can never use is marked toss. Gray items and items you marked as junk in RestedXP are too.
- **Pawn:** its upgrade opinion goes into the export, if it's installed.

## Commands

| Command | What it does |
|---|---|
| `/packrat` or `/rat` | Open the bag triage window |
| `/packrat export` / `import` | Export for an AI agent / paste its reply |
| `/packrat next` | Delete the next tossed stack |
| `/packrat sell` | Sell tossed items at an open vendor |
| `/packrat protect [item]` | Add or remove an item on the never-toss list |
| `/packrat history` | What was sold and deleted |
| `/packrat options` | Settings |
| `/packrat gap <levels>` | Flag quest items once their quest is this many levels below you (0 = when gray) |
| `/packrat debug` | Show which game APIs your client has (for bug reports) |

Key bindings: **Key Bindings → Packrat** (open window, delete next, never-toss the item under the mouse).

## Credits

The quest data is built from [QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0). Packrat is GPL-3.0 as well.

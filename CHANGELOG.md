# Changelog

## 1.0.2

- **New look:** a low-poly amber rat head replaces the old icon, in game (bag button, minimap, window title, chat, addon list) and as the CurseForge logo.
- **New name in game:** the addon now shows as "Packrat" instead of "packRat". Your settings, verdicts and never-toss list carry over, and the folder name is the same.

## 1.0.1

- **Icon buttons:** the Lock, Keep, Toss and Delete buttons in the triage window and the quest-leftovers prompt are now icons (padlock, tick, junk coin, red X). Hovering shows the name and what the button does.
- Icons stay dimmed until you hover them or they're your current choice, so your own locks and picks stand out.
- Delete keeps its place on rows where it's hidden, so the icons line up on every row.
- The reason column has more room, so fewer reasons get cut off.

## 1.0.0

First release.

- **Bag triage:** every item is Keep, Use, Flag, Toss or Unsorted, with the reason in the window and in item tooltips.
- **Quest data:** a quest database built from QuestieDB's Forever data covers about 4,000 quests, so Packrat knows which quests need, hand out or start each quest item.
  - It keeps items for quests in your log.
  - It flags items for gray quests, and for quests you haven't started yet.
  - It tosses an item only when every quest it belongs to is turned in.
  - It ignores quests your race or class can't take.
- **Leftovers prompt:** after you turn in or abandon a quest, a small window lists that quest's leftover items with Delete and Keep buttons.
- **AI agent round trip:** export your bags, quest log, gear, bank and professions as JSON for any AI chat or agent, then import its keep / use / flag / toss verdicts. The agent can never toss a quest item whose quests aren't done, or an item in one of your equipment sets.
- **Never-toss list:** account-wide, and nothing overrides it. Set it with the Lock button, `/packrat protect` or a key binding.
- **Selling and deleting:**
  - **Sell tossed** sells up to 12 stacks per click, so they all stay in buyback.
  - **Auto-sell** when a vendor opens is optional and off by default.
  - **Delete next** removes one stack per click; Rare and better items are never deleted this way.
  - **History** logs every sale and delete.
- **Built-in rules:**
  - gear in an equipment set is kept;
  - soulbound gear your class can never use is tossed;
  - RestedXP junk and gray items are tossed.
- **Integrations:**
  - **Baganator:** a bag button, item corner icons, the junk plugin and the upgrade arrow;
  - **Syndicator:** copies of each item in your bank and mail and on alts;
  - **Pawn:** its upgrade opinion goes into the export;
  - **Minimap button and LDB feed.**
- **Clients:** WoW Forever, including character surnames and the tabbed bank, and Classic Era.

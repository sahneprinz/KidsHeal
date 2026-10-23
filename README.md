# KidsHeal v1.2.0

Health bars with big, clickable spell icons next to every group member —
built for young healers who can't handle keybindings yet.

## What it does
- One box per group member (you + party): class-colored health bar with the name.
- Below every bar: a row of **empty spell slots**.
- **Drag a spell from your spellbook onto a slot** — every member's bar gets it.
  You can also drag **usable items** (potions, healing trinkets) from your bags onto a slot.
- **Left-click an icon → that spell is cast on that player.** No targeting, no keys.
- When a spell goes on cooldown, its icon shows the cooldown sweep **on every box at the same time**.
- Icons turn grey when unusable (out of mana / on cooldown), dim slightly when out of range.
- Each **character has its own slots and panel position**.

## v1.2.0 changes
- Renamed to **KidsHeal** (folder, TOC, slash command `/kidsheal`, saved variables `KidsHealDB`).
- Previous `KidHealsDB` settings are not migrated — reassign your slots once after updating.

## v1.1.3 changes
- **Drop detection rewritten**: the addon now polls the cursor directly (GetCursorInfo)
  and assigns the spell the moment the cursor empties while you're over a slot — this no
  longer depends on drop events, which were being swallowed by the secure button template.
- New `/kidsheal debug` command to diagnose drag-and-drop if anything still fails.

## Moving the panel
- Left-click and **hold** the handle strip on top of the panel (or any health bar), then move the mouse.
- Position is saved automatically. `/kidsheal reset` restores the top-left corner.
- Dragging/assigning is disabled in combat (Blizzard rule).

## Managing slots
- Drag a new spell/item onto a slot → overwrites it.
- `/kidsheal clear <n>` → empties slot n (e.g. `/kidsheal clear 2`).

## Install
Unzip so you get `Interface/AddOns/KidsHeal/` containing `KidsHeal.toc` and `KidsHeal.lua`.
Enable "Load out of date AddOns" and make sure KidsHeal is checked.

## Commands
- `/kidsheal reset` — reset panel position
- `/kidsheal clear <slot>` — empty a spell slot
- `/kidsheal test` — fill bars with random values to check the layout
- `/kidsheal refresh` — rebuild the frames
- `/kidsheal debug` — toggle debug output for the drag-and-drop detection

## Notes
- Works with any client language (spells/items stored by ID).
- Trinket caveat: items are used on the member via `/use [@unit] <item>`. Items that
  only ever work on yourself will still just work on yourself — that's a game rule, not an addon bug.

# KidsHeal v1.3.16

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

## v1.3.1 changes
- Options panel creation wrapped in pcall so a client API difference can no longer
  kill the whole addon at load time (this was the likely cause of "no bars, no slash command").

## v1.3.0 changes
- **Drag-and-drop fixed.** The old invisible catcher frame sat above the slots and
  swallowed the drop before the addon ever saw it — it's gone. Drops are now caught
  directly on the slot button (`OnReceiveDrag`) **and** by fast cursor polling (20x/sec)
  that assigns the moment the cursor empties over a slot. Dragging spells off your
  **action bars** now works too.
- **Options panel** (Interface Options → AddOns → KidsHeal, or `/kidsheal options`):
  - Bar width and height
  - Icon size
  - **Icons right of the bars** (toggle) — icons sit next to each bar instead of below it
  - Health text on/off
- Fixed cooldown/mana/range display for pet spells (they have no spell ID).

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
- `/kidsheal set <slot> <Zauber>` → set a slot by spell name, e.g. `/kidsheal set 2 [Flash of Light]` (brackets optional).
- Options panel → pick a slot and choose a spell from your whole spellbook via dropdown (also has "Slot leeren").
- `/kidsheal clear <n>` → empties slot n (e.g. `/kidsheal clear 2`).
- Sizes and icon placement: Interface Options → AddOns → KidsHeal.

## Install
Unzip so you get `Interface/AddOns/KidsHeal/` containing `KidsHeal.toc` and `KidsHeal.lua`.
Enable "Load out of date AddOns" and make sure KidsHeal is checked (the TOC targets Interface 70300 (Legion 7.3.5)).

## Commands
- `/kidsheal reset` — reset panel position
- `/kidsheal clear <slot>` — empty a spell slot
- `/kidsheal set <slot> <spell>` — set a slot by spell name (e.g. `/kidsheal set 2 [Flash of Light]`)
- `/kidsheal test` — fill bars with random values to check the layout
- `/kidsheal refresh` — rebuild the frames
- `/kidsheal debug` — toggle debug output for the drag-and-drop detection
- `/kidsheal options` — open the options panel

## Notes
- Works with any client language (spells/items stored by ID).
- Trinket caveat: items are used on the member via `/use [@unit] <item>`. Items that
  only ever work on yourself will still just work on yourself — that's a game rule, not an addon bug.

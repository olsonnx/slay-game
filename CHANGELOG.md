# Changelog

## 0.3.0 — Castles and Ore

- Cities are now visually distinct Castles, with three recruitment tiers.
- Added uncapped, shared faction Ore: each controlled source produces 1 Ore per
  3 development. Deposits are approximately 25% more common than mana sources.
- Neutral mana sources receive a modest land-area bonus, capped at six extras;
  Ore abundance follows the increased mana source count.
- Knights require 2 Ore in addition to gold, including paid Soldier upgrades.
- Castles, Towers and Capitals upgrade for 2 / 4 Ore. Tier-two defenses require
  Knights; tier-three Towers absorb the first valid attack each owner turn.
- Capital tier two expands recruitment; tier three halves development costs on
  its own and adjacent friendly tiles. Bridges retain their existing rules.
- Houses appear from development 3: levels 3–6 show one through four houses,
  distributed randomly across three corners with up to two per corner and stable
  rotation / position variation. Occupied buildings shrink beside full-size units.
- Integrated Ore and tiers into AI, map files, undo, replay and multiplayer state.
- Updated teaching scenarios for Ore income and Castle upgrades.

## 0.2.0P — Closed playtest preparation

- Bridges can only be removed with Shatter; removed dismantling from province details, network commands and tutorial authoring.
- Hide empty notification banners when a tutorial topic completes.
- Added slowly drifting distant clouds with a soft, irregular offshore clearing,
  bounded rendering cost, reduced-motion support and a Video settings toggle.
- New matches pan and zoom toward the player's country as the island arrives.
  The opening takes 0.85 seconds and locks camera input until it finishes;
  reduced motion frames it immediately.
- Added the P playtest marker to the game version while preserving numeric
  Windows version metadata. Version tooling accepts both marked and release labels.
- Reconciled regression fixtures with recruitment hubs, cities, infrastructure
  upkeep and limited movement. Historical replay positions remain unchanged.
- AI retaliation analysis accounts for enemy barriers expiring at settlement,
  including armies separated by those barriers in stored positions.

## 0.2.0 — Cities and logistics experiment

- All map sizes now use the same strategic enemy AI. Difficulty adjusts tactical
  budgets and risk handling; map size no longer switches the decision algorithm.
- Reused safe purchase analysis, accelerated pathfinding and shared strategic
  calculations. AI can prepare its next moves privately during animation playback.

- Removed the decorative rank dots below units, including movement and upgrade
  rendering. The finished-map results control is now an icon beside music.

- Reorganized Options into Audio, Video, Game, Controls and Interface, with
  scrolling pages and category defaults. Added UI scaling, reduced motion,
  tooltip timing, FPS limits, depth blur/contact shadow controls, brightness,
  camera sensitivity, playback speed, focus behavior and audio output selection.
- Removed development art-style comparison switches from the player menu.

- Fixed widescreen display scaling and enabled resolution selection in fullscreen.
  Fullscreen changes scene rendering quality while keeping the interface sharp.
- Added an eight-track music playlist with a top-right player, pause/resume,
  next-track controls and a separate music volume slider.

- Updated all tutorial chapters for the current rules and added Cities and supply
  lines, with forward recruitment, city names, road previews, a road-assisted march
  and connecting to existing roads. The editor includes all eight chapter templates.

- Polished guided lessons against actual controls and outcomes: separate treasury
  exercises, all three spells, both encounter rewards, exact road and upkeep costs,
  and reading acknowledgements before advancing.

- Recruitment and Summon show an area boundary around their legal deployment tiles.
- Forest spread and aging graves can only create trees on empty ground.

- Restored equal-tier field merging within movement range.
- AI prioritizes useful forward cities and saves toward them; roads need a
  recruitment route toward the front and a measurable movement benefit.
- Cities and capitals can be renamed by editing the province-details title; names persist in
  replays, level documents and multiplayer state.

- Cities replace houses as recruitment hubs; captured cities survive.
- New town and grand capital models; ready recruits deploy on or beside cities and capitals.
- Scout/Soldier/Knight movement ranges are 5/4/3; roads halve friendly steps.
- Road previews show the actual paved surface and junctions; startup warms the
  shared road material and geometry. Structures can connect to existing road tiles.
- Roads use the clean original appearance, start from a province-details icon,
  and cost 1 G per newly paved tile with route and price previews.
- Towers cost more as their number grows; towers and bridges cost 2 G per turn.
- Roads and towers cannot be dismantled; empty sponsored bridges can still be removed.
- Bridge sponsorship, economy forecasts, multiplayer,
  AI planning and tutorials follow the experimental rules.

## Earlier uncommitted improvements

- Four new event structures: Builders' Guild (local development cost -50%),
  Soldiers' Barracks (Soldier wages -50%), Scout Lodge (Scout wages -50%), and
  Watchtower (+1 province defense and adjacent friendly unit defense).
- Stainless steel now reduces Knight wages by 25%; structure benefits transfer
  on capture and do not stack. Event Editor templates expose all new properties.
- Generation v14 records the expanded encounter pool with refreshed seed fixtures.

- Status-effect icons share the bottom-left dock's background and outline.

- Departing tiles now leave the screen intact, with temporary camera depth
  headroom and a screen-down exit at overhead angles instead of clipping away.

- Trimmed empty space below Quit and confirmation menus to match Pause padding.

- Main menu profile card matches the menu panel and shows current level and XP.

- Loading screens with a miniature hex island assembled by real progress,
  a plain background, and a gentle fade into the ready destination.

- Compact replay filenames with abbreviated mode, map size, difficulty and result,
  kingdoms, UTC date, game version and seed; numbered duplicates.

## 0.1.0 — 2026-10-24

First versioned development baseline, covering the work accumulated so far:

- Local and Steam multiplayer, replays, tutorials, and level and event editors.
- Player profiles, progression, and the painting collection.
- Gameplay, world generation, AI, and interface improvements.
- Prepared province value mode, shared rendering batches, and graphics warmup.
- Smooth tree and mountain materials and covered match exit transitions.

Versions use **MAJOR.MINOR.PATCH**. During development, use a minor bump for
features and a patch bump for fixes; reserve 1.0.0 for the first stable release.
An optional uppercase **P** suffix marks a playtest (for example, `0.2.0P`).
The suffix does not enter the four-component numeric Windows version.
The game version is independent of replay, save, map-generation and network
format versions.

`project.godot` contains the game version. Run `python tools/version.py 0.1.1`
to change it and synchronize the Windows file/product versions. Run
`python tools/version.py --check` before exporting. The menu and newly recorded
replays read the project setting directly.

For each release, move the relevant Unreleased notes into a dated version
section, commit them with the version change, and tag that commit `vX.Y.Z`.

# World generation v13 — 21 October 2026

The current playable sizes are Tiny (~80 tiles), Small (~150), Standard (~250),
Large (~500) and Huge (~1,000). Very Small is retired from new-map selectors.
Generation IDs and budgets are unchanged for saved maps and replays; historical
size names below refer to the old lineup. Chests begin at the current Small size.

Version 12 makes lairs rare objectives: Tiny/Small allow one, Standard two, Large
three and Huge four, subject to safe placement. Lairs stay eight steps apart.

Version 11 adds distant neutral animal lairs after events and treasure placement,
using a separate seeded RNG. Lairs stay four steps from starting territory and
five steps apart. See [wildlife](wildlife.md) for density, behavior and rewards.

Version 10 adds one starting development point per Modern kingdom: total value
and gross income rise from 10 to 11. With Scout upkeep now 4 G, opening net income
stays +7 G. Shapes, area and neutral values retain their existing policies.
Version 9 restricted treasure chests to Medium and larger maps.

Version 8 adds visible treasure chests after event placement. Chests guarantee 15 G
to the collecting unit's supporting treasury, with no choice or danger. They favor
remote neutral land away from direct routes between capitals, including peninsulas
and offshore pockets. Placement uses at least four hexes of capital clearance, six
hexes between chests, and excludes events and their adjacent tiles, mountains,
bridges, trees and mana sources. The target is roughly one chest per 100 neutral
land tiles, stopping when suitable sites run out; Small maps may have none.
Existing land geometry, starting shapes, lakes and ridges are unchanged from v7.

Modern worlds randomly choose one, two or three substantial landmasses. A single
landmass remains possible at every size. Small maps can have two, and Medium
through Huge can have three; Very Small can split when the kingdom count leaves
enough expansion space. Offshore regions use roughly 36–49% of the nominal land
budget for two-landmass maps, or 27–33% each for three. There is no dominant
mainland requirement. Crowded profiles may keep connected land instead.

Kingdoms can start offshore. Starting territories use compact, crescent and
elongated footprints, rotated and reflected to fit actual land. Modern kingdoms
have six to nine provinces, including mixed sizes within a match. All total eleven
province value, eleven gross income and seven net after their Scout's upkeep. They
retain ten gold, one Scout, one mana and capital capacity two.

Footprints are connected, stay within radius two of the capital and have no
single-tile necks or tendrils. The capital has at least three friendly neighbors.
Actual opposing borders, including extended wings, stay at least three hex steps
apart, leaving two intervening hexes. Reserved home rings guarantee a fallback
when a requested larger footprint cannot fit. A neutral land budget prevents
crowded profiles from consuming all expansion space. Placement order is shuffled
so colours are not consistently disadvantaged by constraints.

Two adjacent neutral expansion tiles per kingdom are protected from mountains.
If a coastal home fills its peninsula, a neutral coastal tile can be added within
the safety envelope, without merging separate landmasses or increasing starting
ownership. The camera/editor rules continue to use actual terrain extents.

Every landmass remains connected and has a protected one-water-hex crossing into
the landmass network. These can be reached with normal bridges at their existing
price; no new travel mechanic is introduced. Islands have at least 13 tiles.
The graph-based
`starting_land_reachable` check includes legal short water crossings; existing
literal land-connectivity queries keep their original meaning.

Lake carving is optional: about 30% of eligible seeds skip it, and placement can
also decline a lake if no safe interior fits. Very Small maps skip explicit lakes.
Accepted lakes have at least five water hexes; larger maps can contain much bigger
lakes instead of collections of tiny ponds. Growth follows an irregular compact
frontier, and each lake commits in full or rolls back. At most three are carved.
A complete land rim, home buffer, protected bridge ports and connectivity checks
keep them enclosed and playable. Water reservations preserve minimum land counts.

Modern mountains now grow as thin, winding ridges, rather than compact blobs.
Each new peak extends an end in its current direction or bends gently; it cannot
touch another ridge or create a dense junction. Growth tries both ends before
settling for a shorter range. Length scales with map size, up to eighteen peaks.
Some ridges of seven or more tiles get an inland pass, with at least two peaks
remaining on either side. Pass tiles stay protected during later placements.
Every peak placement preserves passable connections, homes, mana sources and
bridge ports. A wall that would close the only route cannot be completed.

The coverage budget is 5–8.5% of land before placement constraints, between the
previous dense and sparse versions. The number of ridges scales with map width,
leaving larger open areas between them. The original v5 16-seed sample averaged 6.53% on Large and 6.56% on Huge. Ridges are intended to provide detours,
passes and sheltered approaches alongside the larger lakes, without trapping
territory or requiring a particular expansion route.

Lake and landmass generation retain v4's geometry: the largest sampled lakes
remain 19 tiles on Large and 52 on Huge, and five Large and seven Huge sample
worlds have no lake of five or more tiles.

Modern event counts scale with actual eligible neutral land, rather than stopping
at the kingdom count plus one. The target is the larger of that existing minimum
and one event per sixteen neutral, non-mountain tiles without a mana source.
Three-hex spacing is preserved, and generation stops safely if the target cannot
fit. A caller's size label does not override the actual available area. Across sixteen seeded maps per size with low
and high kingdom counts, event averages were 3.8, 5.1, 6.5, 10.9, 27.5 and 57.0
from Very Small through Huge.

Version 7 changes starting ownership, initial value distribution and subsequent
seeded terrain/resource/event draws. Old replays reconstruct stored positions;
new replays record generation version seven and restarts remain deterministic.

Rotated home layouts, irregular solid lobes, coastal erosion and a generous circular
safety envelope continue to support tall and wide worlds. Offshore shapes use
correlated directional variation. Island candidates grow without clipping against
the envelope, then are accepted only with boundary clearance. Cameras fit actual
land and props. Upgrade badges maintain screen clearance at the wider fitted zoom.
The editor retains its expanded bounds and shared 4,000-cell painting/loading cap.
The menu continues to use the same generator and shared terrain rendering.

This intentionally changes the world associated with an older seed. Restarts are
deterministic within v13, new replay metadata records generation version 13, and old
replays reconstruct their stored positions. The 300 golden samples cover all five
sizes, and default, two-kingdom and maximum-kingdom requests:

```powershell
godot --headless --path . --script tools/create_generation_golden.gd -- --update-generation-v13
```

The generation suite checks optional islands, balanced multi-landmass layouts,
island kingdoms, component sizes, land budgets, mountain passability, enclosed
lakes, bridge reachability, authoritative bridge construction and Scout movement,
boundary clearance, orientation variety, determinism and camera fit. Existing
map-size suites also check all supported faction counts and exact starting resources.

`tools/map_generation_preview.gd -- --size=small` (or `large`, `huge`) renders six
seeded maps to `artifacts/map_generation_<size>.png`. `tools/preview.gd -- --modern
--size=huge` captures actual gameplay. Native overview and gameplay renders are
inspected in addition to automated checks. Ridge fixtures check thin non-branching
paths, two open ends per segment, actual inland passes, protected objectives and
connected habitable terrain. The broad generation sweep also checks coverage,
landmass reachability, fairness, larger lakes, open-map variety and determinism.
The map-size suite checks every supported faction count, actual border spacing,
connected footprints, absence of fragile necks, capital depth, expansion options,
unchanged gross/net income, sizes six through nine, mixed-size matches, shape
variety in both modes and repeatability. The map-size and explicit-count sweep produced
366 starts of size six, 421 of seven, 417 of eight and 360 of nine; 347 matches had
mixed sizes. These are generation checks, not evidence of equal strategic strength.

`tools/starting_kingdom_preview.gd` renders nine distinct generated footprints
with per-tile income at `artifacts/starting_kingdoms_v7.png`. Actual Small gameplay
was also captured at `artifacts/starting_kingdoms_v7_gameplay.png`; both were
visually inspected. All 46 Godot suites and 14 Python tests passed, including
762,075 map-size/starting-shape checks, 70,031 generation checks and all 360 v7
golden samples. Isolated exported Small, Large and Huge games passed income,
starting size, mana and route checks with the new helper loaded from the package.
Localization verified 726 messages. Logs are recorded in `docs/HANDOFF.md`.

Version 8 verification: all 360 refreshed seeded baselines passed. The new
points-of-interest suite passed 1,437 checks for escalating per-color capital
relocation, treasury and bridge-home preservation, ward transfer, replay history,
legal UI actions, safe one-time chest collection, deterministic remote placement,
AI reward valuation and chest picking. Native 1280/960 province previews and the
chest close-up were inspected (`artifacts/capital_relocation_1280.png`,
`artifacts/capital_relocation_960.png`, `artifacts/treasure_chest.png`). The local
`world-generation-v8.pck` passed isolated Small/Large/Huge relocation and treasure
smoke tests. The localization catalogue now contains 730 English messages.

All 47 Godot suites and 14 Python replay tests passed for v8. Final suite results
are in `artifacts/poi-verification-summary.json`; the first 16 passed in
`poi-full-tests.log` and the remaining 31 in `poi-full-tests-remaining.log` after
correcting the old single-landmass menu test to allow offshore islands.

Version 9 limits generated chests to Medium and larger maps. Six-map samples per
size yielded 0 Very Small, 0 Small, 6 Medium, 12 Large, 25 Very Large and 54 Huge
chests. All 360 v9 baselines and six focused UI/rules/replay suites passed. The
capital action now uses an icon and a confirmation with Cancel focused by default;
native previews include `artifacts/capital_confirmation_1280.png` and
`artifacts/capital_confirmation_960.png`. The POI suite passed 1,579 checks and
the localization catalogue verifies 734 English messages.

Generation v13 changes event selection to weighted draws without replacement until all enabled event types have been used. Remaining markers allow weighted repeats. Terrain generation is unchanged.

Generator golden fixtures pin the built-in event weights so editing the event pack does not invalidate terrain and RNG determinism checks. The fixture creation tool uses the same weights; event distribution and authored-event tests cover the editable pack separately.

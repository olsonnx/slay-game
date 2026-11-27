# 0.3.0: Castles and Ore

Ore is stored per faction, shared between its kingdoms, with no capacity cap.
A controlled Ore deposit yields `floor(tile development / 3)` at the beginning
of its owner's turn. Trees and graves do not block Ore production. Capture
transfers future production; it never transfers or removes stored Ore.

Generated maps retain their starting Capital mana sources and original neutral
source budget, plus `min(6, 1 + floor(passable neutral land / 150))` extra neutral
mana sources. Extras preserve three-hex spacing and avoid encounters, treasure,
lairs and mountains; crowded maps may receive fewer. Generated maps contain
`ceil(mana sources × 1.25)` Ore deposits, so Ore follows the same modest increase. A separate seeded
placement stream keeps existing mana, events and wildlife generation stable.
Deposits avoid mountains, bridges, lairs, events, treasure and mana deposits.
Old authored maps default to no deposits and tier-one structures. The map and
tutorial editors can paint Ore sources; new fields survive save/load.

Castles retain the former City's 25 G construction price, zero upkeep, no bonus
income and survival on capture. The internal `city` identifier stays compatible
with existing maps, tutorials and replay files.

| Structure | Tier 1 | Tier 2 | Tier 3 |
| --- | --- | --- | --- |
| Castle | Recruit on its tile | Recruit within 1 hex | Recruit within 2 hexes |
| Tower | Soldier can destroy it | Knight required | Knight required; first valid attack is absorbed |
| Capital | Soldier required; recruit within 1 hex | Knight required; recruit within 2 hexes | Same, plus −50% development cost here and on adjacent friendly tiles |

Tier two costs 2 Ore and tier three costs a further 4 Ore. Select a friendly
structure and use its Upgrade button in province details. Towers refresh their
one-hit protection at the beginning of their owner's turn; the attacker spends
its action, just as with unit entrenchment. A ward does not make an otherwise
invalid attack legal. Castle tiers survive capture. Capital tiers move with
relocation; replacement Capitals start at tier one. Overlapping Capital discounts
do not stack. The Capital discount multiplies an existing event discount, then
rounds the final gold cost up.

Knights cost 2 Ore once on recruitment or a paid unit upgrade, in addition to
the existing gold price. Ore adds no recurring Knight upkeep. Unit merging and
encounter rewards keep their existing rules. Bridges have no Ore upgrades.

Development 1–2 shows no houses. Levels 3, 4, 5 and 6 show one, two, three and
four houses respectively on owned, passable land. Six possible sites are shuffled
per province across the upper-left, upper-right and bottom corners, with room for
two houses in each corner. Corners do not correspond to particular values: four
houses can occupy two paired corners, and two houses can share a corner or be
split. Distribution, displacement and rotation remain stable across redraws;
increasing development adds a house without moving existing houses. Placement
fits the whole rotated roof footprint inside the hex, with a small inset from its
edge. Neutral provinces have no houses. Exact values remain in province details
and the heatmap.
Vacant buildings are centered; occupied buildings shrink by 20% and shift slightly
to make room for a full-size unit. Mana uses the top and Ore the lower left.

## Balance switches

Edit `src/game/game_catalog.gd`:

| Constant | Initial value |
| --- | --- |
| `ORE_DEVELOPMENT_PER_INCOME` | `3` |
| `ORE_SOURCE_MULTIPLIER` | `1.25` |
| `EXTRA_MANA_SOURCE_BASE` | `1` |
| `NEUTRAL_LAND_PER_EXTRA_MANA_SOURCE` | `150` |
| `MAX_EXTRA_MANA_SOURCES` | `6` |
| `KNIGHT_ORE_COST` | `2` |
| `BUILDING_UPGRADE_ORE` | `[0, 0, 2, 4]` (indexed by destination tier) |
| `CAPITAL_DEVELOPMENT_DISCOUNT` | `0.5` |

Run `tools/run_tests.ps1 -Godot <Godot_console.exe>` for the full regression suite.
The dedicated `tests/test_castles_ore.gd` covers economy, range, defense, wards,
relocation, snapshots, replay tracking, map compatibility and placement.
`tools/castles_ore_preview.gd` renders the current map and interface for inspection.

## Validation — 2 November 2026

All **105 Godot suites** pass on Godot **4.6.3**, totaling **991,414 checks**.
All **17 Python tests**, version consistency, localization catalogue and whitespace
checks pass. The full audit was followed by targeted reruns of repaired fixtures;
the initial logs and final log mapping are retained under `artifacts/030-*`, with
`artifacts/030-final-results.json` identifying each final successful result.

The 2 November baseline recorded generation version 15. The 3 November resource
abundance update advances the 180 deterministic fixtures to generation version 16.
Rendered previews cover the map, tier-three Capital inspector, Castle build card
and tier-three Tower inspector at 1280×720 and 960×620. Multiplayer coverage uses
the simulated transport regression suite.

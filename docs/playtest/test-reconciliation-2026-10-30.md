# Playtest test reconciliation — 30 October 2026

The game label is **0.2.0P**. The uppercase P marks a playtest and is retained
by the menu, replay headers/filenames and future package names. Windows file
and product metadata remain **0.2.0.0**, since those fields require numbers.
`tools/version.py` accepts both marked and ordinary release versions.

Feedback remains in Discord. No feedback button, export or ZIP was added.

## Reconciled expectations

| Coverage | Current behavior preserved by the replacement checks |
| --- | --- |
| Recruitment and upgrades | Purchases happen on or beside a capital/city; clearing rewards, prices and spent actions remain checked. |
| Cities and income | Cities cost 25 G, survive capture and supply recruitment. Province development raises income; retired houses cannot be constructed. |
| Turn feedback | Tower destruction removes upkeep at visible impact; subsequent province capture removes land income. Preplanned losses stay hidden until playback. |
| Bridges | Sponsored segments cost 2 G/turn. Destroying one segment leaves the bill for surviving segments. Knights cross longer spans over multiple legal moves. |
| Entrenchment | The approach fixture uses a three-step Knight attack, preserving occupied, structure, bridge, capital, tree, replay, cancellation and actor-retention cases. |
| Capital breach | A follower uses the captured corridor within its movement budget; an opposite-side unit cannot shortcut through the unbreached ring. |
| Paid roads | Connections require purchases and retain their recorded route edges. Adjacent paving creates no unpurchased branches; captures, missing land, mountains and legacy tile-only roads remain covered. |
| Historical AI positions | Old recordings remain unchanged. Positions without a forward recruitment hub now require a useful city before more rear troops. Synthetic combat-reserve tests provide a legal forward hub. The unified AI is checked for safe capture and useful expansion rather than an obsolete beam-search ordering. |
| Wildlife | Both diagnostic and production planners hunt all three lairs in a fixture with a continuing neutral frontier. |
| Menu and migration | Menu props use cities; FPS tests set their starting visibility explicitly. Older authored houses migrate to cities while preserving the serialized layout. |
| Local multiplayer | All ten human seats receive turns on a Large map, rather than expecting six seats on Tiny, whose cap is four. |
| Kingdom palettes | All twelve palettes remain selectable with unique opponents at two, six and ten seats, using maps that support those counts. |
| Standalone camera test | Navigation loads after autoload registration, so its Gameplay dependency is available in the custom SceneTree test harness. |

No test suite is disabled or marked skipped. The independent threat reference
now measures weighted movement ranges and settlement expiry instead of unlimited
friendly-territory reach. Its simple linear frontier remains separate from the
production bucket queue.

## Actual AI correction

A historical barrier position exposed a real retaliation error. Enemy barriers
expire at that enemy's settlement, but prediction used the current blocked route
and could omit an army split into a separate region. Read-only threat routes now
account for the attacker's own expiring barriers. The strategic planner uses that
prediction when legacy barriers invalidate its local-region shortcut.

Regression checks require the route to remain blocked for current commands,
predict the future Soldier counterattack, avoid sending the Scout into it,
preserve the original board, and retain barriers owned by another faction.
The solvent Scout fixture avoids confusing this with deliberately shedding
unsupported upkeep. Ordinary movement still uses the current board and range.

## Validation

All **101 Godot suites** pass on Godot **4.6.3**, with **967,395 checks** across
their final successful results. The full headless audit was followed by targeted
reruns of repaired suites; no previously passing suite was removed from the run.
All **17 Python tests** pass, including playtest/release version round-trips.
Version consistency, localization catalogue and whitespace checks also pass.

Logs are under `artifacts/reconcile-*.log`. The initial audit history is retained
in `artifacts/reconcile-full-results.json`; `artifacts/reconcile-final-summary.json`
records the final successful log for every suite. Reproduce the regular full run
with `tools/run_tests.ps1 -Godot <Godot_console.exe>`; it checks version metadata,
runs every Godot suite and discovers all Python test modules.

These automated checks do not replace the fresh-extraction gameplay checklist,
another-PC launch or a real two-account Steam session in the organizer guide.

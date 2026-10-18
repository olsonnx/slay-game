# Performance and structure review — 11 October 2026

This pass preserves rules, seeded maps, resource prices, event outcomes, movement rollback, presentation and pause behaviour. It targets repeated CPU work and unnecessary scene allocations rather than changing gameplay or replacing the renderer.

## Measured results

Godot 4.6.3, headless, Modern, Large, seed 42, 227 tiles. Each CPU measurement is the median of five warmed samples, normalized per operation. Route/spell workloads use expanded connected territory; HUD/picking use the starting board. The before/after probes ran sequentially on the same host. These are workload measurements, **not FPS or GPU benchmarks**; timing depends on hardware and system load.

| Workload | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| All six spell target queries | 44.057 ms | 9.585 ms | 78.2% |
| Reachable unit targets | 2.870 ms | 1.089 ms | 62.0% |
| HUD refresh | 2.595 ms | 0.745 ms | 71.3% |
| HUD mana values | 0.354 ms | 0.066 ms | 81.4% |
| Repeated stationary picking | 0.227 ms | 0.0049 ms | 97.8% |
| Mesh instances for seven question marks | 252 | 7 | 97.2% |

The mana and spell rows compare the old repeated scalar calls with the new equivalent batched queries used by the HUD. Regression tests compare their results directly. Stationary picking measures reuse after an initial live query; moving the pointer or camera still requires a live pick, and moving actors never use that cache.

Run `Godot_console --headless --path . --script tools/performance_probe.gd -- --label=current` to repeat. Raw captured results are `artifacts/performance_before.json` and `artifacts/performance_after.json`. The probe also verifies stable icon identity and reports marker mesh counts.

## Changes and responsibilities

| Finding | Change |
| --- | --- |
| Mana storage/regeneration/forecast each scanned the same board repeatedly during HUD refresh. | `mana_summary` computes all four values in one pass; turn regeneration uses it too. `clamp_mana` now aggregates all factions' capacities in one board pass. Results are local to the query, so direct cell edits and rollback cannot leave stale economy caches. |
| Spell highlighting repeated faction mana scans for each candidate hex. | `spell_targets` reads available mana once, then applies the same authoritative target validation. Unaffordable spells return immediately. Scalar `can_cast` and casting still validate live state. |
| Friendly flood fills allocated a neighbour array at every visited tile and revisited already discovered cells. Border targets could compute the same defence several times. | Route expansion iterates the six directions directly, skips discovered cells first, and reads mode/cell data locally. Target queries examine each border destination once. Direction order and shortest routes are preserved. |
| Status refresh destroyed/recreated buttons and their style resources, also interrupting hover tooltips. | `src/ui/status_effects.gd` updates retained buttons, removes only expired effects and adds only new ones. Barrier/Fortify counts share one board scan. |
| Every question mark used 36 separate mesh instances. | `board_assets.gd` builds one cached two-material relief mesh. Every event tile shares that mesh while retaining its transform, lighting and shadows. Capture cleanup still removes the relief from `Features`. |
| Idle hover performed the complete object/sprite picker every frame. | `board_view.gd` caches the last result keyed by pointer, water mode, camera transform/projection and viewport. Visible-board notifications invalidate it. Animation and level transitions bypass it; returned dictionaries are copies. |
| Player movement rebuilt a visible economy snapshot even when no province inspector was open. | That snapshot is now requested only when it has a consumer. Opponent economy feedback retains its existing visible-state reconstruction. |
| Recruitment highlighting had a second version of purchase validation. | `recruitment_cost` and `can_recruit` share validation with the actual command. The controller retains its selected-kingdom restriction. |
| Session/controller and rules files mixed several unrelated responsibilities. | `player_actions.gd` executes player commands and their cancellable playback; `kingdom_magic.gd` owns spell/effect/event logic; `event_dialog.gd` owns popup layout and animation; `status_effects.gd` owns effect controls; `ui_theme.gd` owns shared visual primitives. Controllers and rules retain existing entry points. |
| Broken legacy root scene referred to missing `res://game.gd`. | Removed the unused root `main.tscn`. The application entry remains `scenes/app.tscn`; internal gameplay remains `scenes/main.tscn`. Temporary refactor scripts were removed after use. Original assets, script UIDs and engine-managed imports were preserved. |

The magic and player-action helpers receive state per call and do not retain a RefCounted model reference, avoiding ownership cycles. Shared UI primitives are independent of screens/controllers, preventing circular script dependencies. Existing dictionary state and snapshot formats remain compatible with fixtures and rollback.

## Verification

All **15 suites pass**, including **164 optimization regression checks** and **160 events/spells checks**. Optimization tests cover scalar/batched mana and spell equivalence in both rulesets and every size, direct terrain/source edits, retained status controls, shared marker geometry, pick invalidation on camera/board changes, cache result isolation, and live moving-actor picking. Existing suites cover turns, combat, kingdom splits, bridges, mana clamping, event rollback, pause/restart, audio, transitions and menus.

Literal source resource references were checked: **zero missing references**. Native minimum-window previews of the spell/status UI and one-/two-choice event popups were rendered and inspected after refactoring.

## Remaining profiling targets

Uncached object/sprite picking remains linear when the pointer moves. Static grass/buildings still use individual mesh instances. Opponent playback reconstructs a visible economy model to preserve impact-synchronized finances. Those are possible next profiling targets; this pass does not introduce a spatial index, MultiMesh migration, or state-version system without measured need and suitable lifecycle tests. There is still no save system, export preset or Git repository.

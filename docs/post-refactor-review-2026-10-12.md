# Post-refactor code review — 12 October 2026

This pass separates movement, opponent turn orchestration and command-preview rendering from the largest scripts. It reduces repeated AI queries and overlay allocations, fixes shared-material mutation, and preserves the current rules, map generation, AI difficulty/scoring, sounds, settings and game/menu visual parity. All 18 regression suites passed on the final implementation.

## Findings addressed

| Priority | Finding | Refactor and verification |
| --- | --- | --- |
| P2 | AI threats traversed each unit's whole friendly region even after caching its route graph. Candidate preparation repeatedly recomputed the same kingdom frontier and income/upkeep. Search evaluation and candidate generation repeated queries for the same immutable parent position. | `ai_queries.gd` memoizes region boundaries, source-rooted targets, frontiers, defence, support and bank summaries. Contexts are private to an immutable search node or a single candidate pass. Threat sources retain their order; different factions have separate region keys. Tests compare against independent per-unit routes, including hostile bridge garrisons, barriers and direct state edits between analyses. Fixed benchmark decisions/scores/counts are identical before and after. |
| P2 | HUD refresh removed and recreated all selection/path/intent overlays even when nothing visible changed. | `board_overlays.gd` retains the current overlay group using copied input signatures and child-count checks. Visible-board notifications invalidate it. Camera-relative upgrade labels still update on reuse. Tests verify retained identity on repeated refresh and replacement after a board change. |
| P2 | Roof and outline construction changed the cull mode of shared cached materials. This could affect unrelated instances using the same material. | Cull mode is part of the material cache key. Roofs and outlines request their intended variant without modifying the returned resource. Per-instance ghost transparency continues to use duplicated materials. Regressions verify that roof creation cannot alter a cached plain material. |
| P3 | Every move-intent rebuild triangulated the same arrow polygon and allocated another mesh. | `board_assets.gd.intent_arrow_mesh` caches the immutable arrow geometry. Transforms and materials remain instance-specific. Mesh-identity regression and a native upgrade-preview inspection passed. |
| P3 | Search queues used `pop_front`, shifting remaining work items. | The bounded candidate/reply queues use head indices and release consumed entries. Expansion order and candidate budgets are unchanged. This is a small allocation/work cleanup, not the source of the entire measured search improvement. |
| P3 | Rules, board and session coordinators mixed several distinct responsibilities. | Stateless movement helpers, a board-owned overlay helper and per-call opponent orchestration now own those responsibilities. Public entry points remain available to scenes, tests, player actions and simulation tools. Full matches, rollback, playback and cancellation tests passed. |

Moving code behind a facade adds dispatch overhead if every inner loop repeatedly accesses a dynamic model. The extracted movement module therefore keeps a local cell-dictionary reference for its read-only hot loops, iterates directions without allocating neighbor arrays where useful, and calls its own movement helpers directly. This retains the same direction order and authoritative validation.

## Responsibility boundaries

| Module | Responsibility |
| --- | --- |
| `src/game/kingdom_rules.gd` | Authoritative state, topology, economy and public command facade. |
| `src/game/kingdom_movement.gd` | Defence, friendly routes, legal targets, shortest paths, movement mutation, attrition/wards and playback command records. Receives state per call; no retained model or UI dependency. |
| `src/game/game.gd` | Session state, selection, player interaction, startup, completion and public controller entry points. |
| `src/game/opponent_turns.gd` | Sequential enemy phases, preparation/movement playback, cancellation checkpoints and next-round settlement. Receives the controller per call. |
| `src/rendering/board_view.gd` | Board synchronization, camera/navigation, units, picking integration and renderer lifecycle. |
| `src/rendering/board_overlays.gd` | Selection rings, routes, intent ghosts and upgrade indicators. Its lifetime follows its owning board. |
| `src/game/ai_queries.gd` | Read-only, per-position query memoization. It is not a cache attached to mutable live rules. |
| `src/game/ai_analysis.gd`, `ai_candidates.gd`, `ai_planner.gd` | Position evaluation, candidate generation and bounded search respectively; scoring and difficulty budgets remain unchanged. |

The largest three coordinators decreased from 715 to 646 lines (`game.gd`), 691 to 516 (`kingdom_rules.gd`), and 690 to 539 (`board_view.gd`). The extracted modules are 75, 231 and 178 lines; the query context is 84. Counts exclude the final trailing newline. The goal is cohesive ownership rather than a particular line limit: authoritative state and compatibility facades remain centralized where appropriate.

Helpers do not get stored inside their RefCounted rule model. Search nodes hold their own snapshot and query context; the context points to that snapshot without a model-to-context ownership cycle. No query context survives a committed live mutation.

## Measurements

Godot 4.6.3, same local host, headless CPU workloads. AI uses a fixed Modern Large seed-42 board with 231 tiles and 30 units. Each profile has one warmup followed by five samples; values below are medians. HUD/routes use the existing probe's five warmed samples, normalized per operation. Final measurements ran sequentially without a simultaneous test workload.

| Workload | Before | After | Less CPU time |
| --- | ---: | ---: | ---: |
| Easy search | 24.955 ms | 19.260 ms | 22.8% |
| Normal search | 165.601 ms | 124.845 ms | 24.6% |
| Hard search | 652.166 ms | 521.662 ms | 20.0% |
| Median peak Hard step | 15.255 ms | 11.583 ms | 24.1% |
| Unchanged HUD refresh | 0.543 ms | 0.335 ms | 38.3% |
| Reachable-target query on expanded territory | 0.645 ms | 0.504 ms | 21.8% |

All three AI profiles kept identical selected sequences, scores and evaluated-candidate counts (5 / 35 / 130). The asynchronous Hard probe still yielded while searching. These measurements are not FPS/GPU results, whole faction-turn durations or guarantees for other hardware/maps. The sample contains Scouts and Soldiers; it is not a comprehensive late-game Knight stress test.

Control workloads were broadly unchanged: stationary cached picking was 2.620 versus 2.625 microseconds; seven event markers still use seven mesh instances. All spell-target queries were 7.359 versus 7.526 ms, so this pass does not claim a spell-query improvement. Timing variation and system load still matter.

Raw evidence:

- `artifacts/ai_performance_review_before.json` and `ai_performance_review_final.json`.
- `artifacts/performance_review_before.json` and `performance_review_final.json`.
- Intermediate `review_after` / `review_after_serial` reports are diagnostic only; some were captured alongside another CPU workload and are not used in the table.

Reproduce with `tools/ai_performance_probe.gd -- --label=review_current --samples=5` and `tools/performance_probe.gd -- --label=review_current`, running each engine process separately. A pre-refactor source snapshot is preserved under ignored `artifacts/review_before_src/` because this workspace has no Git history.

## Verification

The final complete `tools/run_tests.ps1` run passed all 18 suites. Highlights: 178 AI checks, 284 optimization checks, 114,641 general game checks, 10,520 Modern checks, 5,080 presentation checks, 28,568 map-size checks, 2,498 terrain/resource checks, 4,324 menu-background checks and 5 startup checks. Some counts depend on generated menu/scene fixtures and can vary between runs.

Coverage includes both rulesets, all sizes, seeded state/RNG reproduction, full automated matches, capital capture/annexation, Knight attrition and wards, bridges and treasury merging, player rollback, event outcomes, source-rooted paths, AI snapshot isolation, sequential/concurrent animation, impact-synchronized economy, preference persistence, pause/restart/disposal and shared menu/game border geometry. The additional optimization tests verify overlay identity/invalidation, material isolation, arrow reuse, scalar/memoized query equivalence and fresh analyses after direct state edits.

Native preview inspected: `artifacts/preview_water_modern_intent_upgrade.png`. It checks the upgrade ghost/label, terrain, units and HUD after the overlay/material extraction. Literal source resource checks found zero missing references, and the headless editor scan completed cleanly. Existing assets, sounds, reference art, scenes and original script UID files were preserved; Godot registered new UIDs for the extracted scripts.

## Future watchpoints

| Area | What to watch and when to act |
| --- | --- |
| Hard AI cost | A search still takes about half a second of CPU in this fixture. The 4 ms yield target is not a hard upper bound on one step; measured peak steps exceed it. Before increasing depth/width or unit counts, profile representative late-game armies and initialization/candidate-generation spikes. Incremental candidate generation, smaller snapshots or a worker may help, but workers must use isolated data and commit validated actions on the main thread. |
| Query-context lifetime | The cache assumes its model is unchanged. Reusing it after capture, spending, event resolution, a barrier edit or direct fixture mutation produces stale results. Keep contexts scoped to immutable snapshots or a single synchronous read pass. A future long-lived cache requires explicit state revisions or immutable typed records. |
| Route/command duplication | AI dependency checks query a path before the public recorded move validates it again. Avoid bypassing public validation with a stale precomputed path. A revision-bound validated command object could remove duplicate work safely when state ownership is formalized. |
| Generation fallback | The subsequent independent-count update replaced the exhaustive recursive fallback with tested feasible fallback sites after 128 random retries. New faction/bounds profiles still require feasibility and separation tests, including full seven-tile homes. The minimum-land growth loop assumes available frontier space. |
| Generation connectivity | Coast cuts and mountain trials repeatedly flood-fill the mainland. Worker generation keeps the UI responsive, but larger maps may expose quadratic CPU growth. Profile first; preserve seeded RNG order and the current map constraints when optimizing. |
| Visible economy | Playback reconstructs an economy model from the visible board to synchronize money with impacts. This remains correctness-sensitive allocation work. Cache only with visible-board and treasury-baseline revisions; test captures, bankruptcy, split capitals and rollback before changing it. |
| Picking and draw calls | Moving-pointer object picking remains linear. Trees, grass and buildings use individual instances. Consider spatial broad-phase picking or MultiMesh only after large-map profiling, with tests for tall-object priority, hover, changing ownership and animated departure. |
| Remaining coordinators | The board still owns camera, unit presentation and synchronization; the rules facade owns topology and economy; the session exposes many HUD aliases for existing consumers. Extract another cohesive subsystem when features justify it, rather than moving unrelated methods into miscellaneous utility files. |
| Mutable records and extension | Cells, commands and intent data remain dictionaries/string kinds. Save/load, multiplayer or more unit tiers should introduce versioned typed records, stable identifiers and a clear model interface. Internal movement rules now belong in `kingdom_movement.gd`; overriding only a facade wrapper is not a supported extension strategy. |
| Shared resources | Cached meshes/materials are shared resources. Never alter a returned cached material's transparency, tint or cull mode in place; request a keyed variant or duplicate it for an instance. Include new appearance parameters in cache invalidation/keying and keep cache growth bounded. |
| Island visual parity | Every island appearance preference must cover gameplay and the menu landmass, including initial loading, live/hidden changes and streamed rows. Continue using shared asset/terrain helpers and parity tests; do not introduce another menu-only rendering approximation. |
| Options layout | The 600 px options panel fits the minimum 620 px window height with little spare room. More rows should use a scrolling/container layout rather than continuing to extend manually positioned coordinates. |
| Packaging/history | There is still no Git repository or export preset. The local snapshot is a recovery aid, not version control. Keep engine-managed `.godot/` and original assets intact; retain reproducible generated artifacts under `.gdignore`. |

Difficulty balance, deeper enemy forecasting and subtle shadow shimmer in continuous motion remain separate gameplay/presentation investigations. This refactor neither changes those policies nor claims they are fully solved.

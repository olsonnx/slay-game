# Capture updates and frame pacing

Follow-up to the [strategy-scale report](strategy-scale-optimization-2026-10-14.md), implemented 14 October 2026.

The subsequent [strategic AI and command-update pass](strategic-ai-2026-10-14.md) adds a large-map planner alongside the retained beam backend, selective capture reconstruction and cooperative command batches. Measurements below describe the earlier capture pass.

## Changes

- Movement playback freezes only changed records, plus each action's source and target, before starting tweens. Distant capital and kingdom edits are included by comparing the final command state at that boundary. Completion publishes this explicit delta rather than another complete board snapshot.
- Ordinary board refreshes preserve unchanged cell records and touch changed tiles and their immediate neighbours. Ownership changes retain the tile hierarchy. Mountain and bridge changes keep the topology replacement path. Cancellation, new maps and other full-state callers still have a complete synchronization path.
- Static geometry scans use a chunk-to-tile index. Source cleanup and signature comparisons are confined to affected chunks. Army updates use their own chunk index and remove hidden/moving/defeated sources from the affected groups; full lifecycle and filter changes retain a complete fallback.
- Color-only terrain changes update RGBA8 attribute ranges in the existing dynamic ArrayMesh, including earth colors used by filters. Positions and normals remain allocated. Changes to actual join geometry still rebuild the relevant terrain chunk.
- Gameplay props retain their 24-hex draw chunks; terrain within them uses separate 12-hex upload groups. An intermediate version made all static chunks smaller, increasing draw calls from 313 to 433 in the 600-unit fixture. The final version splits only terrain to retain the cheaper prop submission. Automatic publication uses a **1.5 ms soft budget** and processes coherent chunks across frames; repeated edits to a waiting chunk coalesce. A single chunk can exceed the budget, so this is not a hard 1.5 ms or 240 FPS guarantee. Explicit flushes drain the queue; topology changes use the safe complete update path. Authoritative rules and impact-time financial feedback remain synchronous.
- The visible economy is a private readout model containing complete player territory, the inspected faction, all bridges and player-supported garrisons. Unrelated enemy territory is excluded. Rebuilding that model cannot mutate the live rules or visible cells. This narrows the graph being rebuilt, rather than introducing a new authoritative incremental economy algorithm.
- Diagnostic turn runs record visible-copy, tile-update, visible-listener, economy-readout and army-sync times. AI snapshot and authoritative commit times are also recorded. Static scans/builds retain their separate timing and touched-tile counters.

The buffer layout was checked against the [Godot 4.6.3 rendering source](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/servers/rendering/rendering_server.cpp). The implementation verifies the engine-reported color stride and falls back to rebuilding if the expected layout is unavailable. A native screenshot verifies the color update visually.

## Verification

The new capture suite checks narrowed readouts against complete kingdom rebuilding, including treasury, capital/territory ordering, income, bridge wages and player mana. It also checks record isolation, retained tiles, color-only buffer retention, scoped army buffers against a full rescan, removed sources and budget queue progress. The final headless suite passed **1,149 checks**. Earlier intermediate and native visual runs passed 1,150 and 1,149 respectively; assertion counts vary with the retained batch/source groups.

All **30 regression suites passed**, including batching, animation, castle expansion, army, heatmap, immediate turn feedback, cancellation, editor, startup, map determinism and shared menu rendering. Raw native results are recorded separately under `artifacts/map_stress_heavy_turn_normal_120_capture_*.json`; intermediate stages are retained to avoid selecting only favourable measurements. The native color-buffer preview is `artifacts/capture_color_buffer.png`.

## Measurements

Native Huge, 1,000 tiles, seed 71, 120 units, six factions, Normal AI, requested 6× playback, 1920×1080, saved 8× MSAA, Water, shadows on, uncapped/VSync off. This synthetic workload uses the same fixture as the previous report. It is not an ordinary economy-feasible endgame or a universal hardware guarantee.

**Benchmark correction:** the original harness set the human speed-hold flag once. Window-focus notifications can clear that flag. A repeated final run timed out at 180 seconds with 126 decisions; investigation found this weakness, so the final probe now reasserts the requested speed before each process frame and records the observed scale. Older wall times and frame distributions below remain raw observations, but are not strict controlled 6× comparisons. Focus loss was not logged in those runs, so it is a possible contaminant rather than a proven explanation for every variation.

| Complete-round code stage | Duration | Mean FPS | p99 frame | Worst frame |
| --- | ---: | ---: | ---: | ---: |
| Previous final implementation | 109.29 s | 226 | 15.85 ms | 148.69 ms |
| Changed records / retained tiles, intermediate | 115.00 s | 207 | 23.59 ms | 250.26 ms |
| Budgeted 12-hex chunks, intermediate | 114.58 s | 188 | 23.06 ms | 86.40 ms |
| Indexed 12-hex chunks, intermediate | 117.59 s | 182 | 21.16 ms | 94.15 ms |
| Final: indexed batches, split terrain / wider props | 105.01 s | 232 | 18.17 ms | 78.45 ms |
| Final repeat, incomplete / unverified speed | >180 s | 198 | 8.05 ms | 93.21 ms |
| Final with verified 6× playback | 123.21 s | 186 | 24.14 ms | 85.76 ms |

The verified 6× round retained 137 AI decisions and completed normally. Telemetry recorded **22,959 frames at 6×**, plus one final completion frame at 1× after the turn ended. It missed the 240 FPS frame budget on **75.32%** of frames. The final runs' worst frames were below the previous 148.69 ms observation, but the average and p99 results do **not** establish a broad frame-pacing improvement or stable 240 FPS. The intermediate results show why reducing every static chunk was not retained: the cheaper upload transaction increased steady drawing cost. Speed-control and environmental differences prevent a strong causal before/after FPS claim.

| Profiled main-thread stage | Verified 6× mean | Maximum |
| --- | ---: | ---: |
| Freeze/publish changed visible records | 0.77 ms | 4.65 ms |
| Tile hierarchy / prop updates | 3.75 ms | 12.44 ms |
| Army batch sync | 2.97 ms | 9.00 ms |
| Visible economy readout | 4.98 ms | 6.74 ms |
| Static source scan | 3.35 ms | 11.12 ms |
| Static batch build/upload preparation | 9.93 ms | 19.43 ms |
| Owning-thread AI snapshot | 6.41 ms | 8.45 ms |
| Authoritative movement batch commit | 27.37 ms | 59.24 ms |

In the first intermediate capture run, army sync averaged **9.59 ms**, static scanning **6.64 ms** and static building **12.63 ms**. The verified final sample has lower measured presentation costs, consistent with the narrower update paths; those separate runs are not a paired experiment. Visible-listener timing includes the economy readout and UI work; it is not an additional independent duration to add to this table. Static timings refer to each transaction, and transactions can contain several retained drawing groups.

The new evidence identifies **authoritative commits as a substantial remaining bottleneck**. Snapshot creation and economy reconstruction also individually exceed a 240 FPS budget in some samples. Those costs remain synchronous; improved drawing and secondary upload scheduling cannot remove them.

## Remaining limits

This pass removes repeated presentation work and distributes secondary uploads. It does not make the rules graph incremental, move authoritative commits to another thread or share live mutable game state with workers. Larger castle surrenders can still update several provinces together. Border topology changes still need geometry work; smaller chunks bound the transaction size but add some draw submissions.

Whole-round average FPS, p99 and worst frames must be considered together. These results do not prove that every capture meets the 4.17 ms budget. The next substantial change should address authoritative commits and kingdom reconstruction, with either smaller cooperative commit phases or private worker-owned simulation followed by a validated main-thread publication. That requires preserving capital splitting, gold, bridges, encounter secrecy, RNG and cancellation; simply sending the live mutable rules object to a worker would be incorrect.

The corrected dataset is `artifacts/map_stress_heavy_turn_normal_120_capture_pinned.json`. Reproduce with native Godot: `--path . --script tools/heavy_strain_probe.gd -- --mode=turn --difficulty=normal --units=120 --turn-limit=240 --label-suffix=capture_pinned`. The fixed speed hold exists only in the diagnostic harness; normal gameplay still resets human holds on focus loss.

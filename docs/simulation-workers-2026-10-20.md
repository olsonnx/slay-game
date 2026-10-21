# Ordered simulation workers

AI turn preparation and movement now run against private rules on a worker. This includes settlement, planning, route validation, captures, kingdom reconstruction, encounters, random-number advancement and replay delta generation. The main thread publishes a completed state patch and animates its ordered records. Game rules and AI budgets are unchanged.

## Ownership and scheduling

`KingdomAI` owns one retained simulation lane per opponent controller. Work on that lane is serial because commands can depend on earlier captures. It runs concurrently with rendering, rather than dispatching dependent moves to arbitrary concurrent workers. Input indexes are copied on the main thread; their records have a read-only lease while commands are locked. The worker synchronizes them into its own model before any mutation.

Unchanged worker records are retained. The read-only strategic planner borrows those private records instead of cloning the board again; encounter markers remain hidden from planning. Legacy search branches still require independent copies. A worker result contains only changed cells, removed coordinates, changed state sections and decision diagnostics. The renderer receives scoped preparation and movement patches, including distant collateral changes. Deletions retain the complete-board rendering fallback.

Replay recording uses a private fork of the recorder's immutable index. Completed rows and their intermediate deltas are published in order with the state; cancelled work contributes neither state nor replay rows. Worker cancellation is checked between planning steps and commands, pool tasks are acknowledged, and pause prevents publication. No active scene nodes are modified by the worker.

The existing terrain upload budget and coalesced army refreshes remain in place. Rendering and player commands remain on the main thread. The [round-handoff follow-up](turn-handoff-2026-10-20.md) also moves World processing and player settlement onto the worker and budgets their presentation updates. Replay transactions and the diagnostic `ai_simulation_workers = false` override retain the earlier execution path. This is an incremental simulation boundary, not a complete engine rewrite or a claim that every subsystem uses every CPU core.

## Validation

The new worker suite passes 1,058 checks in both headless and native Forward+. It compares serial and worker preparation and movement, complete state/RNG, animation records and intermediate replay deltas. It exercises a randomized duel encounter, partial rendering patches, removed/new tiles, effects, mana, dynamic faction count, nested ownership isolation and cancellation. Unchanged published cell records retain their identity.

Also passed: architecture 79, strategic AI 2,477, AI 180, replay 119, tactics 44, bridge campaigns 26, playback speed 30, animation 47, capture updates 2,202 and wildlife presentation 62. Playback, animation, capture and wildlife checks were also run natively. The worker suite is registered in `tools/run_tests.ps1`.

## Performance evidence and limits

Two complete Huge-map captures used 1,019 tiles, 120 units, seed 71 and Ctrl 6×. Both completed the same 122 decisions, 74 static chunk rebuilds and 72 synchronizations:

| Execution | Mean FPS | 95th-percentile frame | Planning/settlement 95th percentile | Round |
|---|---:|---:|---:|---:|
| Earlier execution, matched follow-up capture | 109.0 | 22.300 ms | 31.651 ms | 30.485 s |
| Ordered worker | 96.8 | 22.396 ms | 25.201 ms | 30.620 s |

This does **not** establish an overall FPS improvement. Idle and animation timings also varied substantially, including periods when no simulation worker was running. Earlier captures from the previous investigation had significantly higher FPS in both configurations of the broader experiment, so those older numbers are not a reliable paired baseline here. The worse mean FPS in this pair is retained rather than omitted.

The tracked main-thread worker input/publication stages totalled about 51 ms over 47 jobs in the initial worker capture, versus about 1,307 ms of snapshot/commit stages in the matched earlier-path capture. This isolates the intended reduction in main-thread computation, not total frame cost. Final profiling additionally includes handoff cleanup in the publication stage.

A short, same-process comparison keeps the rendered board fixed and interleaves identical preparation plus two movement batches: serial / worker / worker / serial. All four final position hashes match. With a fresh recorder per case, worker phases took 1.068 and 1.076 s; serial phases took 2.235 s cold and 1.143 s warm. Frame-time distributions overlap. These few samples support reduced phase/handoff cost, not a universal FPS or multicore scaling guarantee.

Raw captures are `artifacts/map_stress_heavy_turn_normal_120_simulation_worker.json`, `artifacts/map_stress_heavy_turn_normal_120_simulation_serial_paired.json`, and `artifacts/map_stress_heavy_simulation_interleaved_final.json`. The earlier interleaved diagnostic reused the recorder between cases and was superseded by the final comparison.

Reproduce the focused comparison with `tools/heavy_strain_probe.gd -- --mode=simulation --map-size=huge --units=120`. Full native Ctrl captures use `--mode=turn --diagnose --speed=6`; add `--ablation=serial_simulation` to compare the earlier execution path. Avoid concurrent rendering/test processes when collecting timings.

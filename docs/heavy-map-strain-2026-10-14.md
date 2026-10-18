# Large-map army and AI strain

Measured on 14 October 2026, after the map-generation, batching, LOD and smooth-detail-fade changes.

**Historical baseline:** the recommendations below have since been implemented. See the [strategy-scale implementation and comparison](strategy-scale-optimization-2026-10-14.md) for the updated rendering/AI measurements and remaining capture-time pauses.

## Finding

**Huge is fast on an initial board, but does not hold 240 FPS with hundreds of visible soldiers.** Three separate costs now matter: army draw submission, repeated AI candidate scoring, and main-thread terrain rebuilding during actual turn playback. Further generation optimization will not address these costs.

The strongest next changes are to batch settled soldiers and their accessories, separate unit updates from terrain updates, and reuse region/target analysis across units in each immutable AI position. Preserve the existing AI depth and decision rules while pursuing those changes.

## Method and limits

- Same i5-9300HF / RTX 2060 machine, Godot 4.6.3 Compatibility, 1920×1080, saved 8× MSAA, Water, shadows enabled, VSync off, uncapped FPS.
- Production Very Large and Huge profiles, seed 71, six factions. A deterministic multi-source expansion fills the generated passable island with six contiguous faction regions. Mountains and remaining decorations are retained.
- Distribute 120, 300 or 600 soldiers over the board, with a mix of Scouts, Soldiers and Knights. All start ready. Provincial values are raised to six and banks receive 300 gold to keep the workload funded rather than immediately starving armies. These are artificial late-game fixtures, not evidence that typical matches naturally reach this density.
- Rendering samples last six seconds after one second of warm-up. An overview includes the whole board; close views use zoom 11. Hover moves the pointer across the board. Controlled ablations use a stationary overview on the same 600-unit fixture.
- Native worker measurements use the actual production snapshot/search job and planning profile. Interactive picking is disabled while busy, as in normal gameplay. The live board remains untouched by these searches.
- Headless CPU timings are medians of three fresh-position measurements. Diagnostic search attribution instruments copied source files, never the production algorithms. Its timings are inclusive: route and target time is already contained in candidate/evaluation time.
- This is one deterministic late-game layout on one machine. Short samples, desktop activity, faction distribution and camera position affect tails. A 240 FPS frame budget is **4.167 ms**; an average above 240 does not establish stable 240 FPS.

## Crowded rendering

| Size | Units on board | View | Mean FPS | p95 frame | p99 frame |
| --- | ---: | --- | ---: | ---: | ---: |
| Very Large, 500 tiles | 0 | Moving hover overview | 489 | 3.09 ms | 5.21 ms |
| Very Large | 120 | Moving hover overview | 308 | 5.67 ms | 6.82 ms |
| Very Large | 300 | Moving hover overview | 207 | 7.60 ms | 8.35 ms |
| Very Large | 300 | Close | 444 | 2.84 ms | 3.20 ms |
| Huge, 1,000 tiles | 0 | Moving hover overview | 358 | 8.11 ms | 9.10 ms |
| Huge | 120 | Moving hover overview | 239 | 9.63 ms | 10.84 ms |
| Huge | 300 | Moving hover overview | 172 | 11.47 ms | 12.37 ms |
| Huge | 300 | Close | 460 | 2.74 ms | 3.08 ms |
| Huge | 600 | Moving hover overview | 116 | 14.34 ms | 14.97 ms |
| Huge | 600 | Close | 390 | 3.12 ms | 3.55 ms |

The neutral initial-board benchmark did not contain these large owned regions or armies. Even the zero-unit expanded board has slower hover tails: its active kingdom can contain well over seven tiles, and pointer changes recreate the kingdom/intent overlays. This difference must not be attributed entirely to soldiers.

An additional stress fixture combines **300 units, 150 houses/towers, 50 fortified structures and 50 barriers**. Its moving-hover overview averaged **109 FPS**, p95 **14.55 ms**, p99 **15.20 ms**; the close view averaged **358 FPS**, p95 **3.34 ms**, p99 **3.72 ms**. This is a rendering upper-bound fixture with artificially abundant simultaneous effects, not a normal mana-budget scenario. Reported primitives rose to approximately **282,500**, versus approximately **49,900** for the plain 300-unit overview. Fortification spheres use freshly allocated default-tessellation meshes, while each barrier has six translucent wall meshes and six separate rim meshes. Share and simplify the spheres using retained near/far mesh variants; merge each barrier's six panels and six rims into a small number of reusable surfaces. Preserve visible protection and barrier state. Test transparent ordering before combining effects across tiles.

### Same-board army ablation

| Huge, 600 units, stationary overview | Mean FPS | p95 frame | Reported draw calls | Median render CPU | Median render GPU |
| --- | ---: | ---: | ---: | ---: | ---: |
| Full army | 138 | 8.60 ms | 3,387 | 6.57 ms | 2.98 ms |
| Hide rank pips | 170 | 6.78 ms | 1,587 | 5.25 ms | 1.91 ms |
| Also hide flat blob shadows | 224 | 5.10 ms | 987 | 3.86 ms | 1.19 ms |
| Also hide soldier sprites | 532 | 2.35 ms | 387 | 1.40 ms | 0.70 ms |

Shadows remain enabled throughout this controlled sequence. These are diagnostic removals, not proposed gameplay behavior. Rank and soldier visibility must remain readable in the final solution. The renderer's reported draw counter also reflects shadow-pass work; use these values consistently as the same counter, not as an independently verified count of just color-pass submissions.

In the separate moving-hover run, disabling ordinary game/board processing raised the 600-unit sample from 116 to 137 FPS. Disabling realtime shadows gave 133 FPS. Neither restores 240 FPS. The flat blob shadows are separate transparent planes and are still drawn when the realtime Shadows setting is off.

Source explanation: `BoardView.add_unit()` creates a sprite, a blob-shadow mesh, individual rank cylinders and a hidden hover sprite for every actor. Static batching deliberately excludes the entire `unit_role` subtree, so settled soldiers and their accessories do not benefit from the terrain/prop batches. The shadow plane and material are also allocated per soldier. The cost grows with visible actors even when no soldier is moving.

## AI search and waiting

| Huge | Difficulty | One movement search | Evaluated branches | Mean FPS during search | Main-thread snapshot |
| ---: | --- | ---: | ---: | ---: | ---: |
| 120 units | Normal | 1.07 s | 35 | 291 | 4.30 ms |
| 120 units | Hard | 6.86 s | 157 | 287 | 4.49 ms |
| 300 units | Normal | 1.79 s | 35 | 199 | 3.85 ms |
| 300 units | Hard | 12.27 s | 157 | 198 | 3.88 ms |
| 600 units | Normal | 2.62 s | 35 | 125 | 4.90 ms |
| 600 units | Hard | 18.64 s | 157 | 120 | 3.96 ms |

These are one search each, not one entire faction turn. Normal can commit up to three planned moves together and Hard up to five, but dependent paths, captures with annexation, merges and special outcomes stop playback batches early and trigger a new search. A faction with many ready units can therefore pay this cost repeatedly. Spending has its own repeated searches: up to eight purchases on Normal and twelve on Hard.

Workers keep planning off the main thread, but do not make expensive analysis fast. The main-thread snapshot alone uses approximately an entire 240 FPS budget on Huge. The largest observed worker step reached 889 ms with 600 units: cancellation is checked between steps, so a single candidate/layer transition can also delay cancellation acknowledgement.

### Where search time goes

Instrumented headless Huge/300-unit search:

| Operation | Normal | Hard | Hard calls |
| --- | ---: | ---: | ---: |
| Total wall | 1,470 ms | 9,689 ms | — |
| Candidate generation, inclusive | 683 ms | 5,669 ms | 33 |
| Evaluation, inclusive | 464 ms | 2,368 ms | 182 |
| Snapshot copies | 148 ms | 643 ms | 163 |
| Reachable-target queries, already included above | 170 ms | 1,270 ms | 1,711 |
| Friendly-route queries, nested within the above | 130 ms | 857 ms | 2,670 |

Candidate generation consumes approximately **59%** of Hard search wall time, evaluation **24%**, snapshots **7%**. These three top-level instrumented operations account for about 90%; the remainder includes command application, rebuilds, sorting elsewhere and uninstrumented bookkeeping. Nested query counters must not be added again.

Fresh Huge-position costs at 120 / 300 / 600 units were respectively:

- Movement candidate pass: **67 / 144 / 242 ms**.
- Spending candidate pass: **45 / 63 / 94 ms**.
- Evaluation including threats/economy: **9.5 / 12.9 / 19.7 ms**.
- Full snapshot: approximately **4.1 ms**; kingdom rebuild: approximately **7.7–8.3 ms**.

`AiCandidates.movements()` enumerates all legal destinations for each ready unit, constructs an action dictionary for each, scores them, sorts the complete array, and only then retains 7 or 9 candidates with at most two per source. Each unit also rebuilds a source-rooted route tree through its friendly component. Queries memoize a source within a position, but do not eliminate repeated traversal and target scoring across units sharing the same territory. Hard adds reply analysis against all five other factions.

## Prioritized changes

1. **Separate terrain, prop and soldier updates.** A change to `moved`, tier or soldier position currently removes and rebuilds the whole tile; the new node identities also invalidate chunk signatures. Update soldier tint/texture/transform independently, retain terrain nodes, and rebuild terrain only for actual surface, ownership, join or topology changes. Queue/coalesce visible-board and economy notifications once per frame. This addresses turn hitches before increasing map sizes further.
2. **Batch settled army rendering.** Use spatial batches of billboard quads grouped by texture/material, tier and faction, with per-instance moved tint. Retain actors/picking metadata, and temporarily promote moving/hovered soldiers to individual actors. Share blob-shadow geometry/material and batch it separately. Combine rank cylinders into one reusable tier mesh, batch them, or include readable rank information in the soldier quad. Keep camera culling granular enough that close views retain their current advantage. Verify alpha-cut silhouettes, hover outlines, sprite priority, animations and cancellation in Compatibility rendering.
3. **Reuse AI component/target analysis and bound candidate storage early.** Build passable friendly components, frontier sets, defense tables and unit/faction indexes once per immutable position. Candidate enumeration needs legal destination membership; it usually does not need a complete source-rooted path tree. Defer source paths until a shortlisted command is simulated/committed. Precompute target priority terms shared by units of the same faction/tier, retain the best two actions per source and the global candidate budget while enumerating, and avoid creating/sorting discarded action dictionaries. Preserve tie ordering and branch choice with equivalence fixtures; bridges, barriers, equal-tier merges and moved receivers require explicit coverage.
4. **Reduce branch copying and evaluation rescans.** Share immutable topology and use compact indexed cell state, or copy only changed cells/banks within worker-owned positions. Maintain deltas for land, unit value, income, wages and local defense when safe. Preserve kingdom-split/capital/bridge semantics and encounter secrecy. Start with compact snapshots and eliminating the redundant initial worker copy; full persistent branch state is a larger refactor. Never share mutable live dictionaries with workers.
5. **Retain strategic overlays and reuse effect geometry/materials.** Keep the active-kingdom outline until membership changes, update only the pointer/route/intent layer, and reuse marker nodes or merged stroke geometry. Consider an exterior perimeter rather than hundreds of separately drawn hex outlines if readability remains clear. Barrier walls/rims and fortification meshes should share retained geometry/materials and use grouped drawing where correct transparent ordering permits. Any distant simplification should preserve gameplay meaning and follow the existing smooth-transition policy.
6. **Bound work and expose real progress.** Split long worker candidate-generation passes into cancellable chunks. Avoid silent reductions in AI depth as the first optimization. Once exact savings are measured, evaluate a turn-level budget and explicit quality tradeoffs if exceptionally dense positions still take too long. Progress should reflect real planning/playback, not a fabricated percentage.

No FPS or AI speedup is promised for these proposed changes before implementation and measurement. The army-removal tests establish an upper bound on removable cost; they do not predict the exact result of a batching implementation.

## Actual turns and selected-unit hitches

With 120 units on Huge, a **complete five-opponent Normal round took 102.67 seconds**, even with 6× presentation playback. It committed 137 AI decisions and performed 168 batch synchronizations / 227 chunk rebuilds. Mean FPS was **243**, but p95 was **5.01 ms**, p99 **11.73 ms**, and the worst frame **125.31 ms**. Approximately **16.6%** of frames exceeded the 240 FPS budget. This workload therefore does not sustain stable 240 FPS despite its average.

At 300 units, a Normal round was still processing faction five after a **180-second limit**. The partial sample committed 158 decisions, averaged **176 FPS**, and had p95 **7.28 ms**, p99 **11.72 ms**, and maximum **123.29 ms**. It did not complete; do not treat 180 seconds as its full round duration. The original sample recorded 202 syncs / 260 rebuilds including shutdown cleanup; excluding its final two cleanup syncs leaves 200 syncs / 258 rebuilds. Those gameplay batch syncs averaged **8.30 ms scanning** plus **19.51 ms rebuilding**, with peak build time **51.32 ms**. The output was saved before the later measurement refinement that snapshots counters before shutdown.

Selecting a unit adds another serious, independent hitch. The native selected-unit fixture has **174 legal destinations**.

The selected-unit moving-hover run averaged **138 FPS**, with p99 **67.30 ms** and a worst frame **76.81 ms**, while terrain synchronization/rebuild counters stayed at zero. This demonstrates that hover hitches can originate entirely outside terrain batching. A headless isolation of the same geometry measured:

| Overlay operation, five-sample median | Cost |
| --- | ---: |
| Rebuild reachable-area border and wash | **55.73 ms** |
| Build its longest route, 16 hexes | 1.68 ms |
| Recreate active-kingdom outlines on hover | 3.25 ms |

`BoardOverlays.show_overlays()` includes `hovered` in its signature and clears all annotation children whenever that signature changes. It then rebuilds the unchanged reachable region. `show_area()` constructs two border layers plus a fill; every stroke segment emits 16-triangle endpoint caps at both ends, duplicating round-cap work at joined edges. The measured reachable-area build is far more expensive than the route in this fixture. **Retaining that mesh while only hover/path changes should be treated as an early priority alongside separating unit updates from terrain.** The report's overlay proposal is supported by direct timing rather than only a draw-count inference.

Stopping the first timed-out turn exposed a production cancellation bug: the ternary expression in `KingdomAI.movements_async()` returned an untyped empty array through an `Array[Dictionary]` return contract. It now uses an explicit typed-return branch. A new cancellation regression and the existing AI suite passed: **186 checks, zero failures**. The harness also waits for the opponent coroutine to unwind before freeing its game. No gameplay AI policy or rendering optimizations were implemented as part of this analysis.

## Reproduction and evidence

`tools/heavy_strain_probe.gd` uses the production game and accepts `--mode=render`, `ai`, `turn`, `ablate`, `interaction` or headless `cpu`. Turn mode accepts `--difficulty=normal|hard`, `--units=300` and `--turn-limit=180`; playback is accelerated 6× to emphasize processing rather than presentation delay. Timeout samples must be labelled partial.

Run `tools/prepare_heavy_profile.ps1` before headless `tools/heavy_ai_profile.gd` to refresh the instrumented source copies. These copies add inclusive timers but leave the simulated policy intact.

Raw artifacts are `artifacts/map_stress_heavy_render.json`, `map_stress_heavy_ablate.json`, `map_stress_heavy_ai.json`, `map_stress_heavy_cpu_before.json`, `map_stress_heavy_interaction.json`, `map_stress_heavy_turn_normal.json`, `map_stress_heavy_turn_normal_120.json`, `heavy_ai_profile.json` and `heavy_overlay_profile.json`. The original CPU medians were preserved from printed probe output after its default file was reused; that artifact states this provenance. A native 600-unit overview is saved as `artifacts/heavy_huge_600.png`.

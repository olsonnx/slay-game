# Strategy-game scale: implementation and comparison

Implemented 14 October 2026, following the [crowded-map strain report](heavy-map-strain-2026-10-14.md).

The subsequent [capture-update pass](capture-updates-2026-10-14.md) implements changed-record publication, chunk indexes, retained color buffers, budgeted uploads and narrowed economy readouts. The measurements below describe the earlier stages; consult that follow-up for current full-turn results.

## What the comparison with EU IV and Total War tells us

The number of visible soldiers is not a direct measure of CPU work. Shared meshes, textures, material state and draw submissions make large crowds cheap to display; separate rendering objects and rebuilding unchanged geometry make even a modest crowd expensive. Creative Assembly's own **Total War: Three Kingdoms** presentation explicitly covers its engine's instancing pipeline and a change to order-independent particle transparency. This is direct evidence for instancing in Total War, rather than an inference from its unit count. Its earlier optimization blog also describes separating game-draw and rendering threads and distributing CPU work more effectively. [Creative Assembly GDC presentation](https://www.gdcvault.com/play/1026177/Instancing-and-Order-Independent-Transparency), [official optimization blog](https://wiki.totalwar.com/w/Optimisation_Blog).

Simulation throughput and render latency are different budgets. EU IV's developers measure daily and monthly simulation ticks, and Paradox's threading presentation discusses how simulation threading models evolved to keep complex games fluid. These sources do not document every current EU IV AI subsystem, so claims about precisely which country recalculates on which day would be speculation. The applicable architectural lesson is to schedule expensive simulation separately from drawing and avoid repeated analysis when relevant state has not changed. [EU IV developer diary, 9 November 2021](https://store.steampowered.com/news/posts/?appids=236850&enddate=1636621512&feed=steam_community_announcements), [Mathieu Ropert's Paradox threading talk](https://accu.org/video/spring-2023-day-3/ropert/).

There is also a large difference between a smooth 60 FPS experience and a stable 240 FPS target: the frame budgets are 16.67 ms and 4.167 ms respectively. That arithmetic does not establish the actual FPS of either comparison game on this PC. Neither engine is universally free of bottlenecks; Creative Assembly's published account specifically identifies CPU bottlenecks and end-turn optimization work.

For this game, the measured problem was avoidable repeated work rather than the inherent cost of drawing 600 pixel soldiers. The changes below apply those principles within Godot's Compatibility renderer. Godot's own documentation recommends MultiMeshes for large repeated-object counts, and spatially partitioning them because individual instances cannot be culled independently. [Godot MultiMesh guidance](https://docs.godotengine.org/en/4.6/tutorials/performance/using_multimesh.html).

## Implemented architecture

### Retain annotation geometry

The reachable-area border/wash stays allocated while selection and destination membership remain unchanged. Pointer motion changes the hover marker and route, not the large region mesh. The active-kingdom outlines are now a retained spatial instancing object; changing the highlighted province updates the affected slots rather than deleting and recreating all kingdom outlines. Board changes, clear-indicator preferences, protection previews and externally cleared overlays still invalidate the appropriate state.

This specifically removes the previously measured approximately 56 ms reachable-area rebuild from ordinary pointer motion. It does not change which destinations are legal.

### Update soldiers independently of terrain

Moved tint, rank and sprite changes update an existing actor. Unit arrival/departure and tree/building/effect changes refresh the relevant prop content while retaining the tile's soil and surface nodes. Ownership, mountain and bridge topology changes retain the necessary terrain update path. Moving actors still have source objects for cancellation and recorded playback.

Static chunks retain unchanged individual batch groups even when another group in the same chunk changes. In particular, a new prop or grass patch no longer automatically regenerates that chunk's identical merged terrain mesh. A separate terrain rebuild counter makes this distinction measurable.

Changed terrain uses cached geometry templates for hex joins, borders and exposed cliffs. Packed arrays assemble the chunk without repeatedly emitting triangles or regenerating normals. An independent comparison against the previous SurfaceTool path verifies winding, normals and geometry. Unchanged actors skip texture/transform updates, and unchanged static records reuse their source-node membership during batch scans.

### Draw settled armies together

`src/rendering/army_batches.gd` partitions settled armies into 12-hex spatial groups. Billboard quads share textures/materials by tier and faction; moved state uses per-instance color. Rank meshes and flat shadow planes also share drawing groups. The source actor/sprite hierarchy remains available for opaque-pixel picking, hover outlines, animation, heatmap and island lifecycle.

Actors moving under the animation root restore their own render layers and leave settled batches. Island transitions and disabled batching restore the source rendering path. Billboard-aware bounds prevent zero-depth quads from being culled incorrectly when the camera changes angle. No whole-map unit-count limit or hidden strategic units were introduced.

Hover changes one instance color while the original hover outline fades. An intermediate version promoted hovered sprites by rebuilding batch buffers; native measurements revealed new hover stalls. The final version updates a mapped instance slot directly and retains buffers during hover.

Protection/barrier geometry uses retained materials and spatial groups. All six translucent barrier panels and their rims remain present. Fortification spheres share a 32-segment / 16-ring mesh rather than allocating a default high-tessellation sphere per tile. Shield and barrier meaning, translucency and spell behavior remain intact.

### Analyze territory once per AI position

Each worker-owned immutable position caches accessible components, destination membership by component/rank, adjacent cells, defense and target scoring terms. Candidate enumeration no longer builds a new source-rooted route tree for every unit just to discover the same territory. Authoritative commands still construct and validate exact routes when simulating or committing a shortlisted action.

Threats aggregate army strength and source lists by reachable region before applying them to its boundary. The original source ordering is retained when multiple regions threaten a province. Shared target scores exclude source-specific seeded variation; that variation is added per unit as before.

The planner already allowed at most two movement candidates per source. The implementation now retains that shortlist while enumerating, then applies the existing faction-wide budget. This avoids allocating and sorting thousands of discarded action dictionaries. Depth, beam width, difficulty profiles, spending limits and Hard reply analysis remain unchanged. Candidate ties may be resolved through a different enumeration order; the regression compares full candidate arrays against the saved original implementation on generated, crowded and bridge/barrier fixtures rather than claiming every possible board is identical.

Search jobs transfer their private initial snapshot into the planner instead of making a second initial copy. Branch state remains private; live mutable rules are never shared with workers. Cell snapshots copy their scalar records, and kingdom/effect collections remain independently copied. Owning-thread snapshot time remains near an entire 240 FPS budget in the measured Huge scenarios, so this is still an important future optimization.

## Native results

Same i5-9300HF / RTX 2060, Godot 4.6.3 Compatibility, 1080p, saved 8× MSAA, Water, shadows on, uncapped/VSync off, seed 71, artificial late-game fixtures from the original report. Rendering samples are six seconds after warm-up. These are practical measured gains on one machine and layout, not every-frame guarantees or a universal endgame certification.

| Huge workload | Before mean FPS | After mean FPS | Before p99 | After p99 |
| --- | ---: | ---: | ---: | ---: |
| 300 units, moving-hover overview | 172 | **361** | 12.37 ms | **4.47 ms** |
| 600 units, moving-hover overview | 116 | **369** | 14.97 ms | **4.60 ms** |
| 600 units, close view | 390 | **506** | 3.55 ms | **3.32 ms** |
| Selected unit, 174 legal targets | 138 | **324** | 67.30 ms | **7.41 ms** |
| 300 units + 150 structures + 50 wards + 50 barriers, overview | 109 | **269** | 15.20 ms | **7.11 ms** |
| Same effects fixture, close | 358 | **433** | 3.72 ms | **3.79 ms** |

Very Large / 300 units improved from 207 to **440 FPS**, with p95 **3.22 ms**, p99 **3.90 ms**. Huge / 600 units now passes the 240 FPS p95 budget at **3.70 ms**, but its **4.60 ms p99** still misses it. The most extreme effects and selected-unit cases retain slower tails. Therefore the changes significantly improve crowd scale without yet establishing stable 240 FPS across all heavy states.

The Huge/600-unit stationary no-script sample's reported draw calls fell from approximately **3,387 to 313**, while its visible primitives remained approximately **60,303**. This demonstrates shared submission rather than hiding soldier/rank geometry. The effects fixture's reported primitives fell from approximately **282,523 to 125,723**, principally from the shared lower-tessellation shields, and reported draw calls from **2,840 to 572**. The same renderer counter is used throughout; it can reflect shadow-pass work and should not be interpreted as an independently measured color-pass-only counter.

### AI searches

| Huge units | Difficulty | Before one search | After one search | Before FPS during search | After FPS |
| ---: | --- | ---: | ---: | ---: | ---: |
| 120 | Normal | 1.07 s | **0.81 s** | 291 | **381** |
| 120 | Hard | 6.86 s | **4.86 s** | 287 | **361** |
| 300 | Normal | 1.79 s | **1.00 s** | 199 | **378** |
| 300 | Hard | 12.27 s | **5.92 s** | 198 | **375** |
| 600 | Normal | 2.62 s | **1.25 s** | 125 | **380** |
| 600 | Hard | 18.64 s | **6.75 s** | 120 | **365** |

Branch counts remain 35 Normal / 157 Hard for these fixtures. The 600-unit peak worker step dropped from **889 ms to 160 ms**, improving cancellation acknowledgement as well as planning latency. Main-thread snapshots still measured approximately **3.7–4.9 ms** in the native samples.

Headless Huge / 300-unit candidate generation improved from **144 to 29 ms**, and 600-unit from **242 to 35 ms**. Spending passes improved from **63 to 38 ms** and **94 to 33 ms** respectively. Three-sample medians and short native runs have noise; for example the 120-unit candidate median was unusually high relative to the denser fixtures, so these results should not be interpreted as a smooth fitted scaling curve.

### Complete turn playback: unresolved pauses

The complete Normal opponent round on Huge with 120 units, six factions and 6× playback still performs 137 decisions, 168 static syncs, 222 changed-chunk builds and 165 terrain builds. This is a more demanding test of capture publication than timing one worker search.

| Complete-round run | Duration | Mean FPS | p99 frame | Worst frame |
| --- | ---: | ---: | ---: | ---: |
| Original baseline | 102.67 s | 243 | 11.73 ms | 125.31 ms |
| Army/AI implementation | 96.62 s | 265 | 11.91 ms | 129.14 ms |
| Cached terrain templates | 92.64 s | 282 | 12.10 ms | 114.79 ms |
| Final retained updates | 109.29 s | 226 | 15.85 ms | 148.69 ms |

Average profiled batch-building cost fell from 21.58 ms in the army/AI implementation to 10.77–12.89 ms in the two template runs, but full-round performance did not improve consistently. The final sample missed the 240 FPS budget on 38.27% of frames. These single-run differences do not establish a causal regression from the last small changes, nor justify choosing only the fastest run. The honest conclusion is that **capture-time pauses remain unresolved**, despite much faster settled rendering and worker search. More repeated controlled measurements are needed before claiming a whole-turn speedup.

The main thread still compares/publishes large visible snapshots, scans the static scene and reconstructs changed terrain/prop content synchronously. Economy readouts also rebuild a visible model when relevant holdings change. Immediate impact-time finance updates are covered by regression tests and must survive any later scheduling change.

## Remaining work that matters

After submission batching, the next scaling problems are main-thread transactions and whole-position AI simulation. More threads alone will not eliminate the cost of repeatedly copying/rebuilding large positions or synchronously publishing them.

- **Compact indexed simulation state:** packed tile/unit arrays and immutable shared topology would make snapshots and branch copies smaller. Full authoritative kingdom splitting, bridges, encounter secrecy and validated commits must remain correct. This is a larger model refactor than the implemented memoization.
- **Commit and presentation deltas:** apply an explicit changed-coordinate list rather than deep-copying and comparing the full visible board. Narrow HUD/economy rebuilding while preserving immediate income feedback at animation impact; blindly deferring publication would break that timing contract. Terrain colors/joins need their own retained updates. This targets the remaining turn hitches.
- **Hierarchical turn planning:** decide territorial goals once per faction and assign units to those goals, rather than repeatedly searching a global position after every dependency. This is a common useful strategy-game pattern, proposed here rather than a claim about undocumented EU IV/Total War code. It can change AI policy, so compare strength/fairness and decision quality rather than silently reducing depth.
- **Smaller cancellable worker phases:** candidate caches reduced long steps substantially, but a 160 ms worker step can still delay exit. Incremental candidate construction and explicit phase boundaries would improve responsiveness.

For the current map sizes, the measured benefits came from retaining work, grouping drawing and sharing region analysis. A wholesale engine replacement or an immediate C++ rewrite was unnecessary to obtain these gains.

## Verification and reproduction

All **28 existing regression suites passed** across the run and continuation after updating two old tests that explicitly expected prop-driven terrain replacement and individually drawn settled rank pips. The new optimization suite passes **538 checks**, covering original candidate equivalence, authoritative destinations, crowded boards, hostile/friendly bridge garrisons, barriers, retained actors/terrain, upgrades, hover without buffer uploads, moving fallback, disabled batching and persistent reachable geometry. Existing animation, input, events/spells, heatmap, editor, startup and map determinism checks also passed. The added terrain-template suite passes **192 checks** against the original geometry; the runner now contains **29 suites**. Scaling, static batching and animation checks were repeated after the final geometry/retained-update changes.

Use `tools/heavy_strain_probe.gd -- --mode=render|ai|interaction|turn|ablate --label-suffix=final` to retain separate datasets. Turn mode additionally accepts `--difficulty=normal --units=120 --turn-limit=180`. Headless `--mode=cpu` isolates analysis costs. Original and final JSON datasets are under `artifacts/map_stress_heavy_*.json`; `*_optimized` captures the intermediate hover-buffer version, while `*_final` captures the final slot-tint/retention implementation. The rendering matrix was measured before adding effect grouping; its plain-army cases contain no wards or barriers, so that change does not alter those workloads. Native AI/interaction/turn/ablation samples use the final effects implementation.

`*_terrain_templates` and `*_retained_updates` record the subsequent geometry and unchanged-source work. The final complete-round dataset is `artifacts/map_stress_heavy_turn_normal_120_retained_updates.json`. These later suffixes distinguish code stages; the earlier render/search tables should not be presented as a fresh measurement of every final code path.

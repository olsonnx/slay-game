# Map generation and the 240 FPS limit

Measured 14 October 2026, at the requested **1920 × 1080** resolution.

**Implementation follow-up:** the proposed optimizations and zoom-based LOD are now integrated. See [implemented changes and new measurements](C:/Users/Olek1/Documents/slay-game/docs/map-optimization-implementation-2026-10-14.md). The measurements below document the earlier version.

## Finding

**There is no reliable maximum based on tile count alone.** At current graphics quality, the largest individual map that passed the practical frame-time criterion in every tested interactive condition had **330 land tiles**. A 391-tile map narrowly failed, while a different 279-tile map failed more noticeably. Map layout, props, shadows and pointer activity matter.

**Small is the only existing preset that passed all three tested seeds and all tested conditions.** Those six-kingdom Small maps contained **110–114 tiles**. Medium, at 178–184 tiles, and Large, at 231–279 tiles, usually averaged well above 240 FPS but had failing frame-time tails in some conditions. Small is therefore the conservative current recommendation for this PC and these graphics settings, rather than a claim that the engine cannot render more than 114 tiles.

For an enlarged-map feature, approximately **300 actual tiles is a conditional experimental ceiling**, not a safe universal cap. The generator's `min_land` is a minimum, so a “300” profile actually produced 304–391 tiles. It must not be used as an upper-budget setting.

The engine successfully generated **4,000-tile connected maps**. Generation capacity is not the same as the size that maintains 240 FPS. Rendering and interactive picking limit sustained FPS; repeated connectivity checks limit generation speed.

## Test conditions and meaning of “stable”

- Intel Core i5-9300HF, NVIDIA GeForce RTX 2060, approximately 16 GB RAM; NVIDIA driver 572.83.
- Godot 4.6.3, native GL Compatibility rendering; windowed 1920 × 1080, saved **8× MSAA**, Water background, shadows enabled, four directional shadow splits, normal edge softening and production static batching.
- VSync disabled and FPS uncapped. Runtime preferences were not saved. The application's retained menu viewport was confirmed disabled during gameplay.
- Modern rules, six kingdoms, six initial soldiers. These are generated starting boards, not developed endgame armies.
- Real wall-clock intervals between completed rendered frames were recorded, together with rendering CPU/GPU timings, draw counters, node counts and Godot static memory. Headless execution was used only for generation comparisons, never to claim FPS. Godot documents that headless rendering measurements are dummy values. [RenderingServer documentation](https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html).

At 240 FPS, the frame budget is **4.167 ms**. The practical pass criterion here is **p95 ≤ 4.167 ms**: at least 95% of sampled frames fit the budget. The stricter check is **p99 ≤ 4.167 ms**. Both are reported; a high average does not constitute a pass. Neither criterion promises that every individual frame stays within budget.

The initial size sweep sampled two seeds for five seconds per condition. The full-overview threshold tests used three seeds and eight seconds per condition, with one second of warm-up. Preset tests used stationary overview, actual rotation behavior and moving hover. Rendering ablations sampled six seconds; combined batching/hover tests sampled twelve seconds. The final Small endurance run uses thirty seconds per condition.

In total, the native datasets contain **86 samples, 246,829 rendered frame intervals and approximately 11.6 minutes of measured rendering**, excluding warm-ups and generation. The separate generator comparison covers 25 maps.

“Orbit” in the stress datasets changes the camera while leaving picking active. This deliberately tests repeated picking invalidation; it is more demanding than the actual RMB rotation gesture, which suppresses picking. The preset/endurance “rotate” case sets that real rotation flag. “Hover” moves the pointer across the logical game viewport and exercises picking and presentation changes.

The threshold and combined runs scale overview zoom as `64.6 × sqrt(target / 210)` so enlarged maps are viewed as whole islands. The preliminary sweep used a smaller overview envelope; some enlarged-map orientations could crop the outer edges. Its large-map FPS is exploratory, not a certified full-island limit. Large views also interact with the current fixed 75-unit shadow distance; a separate expanded-shadow-range test checks that tradeoff.

These measurements describe this shared desktop session. Clocks, thermal conditions and background work were not laboratory-controlled. Native rendering tests and the CPU-heavy generation comparisons ran sequentially, rather than competing with one another. Repeated baselines expose some variation; an exact universal ceiling would require a wider seed corpus, longer runs and developed gameplay states.

## Current presets

Ranges cover three seeds, 42, 71 and 123, and all three conditions.

| Preset | Actual land tiles | Mean FPS range | Worst p95 | Worst p99 | Assessment |
| --- | ---: | ---: | ---: | ---: | --- |
| Small, six kingdoms | 110–114 | 417–558 | 3.31 ms | 3.96 ms | All short samples pass both checks |
| Medium, six kingdoms | 178–184 | 329–459 | 4.89 ms | 6.36 ms | Fails some rotation/hover tails |
| Large-equivalent profile | 231–279 | 287–432 | 5.16 ms | 6.21 ms | High averages, insufficient reliable headroom |

Large-equivalent uses the same Large bounds, lobe radii, core, minimum land and mountain budget. Its stress camera condition keeps picking active, unlike actual RMB rotation. It also includes moving hover, which independently fails on seed 71.

### Small endurance check

The 114-tile seed-123 Small map was measured for thirty seconds in each condition: ninety seconds total, **46,696 frames**.

| Condition | Mean FPS | p95 | p99 | Frames exceeding 4.167 ms |
| --- | ---: | ---: | ---: | ---: |
| Stationary overview | 565 | 2.32 ms | 2.90 ms | 0.041% |
| Rotation | 559 | 2.36 ms | 2.85 ms | 0.006% |
| Moving hover | 433 | 3.20 ms | 3.71 ms | 0.254% |

All three conditions pass both criteria with useful headroom. Occasional individual frames still reached approximately 13–18 ms, so this is strong percentile stability rather than an every-frame guarantee.

## Enlarged-map boundary

All rows below use full overview, camera motion with picking active, and moving hover, across three seeds.

| Minimum land requested | Actual land produced | Mean FPS range | Worst p95 | Worst p99 | Assessment |
| --- | ---: | ---: | ---: | ---: | --- |
| 210 | 231–279 | 287–432 | 5.16 ms | 6.21 ms | Some seeds fail |
| 300 | 304–391 | 296–393 | 4.19 ms | 5.26 ms | Closest enlarged profile; not uniformly stable |
| 400 | 427–456 | 250–357 | 5.47 ms | 8.91 ms | Clear interactive tail failures |

The 330-tile map, seed 71 of the 300-minimum profile, had p95 **3.73 / 3.70 / 3.94 ms** in overview/camera motion/hover. Its p99 was **4.49 / 4.34 / 4.35 ms**, so it passes the practical criterion but fails the stricter one. The largest map passing both criteria across those three conditions in the threshold set was the 231-tile seed-42 map; this is an observed passing example, not a guarantee for every 231-tile layout.

At the other end, the exploratory sweep produced connected 500-, 1,000-, 2,000- and 4,000-tile boards. Their mean FPS ranges across seeds/camera conditions were approximately **199–355, 129–226, 57–102 and 79–136**, respectively. The non-monotonic 2,000/4,000 results are another reason not to extrapolate a tile-to-FPS formula: camera framing, shadow coverage, layout and test conditions differ. Neither size approached the target, even in that less conservative view.

At 4,000 tiles, the complete application retained approximately **37,000 nodes** and reported **331–345 MB of Godot static memory**. This is not total process RAM or GPU memory. The production renderer batches opaque source meshes, but those source nodes remain present.

## How the current generator works

The authoritative implementation is [map_generator.gd](C:/Users/Olek1/Documents/slay-game/src/game/map_generator.gd), with profiles in [map_sizes.gd](C:/Users/Olek1/Documents/slay-game/src/game/map_sizes.gd).

1. Enumerate potential capital sites, shuffle them, and greedily pack capitals at least five hex steps apart. Retry up to 128 times, then use fallback sites. Each starting home reserves a full seven-hex ring.
2. Connect capitals with a randomized spanning-tree-like set of paths, optionally add an extra link, then grow random hexagonal lobes and offset neutral bulges.
3. Flood-fill from the mainland and discard detached specks. If land is below the minimum, repeatedly scan the whole island to form an outward frontier and add tiles.
4. Erode bays/lakes. Each proposed removal temporarily deletes a tile and flood-fills the remaining island to verify connectivity.
5. Expand ownership for six rounds per faction. Each round scans neutral land, checks neighbors and scores candidates. Add neutral trees and starting soldiers; rebuild kingdoms.
6. Assign province values, equal starting value budgets and spaced mana sources. Compute coast depth, then place coastal mountain clusters; each candidate mountain triggers another full passable-land connectivity scan. Finally set mana and generate encounters.

Let **N** be land tiles and **F** factions. Ordinary flood fills and resource passes are approximately O(N). The randomized capital linking is roughly O(F³), but F is only six here. Starting ownership has six rounds of O(F × N) candidate scans, with dictionary/neighbor-allocation overhead. Erosion can attempt O(N) removals, each costing O(N), giving a quadratic worst case. Mountain placement costs approximately O(M × N), where M is the number of candidate placements; scaling mountain density with map area makes that quadratic too. Minimum-land filling rescans N tiles per growth layer.

The shipped starting-site scan is hardcoded to **q = −20…20, r = −12…12**. Enlarging only the profile bounds does not expand capital placement to the full new island. The benchmark copies derive these ranges from bounds, preserving the original packing method. They scale bounds/radii/core and mountain count with target area, retain six factions and seven starting provinces, and preserve the remaining algorithm. These are diagnostic larger-map profiles, not newly balanced playable presets.

An additional scalability guard is needed before exposing arbitrary sizes: if minimum land exceeds usable bounds and the frontier becomes empty, the current minimum-land loop has no escape. Custom profiles should validate capacity and stop with a bounded failure rather than loop forever. This condition was not triggered by the tested profiles.

## Generation timings and a validated optimization

In the native preliminary sweep, 4,000-tile generation took **8.77–16.12 seconds**. Mountain checks alone took **7.98–14.23 seconds**, about **88–91%** of the total. Ownership/tree setup was the next major cost. Scene replacement then took approximately **2.75–3.11 seconds**. Those scene measurements replace an existing board and benefit from warmed resource caches; they are not cold application-startup timings. The existing normal startup already generates rules on a worker and builds visuals incrementally.

I tested an isolated alternative for both erosion and mountain placement: after removing a vertex from an already connected graph, it is enough to establish that its surviving neighbors are connected to one another. Flood-fill from one neighbor and **stop as soon as every other neighbor has been reached**, rather than scanning the entire island. Mountain checks apply this to passable neighbors only.

This is an exact connectivity criterion under the generator's connected-input invariant, not an approximate local-radius test. It can still visit the whole island in difficult cases and does not remove the worst-case bound, but most accepted coastal removals can finish much earlier. It consumes no additional randomness.

Five seeds per size—42, 71, 123, 7 and 999—were compared headlessly, sequentially on the same PC:

| Minimum land | Actual tile range | Original median generation | Prototype median | Speedup |
| --- | ---: | ---: | ---: | ---: |
| 210 | 231–287 | 91.86 ms | 44.27 ms | 2.07× |
| 500 | 500–522 | 231.90 ms | 101.31 ms | 2.29× |
| 1,000 | 1,000–1,022 | 659.57 ms | 214.37 ms | 3.08× |
| 2,000 | 2,000 | 2,322.33 ms | 532.69 ms | 4.36× |
| 4,000 | 4,000 | 8,613.07 ms | 1,092.67 ms | 7.88× |

**All 25 comparisons passed:** identical cell dictionaries, kingdom dictionaries and final RNG state; connected mainland, connected passable land, six kingdoms and seven starting provinces per kingdom. These are medians of each implementation, not a claim that every seed has precisely the displayed speedup.

The prototype lives only in generated benchmark copies under `artifacts/map_stress_source`. It has not changed production generation. It improves loading time; because generation is not ongoing during an idle match, it does not itself increase steady FPS.

## What limits rendering and interaction

The measured workload is predominantly CPU/driver-bound. On the 500-tile baseline, median renderer CPU time was approximately **2.27 ms**, versus **0.86 ms GPU time**. Disabling stationary gameplay/view scripts changed mean FPS only from **354 to 357**. Active pointer movement reduced it to **261**, indicating substantial work outside the stationary render path.

[board_picker.gd](C:/Users/Olek1/Documents/slay-game/src/rendering/board_picker.gd) scans every cell for tall props and every soldier when a pick must be recalculated. Stationary picks are cached, but moving the pointer or camera invalidates the cache. This is O(N + units) per changed pick; it becomes especially costly at a 4.167 ms frame budget.

Opaque meshes already use spatial MultiMeshes. Larger chunks can reduce draw submissions, at the cost of drawing more offscreen instances when a chunk intersects the view. Godot documents that MultiMesh visibility is all-or-none per batch rather than per individual instance. [MultiMesh documentation](https://docs.godotengine.org/en/4.6/tutorials/performance/using_multimesh.html).

Runtime-only experiments on the same 500-tile seed-71 map:

| Stationary condition | Mean FPS | p95 | p99 | Reported draw calls |
| --- | ---: | ---: | ---: | ---: |
| Current 12-hex chunks, initial baseline | 354 | 3.38 ms | 4.03 ms | 1,007 |
| Gameplay/view processing disabled | 357 | 3.45 ms | 3.87 ms | 1,007 |
| Shadows disabled | 469 | 2.97 ms | 3.60 ms | 368 |
| One directional shadow projection | 402 | 3.39 ms | 3.90 ms | 647 |
| 24-hex chunks | 420 | 2.92 ms | 3.25 ms | 559 |
| 48-hex chunks | 438 | 2.84 ms | 3.18 ms | 484 |
| Current baseline repeated at the end | 327 | 3.78 ms | 4.36 ms | 1,007 |

The repeated baseline changed by about 8%; treat short ablation gains as directional rather than precise universal percentages. Shadow draw counters separately reported zero in Compatibility while shadow primitive counters and total draw counts changed, so the table deliberately uses the available combined draw counter rather than claiming an accurate split by pass.

The closer view ran at **495 FPS**, p95 **2.68 ms**, illustrating the benefit of culling. Keeping picking active during camera motion gave **267 FPS**, p95 **4.66 ms**; suppressing picking gave **337 FPS**, p95 **3.84 ms**. The paths traverse different numbers of orientations in these frame-stepped samples, so this is supporting evidence, not a clean fixed-angle subtraction.

The fixed shadow distance was also expanded from 75 to about 199 units on the 500-tile overview. That sample measured **328 FPS**, p95 **3.78 ms**, p99 **5.08 ms**. Enlarging the island/camera therefore needs an explicit shadow-quality policy; allowing distant shadows to disappear must not be counted as a free optimization preserving the same image.

### Larger batches under actual pointer activity

Twelve-second follow-up samples preserve current shadow/MSAA settings:

| Actual tiles | Moving hover configuration | Mean FPS | p95 | p99 |
| --- | --- | ---: | ---: | ---: |
| 500 | Current 12-hex chunks | 254 | 4.83 ms | 5.60 ms |
| 500 | 24-hex chunks | 311 | 3.92 ms | 4.28 ms |
| 500 | 48-hex chunks | 322 | 3.79 ms | 4.18 ms |
| 1,000 | Current 12-hex chunks | 174 | 7.31 ms | 8.10 ms |
| 1,000 | 24-hex chunks | 212 | 5.75 ms | 6.46 ms |
| 1,000 | 48-hex chunks | 230 | 5.31 ms | 5.73 ms |

This supports **500 tiles as a promising optimization target**, because larger chunks brought that single hover sample within the practical criterion. It does not establish a robust optimized 500-tile maximum across seeds, views and gameplay, and it still misses the stricter p99 criterion. Larger chunks alone do not make 1,000 tiles viable at 240 FPS.

## Recommended work, in priority order

1. **Integrate the exact early-exit connectivity check with broader regression coverage.** It has the strongest measured generation gain and preserved every tested map/RNG state. Retain the full connectivity routines for final validation and disconnected-input cases.
2. **Add a spatial broad phase to picking.** Query conservative ray/height bounds against nearby prop and soldier bins instead of scanning the entire map. Keep the existing precise hit tests. Bounds must account for tall objects and shallow camera angles; blindly restricting checks to one tile would introduce picking errors.
3. **Trial 24-hex render chunks or an adaptive chunk policy.** It substantially reduced submissions and improved 500-tile hover tails. Verify close-camera culling, movement, dirty updates, borders and all shadow views before changing defaults. Forty-eight-hex chunks were slightly faster in this overview, but are more likely to overdraw in close views.
4. **For substantially larger maps, move to directly generated terrain chunks and a smaller retained scene graph.** Merge raised top surfaces and exposed cliffs per chunk; omit buried/internal faces. Keep units, buildings and animation/selection objects separately addressable. Do not recreate all per-tile grass nodes merely to hide them behind batches. This is architectural work, not a small flag change.
5. **Keep shadow quality explicit.** Consider simplified shadow casters, fewer projections or distance-dependent prop shadows as quality options. The experiments show benefit, but removing shadows changes the picture; compare low-angle terrain/bridge/building silhouettes before adopting a preset.
6. **Optimize remaining generation scans after the connectivity change.** Cache generation-only adjacency or use indexed arrays/visited stamps; maintain the minimum-land frontier incrementally; iterate actual axial lobe rows instead of the rejected corners of a square. Ownership growth is then a major remaining cost. A frontier-based ownership rewrite can preserve fairness but may change RNG consumption and old seeded maps, so version it or explicitly preserve the existing random sequence.
7. **Before shipping a larger preset, enforce actual output budgets.** Add dynamic capital bounds, capacity/empty-frontier guards and a true upper tile/prop budget. Benchmark a wider seed set and developed matches, including AI snapshot/commit work, recruitment, captures, heatmap toggles and batch rebuilds. Those operations still include whole-board copies/scans, and are not certified by idle FPS.

For now, retain Small for the strongest demonstrated 240 FPS headroom at 1080p/8× MSAA on this machine. Treat roughly 300 tiles as a conditional current-quality experiment, and 500 tiles as the next measured optimization target. Do not offer 1,000+ tiles with a 240 FPS promise based on these results.

## Reproduction and evidence

No production gameplay, generation profiles or rendering defaults were changed. Added diagnostic scripts and generated, disposable source copies with phase timers and expanded stress bounds. Original generator/profile/batching SHA-256 hashes are recorded in `artifacts/map_stress_source/source_hashes.json`.

Prepare copies, then run one native rendering process at a time:

```powershell
./tools/prepare_map_stress.ps1
& $Godot --path . --script tools/map_stress_probe.gd -- --sizes=210,300,400 --seeds=42,71,123 --cases=wide,orbit,hover --duration=8 --label=threshold
& $Godot --path . --script tools/map_stress_probe.gd -- --sizes=small,medium --seeds=42,71,123 --cases=wide,rotate,hover --duration=8 --label=presets
& $Godot --path . --script tools/map_stress_probe.gd -- --sizes=500,1000 --seeds=71 --cases=hover,chunk24_hover,chunk48_hover --duration=12 --label=combined
& $Godot --path . --script tools/map_stress_probe.gd -- --sizes=small --seeds=123 --cases=wide,rotate,hover --duration=30 --label=endurance
& $Godot --headless --path . --script tools/map_generation_stress.gd
python tools/summarize_map_stress.py
```

`$Godot` is the Godot 4.6.3 console executable. Native probes intentionally refuse headless FPS runs. The benchmark keeps the saved antialiasing choice and forces unsaved 1080p/VSync-off settings; recheck recorded configuration when reproducing on another machine.

Raw native datasets contain every sampled frame interval: `artifacts/map_stress_sweep.json`, `map_stress_threshold.json`, `map_stress_presets.json`, `map_stress_ablations.json`, `map_stress_combined.json`, and `map_stress_endurance.json`. Generation data is in `artifacts/map_generation_stress.json`; hardware in `artifacts/map_stress_hardware.json`; flattened measurements in `artifacts/map_stress_summary.csv`. Matching `.log` files record execution and diagnostics.

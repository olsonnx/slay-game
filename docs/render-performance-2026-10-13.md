# Large-map rendering investigation — 13 October 2026

**Implementation is now complete:** see [static rendering batches](static-batching-2026-10-13.md) for the integrated renderer, validation and same-scene measurements. The following investigation describes the earlier runtime prototypes; its statement that production was unchanged applies to that investigation stage only.

The main bottleneck is the number of separately submitted small meshes, multiplied by directional shadow passes. It is primarily CPU/driver rendering overhead, with additional GPU shadow cost. Zooming in culls most of those instances. Zooming out submits nearly the whole island, even though its triangles cover fewer pixels.

No production rendering or gameplay behavior was changed. Added a repeatable native probe with disposable runtime batching/shadow experiments. Preferences are never saved by the probe. This investigation proposes integration work; the temporary batching is not ready for live gameplay.

## Method and evidence

Godot 4.6.3, GL Compatibility, NVIDIA RTX 2060, windowed 1280×820, unlocked FPS, VSync off, Modern/Large/six kingdoms. The initial broad ablation used 4× MSAA; focused tests repeated with the user's saved **8× MSAA**. Two seeds: 42 (231 tiles, 1,346 mesh instances) and 71 (279 tiles, 1,637 mesh instances). Six kingdoms do not guarantee the same land count. Map variation contributes to the reported lows.

Used the actual application and Quick Play startup, including its retained hidden menu. Verified the menu viewport is `UPDATE_DISABLED` during gameplay. Wide zoom is the actual maximum, **64.6**; close zoom is 11 centered on the player's capital. No turn processing during these measurements. Each condition warms for 0.65 seconds, then samples real `frame_post_draw` wall intervals for 1.5 seconds. Two passes in opposite orders reduce order bias; focused runs include repeated baseline samples. These are short controlled samples, not long gameplay or worst-case guarantees. GPU clocks/background workload can still vary.

| Condition at wide zoom | Seed 42: mean FPS range | Seed 71: mean FPS range | Reported 3D draws, seed 42 / 71 |
| --- | ---: | ---: | ---: |
| Current game | 192–200 | 154–171 | 4,201 / 5,357 |
| Grass/pebble batching only | 290–291 | 218–245 | 2,438 / 3,132 |
| One directional shadow projection | 233–244 | 199–205 | 2,680 / 3,245 |
| All compatible opaque pieces batched, colors retained | 575–586 | 538–556 | 232 / 247 |
| Same batching plus one shadow projection | 642–649 | 578–617 | 148 / 165 |
| Current game at close zoom | 409–411 | 421–488 | 1,055 / 465 |

The full batching prototype uses 33 MultiMesh groups on either map and preserves visible triangle counts and individual part colors. It includes terrain sides/caps, grass and repeated opaque prop parts; transparent blob shadows and soldiers retain their existing rendering. Same-mesh, same-material-only batching was much less effective (247–269 FPS on seed 42): many color variations split materials. Moving color variation into instance colors is essential.

Seed 42 current wide: median wall frame **4.94 ms**, renderer CPU **4.43 ms**, GPU **1.89 ms**. Batched wide: **1.60 / 1.20 / 0.62 ms** respectively. Seed 71 current wide: **6.03 / 5.45 / 3.23 ms**; batched: **1.68 / 1.27 / 0.65 ms**. CPU/GPU work overlaps; these times must not be added together. Seed 71's current p99 wall interval averaged **9.03 ms** (about 111 FPS reciprocal), versus **3.22 ms** batched. This reproduces both the large zoom gap and slower-map lows.

**Counter caveats:** in this Compatibility run, `VIEWPORT_RENDER_INFO_TYPE_VISIBLE` draw counts include shadow submissions: disabling shadows reduces 4,202 to 1,368 while visible triangle counts remain unchanged. The separate shadow draw/object counters report zero even while shadow primitives are nonzero. Therefore the table labels these as reported total 3D draw counts, not literal visible-pass-only counts. `Performance.TIME_PROCESS` is polluted by the probe's coroutine/setup work and not used for conclusions. Renderer timings come from `RenderingServer` and frame pacing from actual wall intervals.

## Causes in the source

1. `BoardAssets.piece` creates a separate `MeshInstance3D` for every box/cylinder. `grass_details` alone creates three box meshes and sometimes a pebble per clear tile. Trees, mountains, buildings and crystals add many more pieces. Geometry/material caching avoids allocations but does not merge their draw submissions.
2. `BoardAssets.material` caches by the exact color. Per-tile tint variation consequently creates separate materials. Explicit instancing with per-instance colors groups these without flattening faction colors or deleting decoration.
3. Gameplay leaves `DirectionalLight3D.directional_shadow_mode` at its default **four splits**. The menu's `DecorativeMap` already selects one orthogonal shadow projection. Extra shadow submissions magnify the mesh count. Tiny grass blades/crystals also cast real shadows despite their low screen size at wide zoom.
4. `Game._process` calls `show_world_tip` every frame after the hover delay. That rebuilds tooltip content and measures text/layout repeatedly for unchanged hover. Focused hover samples were ~186–191 vs ~192–200 FPS on seed 42, and ~153 on seed 71. This is secondary, not the cause of the baseline zoom gap.

## Other suspects tested

Broad seed-42 tests (4× MSAA, two passes):

| Runtime ablation | Mean FPS across the two passes |
| --- | ---: |
| Current wide | 196 |
| Gameplay/board `_process` callbacks disabled | 201 |
| Water hidden | 196 |
| Screen-edge blur hidden | 196 |
| MSAA off | 194 |
| Shadows off | 280 |
| Grass/pebbles hidden | 280 |
| All tile props hidden | 364 |
| World hidden, UI/background retained | 838 |

Shrinking the window to 960×620 did not improve FPS; 1920×1080 remained about 185 FPS. Water, blur and MSAA are not the first targets in this CPU-bound scene. Sky did not help; its GPU time was higher. The menu viewport was confirmed inactive. The fresh-map movement indicator adds only a handful of meshes; selection cost exists, but the heavy baseline is present without any selected unit or arrow. Rules/AI changes would not address this idle rendering drop.

## Recommended implementation order

**1. Batch repeated opaque rendering with per-instance colors, using spatial chunks.** Start with grass/pebbles and terrain, then repeated opaque prop parts. Keep logical tile nodes and authoritative picking separate from the batched render instances. Group by mesh, actual material features and shadow role; preserve original transforms, color, lighting and double-sided roofs. Avoid one whole-map batch as the final architecture: the prototype draws extra offscreen/shadow triangles because each MultiMesh is culled as one object. Spatial chunks retain close-zoom culling. Even the unchunked prototype improved close zoom (593–677 FPS across the two maps), but chunking is the safer production design.

Update only dirty chunk/instance data on capture, terrain join changes, trees/graves/buildings and preference changes. Keep moving units and tile entry/exit transitions on their existing animation paths initially, then switch back to batched static rendering after completion. Explicitly support heatmap tint/hiding/restoration and bridge demolition, so batching cannot resurrect removed props or miss newly built ones. Use the same helpers for menu tiles, including recycled tiles, to preserve shared appearance.

**2. Evaluate one orthogonal shadow projection after batching.** This is a smaller additional gain once submissions are reduced (~10–15% in these samples). Preserve a quality option if close-zoom sharpness suffers; test shallow angles, transitions, water/sky, map edges and shadow stability. Separately consider disabling real shadow casting for tiny grass/pebbles while retaining larger props and terrain. Do not remove all shadows by default just to raise FPS.

**3. Cache stationary tooltip content/layout.** Rebuild it when hovered tile, visible state, value mode or bindings change; update position separately. This is an inexpensive secondary cleanup and needs stale-content tests during playback/changes.

**4. Optional distant detail reduction, only if needed afterward.** Fade tiny grass/pebbles when subpixel at wide zoom. This changes presentation; batching already removes most of the measured waste while retaining the geometry, so detail removal is not the first recommendation. No renderer migration or major shader rewrite is justified by these results.

The wide-view baseline/batched screenshots were visually compared. Main terrain colors, raised geometry, props and units were retained; the single-shadow version changes shadow rendering. These experiments do not verify full gameplay lifecycle behavior or promise production FPS.

## Reproduce

Run the console executable **without `--headless`**:

```text
Godot_console --path . --script tools/render_performance_probe.gd -- --label=large6
Godot_console --path . --script tools/render_performance_probe.gd -- --focused --native-msaa --label=large6_native --capture
Godot_console --path . --script tools/render_performance_probe.gd -- --focused --native-msaa --seed=71 --label=large6_seed71
```

Raw results: `artifacts/render_performance_large6.json`, `render_performance_large6_native.json`, `render_performance_large6_seed71.json`. Screenshots: `render_large6_native_wide.png`, `render_large6_native_color_batches.png`, `render_large6_native_batches_one_shadow.png`.

Official references: [MultiMesh batching and its culling tradeoff](https://docs.godotengine.org/en/4.6/tutorials/performance/using_multimesh.html), [directional shadow modes](https://docs.godotengine.org/en/4.6/classes/class_directionallight3d.html), [RenderingServer timing and counters](https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html).

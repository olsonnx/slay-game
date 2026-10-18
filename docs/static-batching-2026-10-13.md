# Static rendering batches — 13 October 2026

The later [main-menu optimization](menu-performance-2026-10-13.md) supersedes this document's initial per-row menu batching and streaming-cost discussion. Gameplay's chunked renderer remains active; the shared helper now also supports opt-in cached/incremental menu records and notification suppression.

The approved rendering optimization is implemented. Opaque terrain and repeated static prop pieces now render in spatial MultiMesh batches with individual colors. Source scene nodes, meshes and materials remain intact for picking, inspection, heatmap restoration and lifecycle code. Shadows retain the existing gameplay quality; the single-shadow projection remains an experiment rather than a changed default.

## Measured result

RTX 2060, Godot 4.6.3 Compatibility, Modern/Large/six kingdoms, 1280×820, saved **8× MSAA**, unlocked FPS. The same runtime scene alternates between the source renderer and the integrated renderer, with warmup and two sample orders. Source-renderer fallback only disables batching; all other settings stay the same. The original investigation and earlier unchunked prototype remain historical evidence in `render-performance-2026-10-13.md`.

| Map / view | Source renderer FPS | Integrated FPS | Reported 3D draws before → after |
| --- | ---: | ---: | ---: |
| Seed 42, 231 tiles, wide | 214–217 | **427–436** | **4,201 → 713** |
| Seed 71, 279 tiles, wide | 184–185 | **404–429** | **5,357 → 751** |
| Seed 42, close | 428–455 | 519–617 | 1,055 → 202 |
| Seed 71, close | 557–566 | 645–648 | 465 → 89 |

Seed 42 median wide frame time: **4.51 → 2.24 ms**; p99 wall interval **6.22 → 3.38 ms**. Seed 71: **5.28 → 2.29 ms** median, **6.52 → 3.50 ms** p99. Rendering CPU approximately halves; visible geometry is preserved. These are short controlled samples, not guaranteed FPS through every match/animation.

The integrated renderer uses 12-hex axial chunks. Eight-hex chunks were also tested, but had more draw submissions and lower wide-view FPS. Compared with the unchunked prototype, production keeps smaller culling bounds, full source-node behavior and animation fallback. Extra offscreen triangles within each chunk are still drawn, but both close views improved in the A/B tests. Reported Compatibility draw counts include shadow submissions, as documented in the investigation. CPU/GPU timings overlap; `Performance.TIME_PROCESS` from the coroutine probe is not used as script-time evidence.

Raw final map measurements: `artifacts/render_performance_production12.json` and `render_performance_production12_seed71.json`. The compact material-key cleanup afterward changes bookkeeping only; batch grouping and geometry are unchanged. Screenshot: `artifacts/render_production12_wide.png`.

## Rendering responsibilities

`src/rendering/static_batches.gd` owns opaque instancing. It groups by mesh, original render layers, shadow-casting role and the complete immutable material state apart from color/instance-color enablement. A compact canonical feature ID keeps per-instance keys small. Copied batch materials are white and use instance colors; source materials are never edited. Only supported single-surface, texture-free opaque StandardMaterial pieces are eligible. Transparent shadows, sprites, multi-material reliefs and unsupported materials retain their original rendering.

Source render layers are suppressed while batched, rather than changing `visible`. This preserves existing scene visibility semantics and heatmap tracking. Unit actors carry an explicit role and are excluded with their rank markers; wards remain on their existing temporary rendering path. Batch/source correspondence is retained so hidden/removed sources cannot leave ghost instances. Material references no longer used by a source scan are pruned.

`BoardView.refresh_static_batches` runs after visible board changes and value-filter changes, plus live terrain-join preference changes. Source signatures include identity, mesh/material features, transform and color. Unchanged chunks keep their MultiMeshes; only affected chunk geometry is rebuilt. This does not walk/rebuild the static island every idle frame. Captures, structures, trees/graves, bridge removal, wards and rollback retain their existing source synchronization and batch updates follow that visible state.

`BoardTransition` suspends batches and restores source layers for tile arrival/departure, so existing tile tweens continue to move the entire tile and props. Completion/cancellation restores the static path at the correct home positions. Leaving a level keeps batches suspended until disposal/reset. Moving soldiers always retain their own actor path.

`DecorativeMap` uses the same helper for settled tiles in each scrolling row. The row parent moves the whole batch with the scenery. Only membership changes, recycled rows and geometry preference changes rebuild row batches; falling/arriving tiles use the source path. Source asset generation stays shared between menu and gameplay. Menu regression covers 150 simulated seconds, recycling, borders and background preferences. Membership-update CPU work is higher than the previous unbatched scheduler (about 4.9–5.2 seconds for the 150-second simulation versus the historical ~1.2 seconds); this is event work rather than an idle full-world scan. Native menu A/B samples showed a modest mean-FPS gain and fewer draws, with variable tail pacing. Menu streaming rebuilds remain a future profiling target; no large menu-FPS claim is made.

`GamePresenter` caches stationary tooltip content by hovered cell, value mode and a presentation revision. UI refreshes, visible board changes and key changes invalidate it; direct changes to the hovered cell also change the signature. Pointer position is updated separately. This avoids repeating defense/economy reads and content construction for unchanged hover.

## Verification

- All **23 existing suites** passed in the full run, including AI **178**, game **114,641**, animation **40**, input **42**, Modern **10,520**, presentation **5,080**, expansion **409**, map sizes **33,116**, performance **284**, scrolling menu ~**4,322**, heatmap **38** and indicators **337** checks. Menu counts vary with the random streamed fixture.
- New `test_static_batches.gd`: **1,311 checks passed** headless and again with the native graphics renderer. Covers one render instance per suppressed source, unchanged-chunk retention, one-chunk changes, color preservation, actor exclusion, filter hide/restore, source fallback, transitions/cancellation, tooltip invalidation and hidden-subtree removal/restoration.
- After compact-key cleanup, final affected reruns passed: static batching **1,311**, heatmap **38**, input **42**, performance **284**, menu **4,321**, presentation **5,080**. The runner now contains **24 suites**.
- Native visual previews inspected for normal/movement, Sky/top-down heatmap, wooden bridges and wards, tower/house/grave/tree fixtures, intermediate tile arrival and evolving Water menu scenery. The original gameplay shadows and procedural asset silhouettes are retained.

## Reproduce

```text
Godot_console --path . --script tools/render_performance_probe.gd -- --production --native-msaa --label=production12 --capture
Godot_console --path . --script tools/render_performance_probe.gd -- --production --native-msaa --seed=71 --label=production12_seed71
Godot_console --headless --path . --script tests/test_static_batches.gd
```

The probes do not save preferences. Production mode measures the integrated renderer and its source-renderer fallback in the same application. Legacy experiment mode disables integrated batching first to avoid measuring two overlapping batching systems. `tools/menu_batch_probe.gd` separately compares streamed menu paths.

Future work should profile command-time chunk scans/rebuilds and streamed-menu membership tails before adding further complexity. Do not change shadow quality or remove distant detail merely to match the unchunked prototype's peak FPS; those are separate visual tradeoffs.

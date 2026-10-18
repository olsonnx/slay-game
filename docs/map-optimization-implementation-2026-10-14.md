# Map optimization implementation and LOD

Implemented 14 October 2026. Follow-up to the [generation stress report](C:/Users/Olek1/Documents/slay-game/docs/map-generation-stress-report-2026-10-14.md).

The [16 October generation v7](world-generation.md) intentionally changes map
layouts and supersedes the original-seed compatibility baseline described below.
Connectivity shortcuts, adjacency caching and incremental frontier growth remain.

## What changed

**Generation:** erosion and mountain placement now stop connectivity checks as soon as all surviving neighbors are connected. Generation caches adjacency after topology settles, builds lobes over actual hex rows, and maintains the minimum-land frontier incrementally. Frontier priorities and ownership random draws preserve the original seed sequence. Starting-site search bounds are derived from map dimensions, and an empty frontier now stops with a diagnostic rather than looping forever.

Ownership setup uses the six guaranteed home neighbors instead of repeatedly checking adjacency across every neutral tile. The full neighbor ring is reserved before erosion and protected from removal, so the six starting claims can be made without changing the result. All original random draws are still consumed.

**Picking and hover:** a conservative ray footprint queries nearby terrain/prop cells and soldier actors, retaining the original hit tests and opaque-pixel priority. Its bounds expand at shallow angles. Moving actors still use the live sprite fallback. Hover highlighting caches kingdom membership and board order instead of rescanning every neutral province on pointer movement.

**Terrain:** gameplay uses 24-hex spatial chunks. Settled soil and colored surfaces share a merged mesh with vertex colors. It omits buried bottoms, covered earth tops, walls between neighboring land tiles, and flush joined cap walls. Exposed cliffs and soil rims remain. Color, kingdom-border and neighboring-tile changes rebuild affected geometry, including chunk boundaries. Full source tiles remain available for arrival/departure animation, cancellation and rendering fallback. The menu retains its established animated terrain path.

**Grass:** three individual blades now share one procedural mesh. Grass and its associated pebble hide above camera zoom **36** and return at **32 or below**. The separate thresholds prevent repeated switching around the boundary. Grass batches stay resident and become invisible, stopping their draw/vertex work without reallocating them on zoom. Newly created tiles honor the current LOD. Trees, buildings, mountains, soldiers, crystals and gameplay markers remain visible.

**Shadows:** tiny grass/pebbles no longer cast realtime shadows. Close views use two directional projections; wider views use one projection. Shadow caster cutoffs rise from **0.35 to 0.8 to 1.4 world units** of mesh bounding-box diagonal across close/medium/distant bands. This principally removes small prop pieces and upper tree sections from distant shadow passes, while keeping their visible geometry. Shadow distance expands with camera zoom instead of silently losing coverage on larger islands. The saved Shadows option still controls whether shadows are enabled.

The near/medium shadow threshold has hysteresis around zoom 24–28, and the far band around zoom 50–56. Terrain remains fully visible at every LOD; this is not a flat-map substitute.

### Rapid-zoom correction

The initial LOD implementation invalidated source caches and rebuilt entire chunks when grass or shadow bands changed. Repeatedly zooming across those boundaries caused **145 synchronizations and 580 chunk rebuilds in 12 seconds** on a 279-tile map. This regenerated merged terrain even though its geometry had not changed.

LOD now toggles visibility on retained grass batches and changes shadow casting flags on existing renderers. Detail groups have stable batch keys; shadow thresholds no longer alter grouping. Zoom causes **zero batch synchronizations, zero chunk rebuilds and no terrain mesh replacement**. Source-layer restoration preserves the same grass visibility when batching is disabled or tiles are animated.

At 1080p/8× MSAA, repeating zoom between 20 and 64 twice per second gave:

| Map / version | Mean FPS | p95 frame | p99 frame | LOD chunk rebuilds |
| --- | ---: | ---: | ---: | ---: |
| 279 tiles, before | 215 | 41.63 ms | 53.38 ms | 580 |
| 279 tiles, corrected | 483 | 2.78 ms | 3.15 ms | 0 |
| 1,000 tiles, corrected | 464 | 2.77 ms | 3.64 ms | 0 |

The original worst interval was 127 ms; the corrected Large trace still had an occasional 17 ms outlier, but the systematic LOD stalls disappeared. These are twelve-second native traces on the same shared desktop, rather than an every-frame guarantee. Raw evidence: [before](C:/Users/Olek1/Documents/slay-game/artifacts/map_stress_zoom_before.json), [after](C:/Users/Olek1/Documents/slay-game/artifacts/map_stress_zoom_after.json).

Regression checks now include 500 immediate zoom changes, unchanged terrain resource identities, visibility restoration, heatmap toggles, disabled batching and animated-source fallback. Scaling **2,038**, static batching **1,118**, heatmap **38**, animation **41**, startup **5**, expansion **409**, and menu rendering **41,882** checks passed for this correction.

**Smooth fade follow-up:** grass and pebbles now fade over 0.22 seconds instead of changing opacity instantly. Reversing zoom continues from the current opacity. Cached alpha materials on the existing batches provide intermediate opacity without changing instance buffers, geometry or batch keys. Only rendered batch materials update each frame during a normal fade; source materials update for animation/disabled-batching fallback. The fade updater stops once opacity reaches its target. Native full/half/zero-opacity previews were checked.

The final 1,000-tile repeated-zoom sample averaged **452 FPS**, with p95 **2.85 ms**, p99 **3.95 ms**, and **zero synchronizations or chunk rebuilds**. [Fade measurement](C:/Users/Olek1/Documents/slay-game/artifacts/map_stress_zoom_fade_final.json). The same regression suite now also checks intermediate opacity, reversal without jumping and fallback material opacity.

## Measured results

Same PC as the original report: i5-9300HF, RTX 2060, Godot 4.6.3 Compatibility, **1920 × 1080, 8× MSAA, Water**, VSync off, uncapped FPS. New measurements use the actual production LOD/shadow policy. Performance gains include the intentional reduction in grass and shadow detail; they are not a comparison with identical distant graphics settings.

Twenty-four eight-second samples cover overview, real rotation and moving hover, with two seeds at each size. After removing the remaining full-map hover scan, eight twelve-second hover samples repeated those sizes on the final code. Warm-up is excluded.

### Final moving-hover results

| Actual land tiles | Mean FPS, two seeds | Worst p95 | Worst p99 | 240 FPS assessment |
| --- | ---: | ---: | ---: | --- |
| Large: 231–279 | 513–583 | 2.64 ms | 2.91 ms | Passes both percentile checks |
| 500 | 511–526 | 2.67 ms | 2.95 ms | Passes both |
| 1,000 | 428–436 | 3.19 ms | 4.01 ms | Passes both in these samples |
| 2,000 | 325–340 | 4.04 ms | 4.89 ms | Passes p95; one seed misses p99 |

The 240 FPS budget is **4.167 ms**. The preceding overview/rotation samples also passed p95 at every size. Their worst p99 was approximately **3.43 ms at 1,000 tiles** and **4.65 ms at 2,000 tiles**.

On the same 500-tile seed-71 hover workload, the original renderer measured approximately **254 FPS, p95 4.83 ms**. Final code measured **511 FPS, p95 2.67 ms**. Reported draw calls fell from **1,007 to approximately 220**, including the new shadow/grass quality policy.

**1,000 tiles is now a credible tested 240 FPS target on this hardware**, rather than the previous roughly 300-tile conditional boundary. Two thousand tiles is promising but lacks the same tail headroom. These are initial boards and short controlled samples across two seeds; they do not certify dense endgame armies, every seed or every individual frame. The four original map presets retain their seeded maps. Very Large (~500 tiles) and Huge (~1,000 tiles) now extend the playable size ladder, using the measured larger-map profiles. Both Quick Play and the level editor show approximate tile counts in their dropdowns and explain seed variation in tooltips. Map-size checks cover both new presets, deterministic generation, connected routes, balanced starts, independent kingdom counts, scaled cameras and restart; editor checks include saving more than 1,000 tiles.

### Generation, original versus implemented

Five seeds per size, sequential headless comparisons. Medians:

| Minimum land | Original | Implemented | Speedup |
| --- | ---: | ---: | ---: |
| 210 | 88.95 ms | 22.37 ms | 4.0× |
| 500 | 226.68 ms | 42.04 ms | 5.4× |
| 1,000 | 751.79 ms | 93.48 ms | 8.0× |
| 2,000 | 2,359.22 ms | 227.25 ms | 10.4× |
| 4,000 | 8,622.51 ms | 455.34 ms | 18.9× |

All 25 larger-map comparisons produced identical cells, kingdoms and final RNG state, with connected land/passable land and six seven-province starting kingdoms. The improved frontier and ownership setup account for additional gains beyond the original connectivity-only prototype.

Generation is a loading cost. The FPS gains come from picking, hover, merged terrain, batching and LOD rather than faster generation itself.

## Verification

- All **27 game regression suites passed**, covering AI, economy, input, animation, maps, terrain/resources, menus, editor, heatmap, batching and presentation. The run resumed after updating a pre-existing tooltip wording assertion; its Classic/Modern upkeep amounts are still verified.
- New scaling suite: **1,104 checks**. This includes 160 original seeded-map fingerprints, **936 local-versus-exhaustive picking comparisons**, reduced triangle counts, exposed cliff counts across chunks, grass hysteresis/restoration, shadow bands and combined heatmap/LOD restoration.
- After the final hover cache change, scaling, performance, input and movement-indicator suites passed again.
- Native normal/showcase and wide overhead heatmap previews were inspected. Actual GPU instance readback for merged terrain is covered structurally; the batching regression's existing per-instance color/transform checks continue for ordinary prop batches.

Raw data: [final hover](C:/Users/Olek1/Documents/slay-game/artifacts/map_stress_implemented_final.json), [overview/rotation run](C:/Users/Olek1/Documents/slay-game/artifacts/map_stress_implemented.json), [generation comparisons](C:/Users/Olek1/Documents/slay-game/artifacts/map_generation_implemented.json). Full logs are alongside these files. The original stress datasets remain available for comparison.

Reproduce native measurements using `tools/map_stress_probe.gd` with **`--live-quality`**, which keeps the production LOD policy rather than forcing the old four-split/12-hex benchmark settings. For example:

```powershell
& $Godot --path . --script tools/map_stress_probe.gd -- --sizes=large,500,1000,2000 --seeds=42,71 --cases=wide,rotate,hover --duration=8 --live-quality --label=implemented
```

Run `tools/prepare_map_stress.ps1` to refresh diagnostic larger-map source copies after production generation changes. Numeric profiles above 1,000 tiles remain benchmark-only. The playable Very Large and Huge profiles can also be measured by name. Follow-up native hover/rapid-zoom measurements are saved in `artifacts/map_stress_playable_sizes.json`.

The playable-profile follow-up measured two seeds per size at 1080p/8× MSAA, with eight-second hover and rapid-zoom samples. Very Large averaged 513–531 FPS; Huge averaged 385–460 FPS. Every sample passed the 4.167 ms p95 budget and recorded zero LOD synchronizations/rebuilds. Huge's worst p99 was 4.35 ms (one hover sample); occasional frames still exceeded the 240 FPS budget, so the preset is a practical tested choice, not an every-frame or dense-endgame guarantee. The map suite passed 112,239 checks; editor roundtrip checks include a 1,001-tile authored island.

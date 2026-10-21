# AI turn stutter investigation — 20 October 2026

The largest movement hitches came from rendering pipelines being rebuilt for transient action effects, alongside redundant scenery and board refreshes. AI search already runs on a worker thread. This change preserves AI rules, search, animations, and playback speed.

## Reproduction and evidence

Godot 4.6.3, native Forward+ / D3D12, RTX 2060, windowed 1920×1080 requested resolution, existing 4× MSAA, VSync and FPS cap disabled. The deterministic crowded fixture uses seed 71 and the production full opponent-round orchestration. Ctrl playback is pinned at its production 6× setting. These are synthetic crowded boards, not representative starting positions.

Two original Huge-map captures reproduced 244–266 ms stalls. Most large movement spikes coincided with an increase in Godot's Surface pipeline compilation counter; the Draw compilation counter remained zero. Disabling merged terrain did not remove the issue. Disabling action ripples reduced frames over 50 ms from 41 to 11, identifying transient effect materials as a major trigger. Generating individual sprite frame textures took less than 0.3 ms in the instrumented run and was not the major source of these stalls.

Godot releases a StandardMaterial3D shader when the last material using its key disappears. A material template that has never requested its rendering RID does not retain that shader. The effect templates now request their RIDs and remain alive for the board's lifetime. Surfaces excluded from camera layers also prepare the ring and flash mesh/material combinations during scene loading. See the [engine material implementation](https://github.com/godotengine/godot/blob/4.6-stable/scene/resources/material.cpp) and [pipeline precompilation documentation](https://docs.godotengine.org/en/4.6/tutorials/performance/pipeline_compilations.html).

## Changes

- Retain initialized material templates for movement ripples, castle surrender rings, and recruitment/merge flashes. Each effect still duplicates its material, so simultaneous colors and alpha tweens remain independent.
- Prepare both ring and filled flash surface formats under the existing loading cover.
- Work around Godot 4.6 Forward+ light pairing when batching changes source mesh layers: hide the rendering instance using its old mask, set the mask, then restore rendering visibility. This avoids stale light references and a native scene-cleanup crash. See [the upstream issue](https://github.com/godotengine/godot/issues/121989) and [engine fix](https://github.com/godotengine/godot/pull/122064). The workaround covers static, army, and transition batching.
- Remember each tile's rendered scenery state. Moving a unit across otherwise unchanged terrain now retains its scenery and crystal nodes; changes to ownership, buildings, trees, graves, lairs, wards, or capital occupancy still refresh them. Playback explicitly invalidates scenery when destroying features.
- Skip unchanged settlement snapshots and one redundant notification before ordinary moves settle. Captures with an asynchronous surrender still notify before the surrender plays.
- Reduce static upload chunks from 24 to 12 hex coordinates per axis. An atomic update now covers one terrain region rather than scanning a larger scenery chunk. This trades some additional scenery draw batches for smaller update bursts.
- Extend the existing strain probe with playback speed, map size, pipeline counters, and frame-linked CPU/mesh/texture timings. Diagnostic switches can independently disable action ripples or merged terrain.

## Native measurements

| Scenario | Median frame | 99th percentile | Worst frame | Frames over 50 ms | AI decisions |
|---|---:|---:|---:|---:|---:|
| Huge, 1,019 tiles / 120 units, original, Ctrl | 3.115 ms | 30.369 ms | 265.595 ms | 43 | 122 |
| Same original case, second capture | 2.791 ms | 25.999 ms | 244.150 ms | 41 | 122 |
| Same case, optimized, Ctrl | 3.008 ms | 18.574 ms | 75.582 ms | 7 | 122 |
| Standard, 255 tiles / 60 units, optimized, Ctrl | 2.457 ms | 10.427 ms | 47.700 ms | 0 | 78 |
| Standard, normal playback, before final redundant-snapshot skip | 2.370 ms | 4.513 ms | 45.067 ms | 0 | 78 |

Every round completed and restored the player's turn. Between the first and last recorded slow frames, Surface compilations fell from 64 in the original instrumented run to 1 in the final Huge run. Static batch synchronizations fell from 156 to 72; the largest measured chunk scan plus build fell from 21.286 to 16.117 ms. Whole-round time changed only modestly, from 29–30 seconds to 27.6 seconds: the improvement concerns frame stalls, while search and animation scheduling still take time.

The table above was captured before a machine power loss. A post-restart confirmation (`..._120_fp_verified.json`) completed all 122 decisions with 1 additional Surface compilation, but CPU stages were uniformly about 1.6× slower (worst frame 119.469 ms). Its timings should not be compared directly with the earlier baseline. A separate post-restart paired effect-churn comparison is recorded below.

The controlled post-restart comparison keeps all CPU optimizations and the safe layer-change workaround enabled in both runs; only the old effect shader churn is reproduced in the first run:

| Huge / 120 units / Ctrl, post-restart | Original effect lifecycle | Retained effect shaders |
|---|---:|---:|
| Median frame | 4.876 ms | 4.819 ms |
| 99th percentile | 49.892 ms | 33.488 ms |
| Worst frame | 211.187 ms | 131.587 ms |
| Frames above 50 ms | 46 | 12 |
| Surface compilations during measured slow-frame span | 62 | 1 |
| AI decisions / round completed | 122 / yes | 122 / yes |

The final run's worst frame occurs at round settlement (revision 122, player faction restored), rather than mid-movement. Raw files: `artifacts/map_stress_heavy_turn_normal_120_fp_restart_churn.json` and `artifacts/map_stress_heavy_turn_normal_120_fp_restart_fixed.json`. Reproduce the first using `--ablation=effect_churn` and the second with no ablation flag.

These are individual native captures, not a statistical hardware survey. Severe hitches are substantially reduced, not eliminated. Huge-map preparation, faction changes, and round settlement can still combine authoritative rule work, UI/readout updates, army submission, and chunk uploads on one frame. Those remaining boundary stalls are the next profiling target; moving authoritative state mutations onto worker threads would require separate synchronization work.

Raw captures are in `artifacts/map_stress_heavy_turn_normal_120_fp_spike_before.json`, `..._fp_spike_trace.json`, `..._fp_optimized.json`, and `artifacts/map_stress_heavy_turn_normal_60_fp_standard_optimized.json`. The 1× capture is `..._60_fp_standard_normal.json`. The earlier material-retention and chunk-size captures are intermediate diagnostics, not the final implementation.

Reproduce the final Huge case:

```powershell
& $Godot --path . --script tools/heavy_strain_probe.gd -- --mode=turn --units=120 --difficulty=normal --turn-limit=65 --label-suffix=recheck
```

For Standard, add `--map-size=large --units=60`; for normal speed add `--speed=1 --turn-limit=120`. Use a workspace-local APPDATA directory for isolated preferences. Run timing captures without another game or test process active.

## Verification

Headless suites: animation 47 assertions, capture updates 1,174, static batching 937, army optimization 2,041, transition batching 22, playback speed 30, lighting 30, architecture 79; all passed. New regression coverage verifies unchanged scenery/crystal identity across movement and omission of redundant board notifications. The army optimization fixture exits successfully but emits an ObjectDB/resource warning during teardown.

Localization catalogue: 872 messages verified. The native animation fixture reproduced the upstream crash even with effect prewarming disabled. After the safe layer-change workaround, its 47 assertions pass and the process exits cleanly. Native Forward+ animation (47 assertions) and capture updates (1,173 assertions) both exit with code 0. Native renderer regression results are recorded in `artifacts/ai-spikes-native-test_animation.log` and `artifacts/ai-spikes-native-test_capture_updates.log`.

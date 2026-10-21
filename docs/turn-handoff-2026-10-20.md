# Last AI → World → player handoff

A focused native capture reproduced the reported hitch without simulating the AI round: Huge map, 1,019 tiles, 300 units, all troops marked spent, then the production World and player-start path. Before the fix, about 136 ms of work ran in one frame. That frame took about 158 ms including rendering.

The work stacked up as follows: World rules 9.6 ms, World presentation 32.6 ms, player settlement 20.7 ms, player board refresh 39.7 ms and final UI refresh 33.3 ms. The final UI refresh included a 23.5 ms army synchronization. Two intermediate economy projections were rebuilt even though a final HUD refresh immediately followed.

## Changes

- World rules and player settlement now use the existing ordered simulation worker. Short settlement jobs use high pool priority so background preparation cannot unnecessarily delay the next turn. RNG, starvation, effect expiry, animal actions and replay round numbering are preserved.
- Settlement suppresses intermediate economy readouts; animated wildlife impacts still update them immediately. The final HUD refresh happens before player commands unlock.
- Unit readiness is staged before rendering the player's changed cells. Movement/readiness changes retain their existing sprite, outline and rank markers rather than configuring them again.
- Tree/scenery-only changes no longer rescan the army. Protected structures, units and removed/replaced tiles still invalidate their relevant army chunks.
- During settlement, deferred army synchronization drains one coherent chunk per frame. Explicit combat/movement flushes retain their immediate behavior. The handoff waits for pending uploads before enabling player commands. Disabled batching also drains safely.
- Hotseat player starts share the same settlement/readiness behavior.

## Focused measurements

| Native Huge / 300 units | Before | Final priority-worker capture |
|---|---:|---:|
| Largest observed handoff frame | 158.2 ms | 38.1 ms |
| World presentation | 32.6 ms | 18.3 ms |
| Player board refresh | 39.7 ms | 20.8 ms |
| Final UI refresh | 33.3 ms | 12.4 ms |
| Army synchronization | 23.5 ms in one refresh | 0.6–7.2 ms per chunk |
| Total handoff wall time | 136.3 ms | 203.4 ms |

The fix exchanges one long freeze for a short staged handoff; total locked-input time is slightly longer in this fixture. The largest frame improved by about 76%, but remaining 30–40 ms frames are still possible. These are individual diagnostic captures, not a guarantee for every saved game.

The first asynchronous capture included first-use pool/background work and took roughly one second, while its actual World worker body took only 28 ms. The probe now warms the pool because a real last-AI handoff follows already-running AI jobs. Critical settlement jobs were subsequently prioritized. Awaited `world_rules` and `player_settlement` stages represent wall time, not time blocking the main thread; worker input/publication was roughly 0.6 and 0.4 ms per job in the final capture.

Raw files: `artifacts/map_stress_heavy_handoff_before.json`, `artifacts/map_stress_heavy_handoff_final.json` (before priority adjustment), and `artifacts/map_stress_heavy_handoff_priority.json`. In the initial capture, the second frame interval was inadvertently cumulative; the first 158.163 ms frame is the valid peak used above. Subsequent captures fix that interval accounting.

Reproduce only the handoff with `tools/heavy_strain_probe.gd -- --mode=handoff --map-size=huge --units=300 --label-suffix=recheck`. No full opponent round is needed.

## Validation

Headless checks passed: simulation worker 1,074 (including World/player settlement equivalence and replay rounds), readiness/budgeted queues, capture updates 2,201, animation 47, army optimization 2,047, playback speed 30 and hotseat 39. Native checks cover readiness, real Ctrl opponent-loop completion and worker-generated animal emergence through scoped World playback. The readiness suite also covers coalescing new edits, waiting for every chunk and disabled batching.

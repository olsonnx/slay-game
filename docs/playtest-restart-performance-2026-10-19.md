# Playtest restart rendering

The affected path is Pause / Restart while playing an editor draft, rather than regenerating the draft in the editor.

Restart departure and entrance previously suspended settled batching and restored every source mesh. A native Large authored map drew over 1,300 calls during each wave, compared with roughly 180 when settled. On larger maps the exposed source scenery scales into thousands of draws. The transition also rebuilt merged terrain at completion despite its unchanged home transforms.

Changes:

- Temporary MultiMeshes group opaque scenery by mesh/material/layers/shadow state. Every source tile keeps its own animation, delay and position. Instance transforms update immediately before drawing, after tweens, preserving alignment with soldiers.
- Completion restores the already-uploaded settled meshes and source suppression, avoiding terrain rescans and merges. Actual setting/board invalidations still trigger the required refresh.
- Hidden old tile nodes retire in bounded groups rather than one large deferred destruction.
- During covered construction, the camera skips unfinished source geometry. It resumes for the existing warmup/reveal phase once the settled batches are ready.

Native Compatibility-renderer validation on an RTX 2060 at 1200 x 800, VSync disabled:

- Large-map moving-scene draw calls fell from approximately 1,300 to 120-160. Maps in the probes are generated independently, so these are representative runs, not identical seeded A/B fixtures.
- Huge-map restart: approximately 84 FPS during departure, 93 during entrance and 117 once settled, with roughly 245-325 draw calls. Entrance p99 frame time was about 16 ms and settled p99 about 33 ms in this run. Covered preparation still performs necessary work and is reported separately in the logs.
- Logs: artifacts/playtest-restart-before.log, artifacts/playtest-restart-final.log, artifacts/playtest-restart-huge-final.log.
- Probe: tools/playtest_restart_probe.gd; use --huge and/or --uncapped after the Godot argument separator.

Validation includes native GPU-transform readback, animated source positions, pause/cancel, source suppression, retained terrain rebuild counts, resource retirement, authored player outcomes, startup and existing presentation/static-batching suites. Screenshots: artifacts/transition-batched-entrance.png and artifacts/transition-batched-departure.png.

## Remaining covered preparation hitch

Compared the normal game and editor playtest paths. Normal games generated rules on a worker, while authored playtests validated/restored their document and rebuilt rules on the main thread. Both built source tiles over multiple frames but then synchronously collected and uploaded the whole settled island through `visible_board_changed`.

Instrumented a native Large playtest restart: authored rule preparation took 10.5 ms, session setup 7.0 ms, and final scenery publication 219.1 ms. Covered preparation p99 was 240.9 ms. The full-board scenery publication was the dominant remaining hitch.

The shared preparation worker now handles authored validation and rule construction too. Validation owns a deep copy because legacy event normalization can modify rows. Player configuration consumes the already-prepared document instead of restoring every cell a second time.

Initial board construction now keeps refresh callbacks suspended until scenery is ready. The existing static batch implementation accepts a startup-only 4 ms budget, yielding between source tiles and mesh batches while retaining the same chunk sizes, materials, coastline neighborhood and merged terrain. Ordinary gameplay updates remain atomic. The loading cover and camera suppression remain active until all batches are complete.

Native 1200 x 800, uncapped, Compatibility renderer on RTX 2060:

| Run | Preparation p99 | Largest scenery work batch |
| --- | ---: | ---: |
| Large playtest, before | 240.9 ms | 219.1 ms (whole publication) |
| Large playtest, after | 19.9 ms | 10.8 ms |
| Huge playtest, after | 24.5 ms | 9.1 ms |
| Normal Large game, after | 20.8 ms | 7.9 ms |

These are representative runs, with some tests running concurrently; the first Large before/after maps were independently generated. The probe now uses seed 4242 and supports `--normal` for repeatable future game/playtest comparisons. Loading takes more frames to keep each frame responsive; these numbers describe frame spikes, not total loading duration. The work budget is checked between indivisible tile/mesh operations, so individual batches can exceed 4 ms.

Logs: `artifacts/restart-phases-before.log`, `artifacts/restart-phases-after.log`, `artifacts/restart-huge-progressive.log`, `artifacts/restart-normal-progressive.log`.

Regression coverage: startup now verifies that normal scenery collection spans frames, authored cells/resources/player/palettes survive background preparation and restart, the editor snapshot is untouched, and every tile is published before play resumes. Startup 14/14, static batching 1159/1159, editor loading 12/12, editor outcomes 72/72 and transitions 22/22 passed.

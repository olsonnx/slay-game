# Capture frame spikes and AI planning

The user reported player captures dropping roughly 300 FPS to 100 and concurrent enemy captures dropping to 30–40, plus unusually long AI decisions. These are transient CPU/frame-pacing problems, separate from steady map rendering.

## Reproduction and causes

`tools/capture_performance_probe.gd` uses actual movement records and concurrent playback on a seeded Modern Large/six-kingdom scene, 1280×820, unlocked FPS, saved video quality, RTX 2060. The fixture adds armies to a starting kingdom and captures neutral land. It measures playback frames separately from command-selection/commit CPU time.

Before this change, one capture produced a 91.480 ms maximum frame and three simultaneous captures produced 133.256 ms. Each board-change notification rescanned all opaque source nodes, materials and transforms: roughly 20–28 ms per scan, including scans that rebuilt nothing. Capture playback sends multiple notifications and finishes with an atomic board sync, so those costs accumulated. Raw evidence: `artifacts/capture_performance_before.json`.

AI search was nominally yielding every 4 ms, but a single step could exceed that threshold. Planner initialization, candidate generation and Hard reply evaluation remained on the main thread. The fixed 30-unit Large fixture measured 1,370 ms for Hard search, with a 39.8 ms peak step in the initial headless sample. Spending and dependent moves can require several searches in a faction turn; those individual search times are not full-turn durations.

## Implemented changes

- Gameplay caches source parts and tracks dirty tile IDs. Tile replacement, ownership/material changes, removed props and changed neighbour cap geometry invalidate the affected records.
- Known playback notifications share one deferred batch sync before drawing. Unchanged notifications do no batching work. Ordinary atomic `render_cells` flushes once; explicit full refresh retains fallback semantics for transitions, video preferences and unknown external scene changes.
- Chunk nodes and compatible MultiMesh renderers survive changed colours/membership. Only added/removed mesh/material groups create/free renderers. Established per-instance upload APIs are retained.
- The value filter only invalidates changed source materials/visibility. Unchanged filtered tiles skip repeated prop traversal during incremental playback; range/slider/toggle changes still refresh correctly.
- Enemy captures unrelated to the player's displayed economy skip repeated full economy reconstruction/HUD refresh. Player land loss, buildings, bridge support, inspected ownership and bank changes still update immediately at impact/arrival.
- Live AI planning runs on a WorkerThreadPool task using a private rules snapshot. Workers never access the scene, renderer, live board or gameplay RNG. Main-thread commits are validated as before. Pause prevents commits; cancellation is mutex-protected and acknowledged without blocking a render frame on a running task.
- Immutable AI query contexts calculate wages for all banks in one unit pass, instead of scanning off-land units separately for each kingdom. Hard reply evaluation and candidate generation share their query context. Difficulty depths, candidates, scoring and reply limits are unchanged.

## Final observations and limits

The final player fixture measured maximum frames of **29.692 ms for one capture** and **24.375 ms for three**, compared with 91.480/133.256 ms before. Source scans were approximately 2.8–5.7 ms and there were only two/three necessary syncs. Median playback frames were 3.041/3.583 ms. Command selection and commit took 1.913/3.258 ms separately. Unchanged board sync dropped from about 32 ms to 4.9–6.0 ms. Raw evidence: `artifacts/capture_performance_final.json`.

An additional final enemy fixture, with actual busy opponent HUD callbacks enabled, measured 38.405/27.413 ms maximum frames and 3.120/3.155 ms medians. These sample maxima are not a claim of completely hitch-free captures. Node/actor reconstruction, full visible snapshots and topology/UI work still leave measurable tails. The baseline player/concurrent fixture did not enable enemy HUD callbacks, so do not use its baseline as a direct enemy-HUD A/B. Raw evidence: `artifacts/capture_performance_final_enemy.json`.

`tools/ai_frame_probe.gd` compares identical native Hard searches without committing or changing the fixture. The first pre-accounting comparison measured main-thread median/p99/max frames of 9.249/18.609/20.673 ms, versus worker 3.857/6.057/7.067 ms. Search wall time was 1,236.797 versus 952.898 ms. After the accounting/reply-cache optimization, the same native comparison measured worker median/p99/max 3.606/5.884/7.995 ms and 833.760 ms wall time, with the same sequence and 130 evaluations. Raw final comparison: `artifacts/ai_frame_probe.json`.

The three-sample synchronous CPU probe after optimization measured medians of 27.114 ms Easy, 175.195 ms Normal and 697.204 ms Hard, retaining the original scores, sequences and 5/35/130 evaluation counts. These are single-board measurements and can vary with load, clock speed and scene complexity. Threading removes render-thread search stalls; it does not impose a think-time cap or shorten visible animation delays. Complex Hard turns can still take longer. Raw evidence: `artifacts/ai_performance_optimized.json`.

## Verification

All 25 regression suites passed. Final targeted results include AI 185, batching 1,347 headless / 9,105 native, performance 458, turn feedback 17, value filter 38, and long-scroll menu rendering 55,012; editor import/scan clean. Native instance readback is intentionally skipped with the dummy headless renderer. Tests cover native instance transforms/colours (with Compatibility precision tolerance), retained renderer identities, coalesced capture notifications, unchanged filtered notifications, exact bank accounting including bridge garrisons, worker/synchronous decision equality at all difficulties, snapshot/RNG isolation, queued cancellation, pause/shutdown, immediate income forecasts, ownership/filter restoration, and menu recycling.

Primary engine references: [thread-safe APIs](https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html), [WorkerThreadPool lifecycle](https://docs.godotengine.org/en/4.6/classes/class_workerthreadpool.html), [MultiMesh component precision](https://docs.godotengine.org/en/4.6/classes/class_multimesh.html).

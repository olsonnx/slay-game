# Startup performance — 12 October 2026

Native Godot 4.6.3 Compatibility probe, RTX 2060, 1280×820, 75 Hz; seed 42. These are observations on this machine, not a guarantee at other resolutions/hardware. The standalone probe does not include the original menu handoff; it therefore does not reproduce the user's entire 40–50 FPS report.

Original synchronous construction blocked for 76 ms (49-tile Very Small) and 194 ms (227-tile Large). Standalone arrival was approximately 73–76 FPS and settled rendering approximately 75 FPS. Large rendering used 3,643 draw calls with shadows and 1,379 without. Removing shadows did not meaningfully improve the already display-limited settled rate, so shadows and blur were preserved.

The app now stops the decorative viewport before preparation, presents an opaque cover, and generates independent rules on WorkerThreadPool. The job owns a separate RefCounted rules instance and never accesses scene nodes or the renderer. Its completed rules are adopted only after task completion and joining. Seed/RNG/state semantics remain identical. Scene construction stays on the main thread, yielding after a 4 ms budget checked between whole tiles. A complex tile can exceed that budget; observed peak batches were approximately 8 ms.

Three covered rendered frames warm actual geometry/materials/shadows before entry. The camera/world remain visible underneath the opaque cover so rendering can occur. The new game has disabled processing/input during preparation. Entry is staged while disabled; cover fades over 0.24 seconds, then gameplay processing starts and the full tile animation runs. Its tween uses idle/rendered-frame updates instead of 60 Hz physics ticks. The normal atomic render path for commands is unchanged.

Native app handoff with the final threaded preparation held 75.06 FPS during Large arrival (95th-percentile drawn interval 13.70 ms), and 75.00 FPS settled (13.83 ms). Construction used 17 batches, peak 8.30 ms. CPU build time was 86 ms spread across 227 ms wall time; generation took 125 ms on its worker in this run. Preparation trades a short covered wait for uninterrupted visible entrance; it does not lower steady-state draw count or guarantee FPS on a GPU-bound machine. The first FPS sample can still include loading resource work.

Reproduce with `tools/startup_probe.gd`: default records synchronous standalone startup; `-- --batched --label=after` uses prepared standalone construction; `-- --app` exercises the real menu handoff and saves screenshots. Reports: `artifacts/startup_before.json`, `startup_after.json` (batched before threading), `startup_app.json` (final app path). Screens: `startup_preparation.png`, `startup_settled.png`.

Regression coverage includes deterministic worker output, duplicate startup protection, yielding construction, controls locked through entrance, complete settlement, and existing pause/restart/defeat transitions. Startup tests are included as the 17th suite.

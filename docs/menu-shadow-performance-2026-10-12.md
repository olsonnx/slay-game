# Menu shadows — 12 October 2026

Menu sun now follows the saved Video → Shadows preference, including live changes. Sun direction, colour, energy and ambient lighting are unchanged. An orthographic shadow projection uses one pass with an 80-world-unit maximum distance; pooled scenery, independent tile flight, resolution cap and hidden-viewport shutdown are unchanged. Shadows remain available in both Water and Sky backgrounds.

Native Godot 4.6.3 GL Compatibility benchmark on RTX 2060 at 1280×820, current AA setting 3 (8× MSAA). Each trial uses initial seed 42, the same scrolling/camera trace (360 steps at 1/75 second), and 75 warmup draws. Two repetitions reverse the on/off order. VSync is tested both on and off, and all temporary preferences are restored without saving. FPS below is drawn wall-clock rate, not an isolated GPU timing.

| Mode | Shadows off | Shadows on |
| --- | --- | --- |
| VSync on, second trial (no capture overhead) | 74.97 FPS | 74.97 FPS |
| VSync off, average of two trials | 195.33 FPS | 166.23 FPS |
| Uncapped mean drawn frame interval | 5.12 ms | 6.02 ms |
| Uncapped 95th-percentile interval, trials | 5.69 / 5.79 ms | 6.86 / 6.82 ms |
| Mean total draw calls, including UI/root | 1,314 | 2,653 |

Measured overhead is approximately 0.90 ms per drawn frame (~17.5% more time, ~15% less uncapped throughput). Both retain 75 Hz headroom on this machine. VSync trial 1 averaged 73.55 FPS in both modes and includes a synchronous screenshot readback at the midpoint, so trial 2 is the clean capped comparison. These results cover the chosen seed/trace/settings, not every island, GPU or display resolution.

Reproduce with native Godot `--path . --script tools/menu_shadow_probe.gd --quit-after 18000`. Raw results: `artifacts/menu_shadow_comparison.json`. Matched captures: `artifacts/menu_shadows_off.png`, `menu_shadows_on.png`. The script rebuilds seeded scenery in the actual menu viewport and preserves the actual menu controls/vignette. It stops automatic scrolling and advances an identical trace manually, avoiding different layouts caused by different uncapped frame rates.

Targeted menu regression: 1,440 checks passed, including startup shadow preference, live toggling, a single projection, pooling, scrolling and gameplay/menu isolation. Gameplay shadow settings were not changed.

## Later stability tuning

The first shadow settings showed subtle movement artifacts. Final menu-only tuning narrows camera near/far to 0.1/90, disables shadow pancaking, starts fade at 1.0, sets bias 0.15 with normal bias 2.0, renders back faces into the shadow map, and adds mild blur 1.3. Keeping the normal bias lower caused visible stippled self-shadowing when tested with the tighter range; that experimental setting was rejected. Back-face rendering retained visible cast shadows without that stippling in captured frames. The actual camera orbit and scenery movement remain unchanged.

Final matched probe (`-- --label=stable`) kept clean VSync trials at 74.97–74.98 FPS. Uncapped trials were 166.80/176.55 FPS off and 147.26/138.04 FPS on, with means 5.83/7.02 ms respectively. These are a separate run with different throughput than the earlier measurements, so do not attribute all between-run difference to the tuning. Raw final results and screenshots use the `_stable` suffix, preserving the initial reports. Targeted suite now passes 1,441 checks, adding depth coverage throughout motion.

`tools/menu_shadow_stability_probe.gd` samples 20 clear tile surfaces over the same six-second movement trace and captures frames 40/80/120 with old/new settings. Natural shadow movement, grass crossings and rounded sampling coordinates also affect its luminance differences; the original versus final mean steps (~0.00148/~0.00153) do not quantify perceived edge shimmer. It is a diagnostic capture, not an automated assertion that every temporal artifact is gone. Shadow bias/reverse culling/blur follow [Godot's shadow mapping guidance](https://docs.godotengine.org/en/4.6/tutorials/3d/lights_and_shadows.html).

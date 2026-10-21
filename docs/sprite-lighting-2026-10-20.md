# Sprite lighting, 20 October 2026

Atmospheric lighting now shades units, animals and birds individually. Warm sunlight and real cast shadows affect their original pixel art. Nearby mana and building lights add restrained blue and warm colour. A cool ambient floor keeps shaded units readable. A shallow curved lighting volume adds shape without requiring hand-authored normal maps; its response is quantized to source pixels. No blur, new textures or additional lights were introduced by this extension.

The original textures, transparent silhouettes, kingdom colours, animation frames and pixel scale remain intact. Units retain their spent/ready tint and hover outlines. Birds retain fading and depth occlusion. Gameplay indicators remain unlit. Both moving sprites and settled army batches use the shader; changing lighting swaps materials without recreating army instance buffers. Materials are shared and cached, with a bounded cache for live sprite frames.

**Options → Video → Atmospheric lighting** controls the extension along with the existing scene lighting. Turning it off restores native unlit sprite materials and the original Simple scene lighting. The saved preference applies to gameplay, editor and replay boards.

## Incremental performance

These measurements describe the initial sprite pass, before the softer lighting revision below.

RTX 2060, Godot 4.6.3 Compatibility, shadows on, 4× MSAA, VSync off. Same seeded boards, cameras and Atmospheric scene lighting in both cases; only sprite shading changes. Standard: 255 tiles, six starting units. Huge: 1,019 tiles, 300 units. Two three-second samples per view/style, reversing order on the second pass, after warm-up. No other test suites ran during measurement. Actual PNG captures are **1685×1080**; the requested window and stretched logical viewport report different sizes, recorded separately in the raw data.

Values are means of per-run median timings; FPS is the mean of run averages.

| Map / view | Unlit GPU | Lit GPU | Unlit frame | Lit frame | Unlit / lit FPS | Draw calls, both |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Standard / overview | 0.677 ms | 0.673 ms | 1.931 ms | 1.893 ms | 496 / 504 | 231 |
| Standard / close | 0.929 ms | 0.926 ms | 1.854 ms | 1.955 ms | 516 / 486 | 209 |
| Huge / overview | 0.791 ms | 0.784 ms | 2.374 ms | 2.485 ms | 396 / 371 | 365 |
| Huge / close | 1.056 ms | 1.053 ms | 2.046 ms | 2.201 ms | 460 / 422 | 214 |

The samples show no measurable GPU increase or additional draw calls. Total frame time increased approximately 0.11–0.15 ms on the crowded Huge board, with 6–8% lower uncapped FPS. The tiny GPU decreases are measurement variation, not evidence of a speedup. These short static-board measurements do not predict performance on other hardware or include AI searches and gameplay rebuilds.

## Verification

- 31 sprite-lighting checks: live/batched frames, returning to an existing batch, every animal pose, bird material selection, immediate Simple restoration, unchanged snapshots and army uploads, bounded caching.
- 113 native pixel checks: all 12 kingdom palettes, animal atlas poses, both facings and two camera angles retain the original pixels under neutral shader settings; actual engine shadows reduce sunlight while preserving the ambient floor; blue and warm point lights tint sprites in the expected direction.
- 16 native bird depth checks: real bear, wolf, boar and unit sprites correctly cover birds behind them, including fading birds; foreground birds correctly cover those sprites.
- Existing suites passed: lighting 30, unit sprites 967, unit readiness 17, animation 46, static batching 1,174, performance 374, wildlife alerts 191, wildlife presentation 62, birds 54 and bird heads 55.
- Native gameplay captures and sun/shadow/blue/warm sprite renders inspected. Localization catalogue verified.

## Reproduce and inspect

- `tools/lighting_comparison.gd -- --sprite-lighting --duration=3.0` produces the controlled comparison using the native renderer.
- Raw measurements: `artifacts/sprite-lighting-comparison.json`.
- Matching close views: `artifacts/sprite-lighting-large-close-unlit.png` and `artifacts/sprite-lighting-large-close-lit.png`; equivalent Huge and overview captures are alongside them.
- `tools/sprite_lighting_probe.gd` and `tools/bird_depth_probe.gd` require native rendering. Their pixel captures are in `artifacts/sprite-lighting-probe-*.png` and `artifacts/bird-depth-*.png`.

## Softer lighting revision

The initial sprite pass was too bright, particularly on pale helmets and skin. The revised Atmospheric style reduces the sun energy from 1.12 to 0.92 and scene ambient energy from 0.30 to 0.26. The colour grade lowers midtones, gently compresses its brightest range to warm off-white, and uses less contrast and slightly less saturation. Simple retains its original settings.

Sprites use a lower cool fill (0.42/0.49/0.61), lower sunlight and accent gains (0.42 and 0.26), and a smooth highlight shoulder above 0.55. The shoulder scales RGB together, preserving hue and the ordering of pale details. It acts on the rendered pixels, leaving the source textures intact. Contact shadows have a stronger centre with a smooth falloff. The board remains sharp; there is no depth blur or new fog, render pass, light or texture allocation.

The revision passed 30 lighting checks, 31 sprite-lighting checks and 114 native pixel checks, including a direct comparison confirming visibly lower sprite brightness than the previous pass, readability under cast shadows, and warm/blue light response. Native Standard and crowded Huge captures were visually inspected. The short 0.3-second capture run is a rendering smoke test, not a replacement performance benchmark.

New captures: `artifacts/softer-lighting-large-close-lit.png`, `artifacts/softer-lighting-huge-close-lit.png`, with equivalent overviews alongside them. The preceding captures remain available under `artifacts/sprite-lighting-*.png`. Reproduce the new captures with `tools/lighting_comparison.gd -- --sprite-lighting --output-prefix=softer-lighting --duration=0.3`.

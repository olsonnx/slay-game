# Forward+ adaptation, 20 October 2026

The project now runs Forward+ through Direct3D 12 on Windows. The renderer change exposed colour-space assumptions in procedural geometry and custom shaders; the washed-out appearance was not just a lighting-strength issue.

## Changes

- Terrain, prop, transition, army, border and heatmap materials now identify their authored vertex/instance colours as sRGB. Retained geometry matches its original source materials instead of becoming pale when interpreted as linear colour. Instance buffers still store the same gameplay colours.
- Custom sprite shaders convert vertex tints and the authored cool fill appropriately for the active renderer. Highlight compression operates in display colour space, then returns to the renderer's working space. Texture sampling remains nearest, silhouettes remain unchanged, and spent/ready tints match native Sprite3D rendering.
- Original procedural water converts its hard-coded display palette to linear output under Forward+. Stylized water similarly converts authored glint/crest additions; its colour uniforms already have `source_color` hints. Existing depth reconstruction handles both clip-space conventions. Both styles retain their deep blue appearance and shoreline behaviour.
- Forward+ Atmospheric uses a 1.35-energy sun in `fff0d8`, ambient energy 0.26, saturation 1.0, restrained SSAO (radius/intensity 0.55, direct-light affect 0.10), and a 0.15-degree sun for slightly softer shadows. Simple disables SSAO and sun angular softness. The shadow preference also disables SSAO. Menus and boards share the profile.
- Manual covered light-variant warm-up now runs only on Compatibility. Forward+ uses its pipeline precompilation path. The existing preparation/reveal remains, as do eased zoom accents, stable shadow projection and removal of grass/pebbles.

No global illumination, volumetric fog, temporal antialiasing or depth blur was added. The existing screen-edge treatment and UI remain in place. Simple selects basic lighting within the active renderer; it is not a renderer switch or a guarantee of pixel-identical output across rendering backends.

Godot documents the [renderer colour-space difference](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html) and [pipeline precompilation](https://docs.godotengine.org/en/4.6/tutorials/performance/pipeline_compilations.html). The implementation was checked with actual native-renderer pixel comparisons rather than relying on settings alone.

## Verification

- 126 native sprite checks passed in Forward+ and Compatibility: all 12 faction palettes, animal atlas poses, camera rotations, facing, spent tints and actual MultiMesh/native Sprite3D colour parity, plus cast shadows and local light response.
- 11 native renderer checks passed in each backend. Mean source/batch RGB-vector error across the board was 0.001217 in Forward+ and 0.001612 in Compatibility, including edge/geometry differences. Both water styles and Simple/shadow profile resets passed.
- 16 native bird depth checks passed under Forward+, including foreground, background and fading birds. The readback fixture now lets queued rendering work settle before freeing its viewport and materials.
- Existing suites passed: lighting 30, transition fades 14, sprite lighting 31, static batching 952, transition batching 22, unit readiness 17, menu rendering 29,016, editor water-hover 12, performance regression 374, kingdom palettes 226.
- Native menu, Standard/Huge gameplay and both water-style captures inspected. First/repeat native Forward+ zoom sweeps had median frame times 2.459/2.330 ms, p95 4.322/3.056 ms and maxima 6.351/5.695 ms on this RTX 2060 run. No manual Compatibility warm-up was performed. Animations were frozen to isolate zoom rendering; this does not establish cold-driver performance on other hardware.
- Localization catalogue regenerated and verified.

## Artifacts

Before/after Forward+ gameplay: `artifacts/forward-before-large-close-lit.png` and `artifacts/forward-adjusted-large-close-lit.png`, with Huge and overview equivalents alongside them. Water: `artifacts/forward_plus-water-original.png`, `artifacts/forward_plus-water-stylized.png`; corresponding Compatibility captures use the `gl_compatibility-` prefix. Menu: `artifacts/menu_main.png`.

Native zoom data: `artifacts/forward-zoom-lighting.json`. Final static-render data: `artifacts/forward-adjusted-comparison.json`. The `forward-before` capture run used short samples for visual inspection and is not a reliable performance baseline. Reproduce the final captures/measurements using `tools/lighting_comparison.gd -- --sprite-lighting --output-prefix=forward-adjusted --duration=3.0`.

## Current performance

RTX 2060, Godot 4.6.3 Forward+/Direct3D 12, shadows on, 4× MSAA, uncapped, actual captured buffer 1685×1080. Two three-second samples per case after warm-up, reversing order, with no other rendering/test jobs running. GPU values below are the means of per-run medians for the lit Atmospheric cases, including SSAO and soft sun shadows.

| Map / camera | GPU time |
| --- | ---: |
| Standard / overview | 1.715 ms |
| Standard / close | 2.296 ms |
| Huge / overview | 2.053 ms |
| Huge / close | 2.671 ms |

Standard has 255 tiles and six starting units; Huge has 1,019 tiles and a synthetic 300-unit board. These static render measurements exclude AI search and gameplay rebuilds. They describe the current profile rather than isolating the cost of the renderer migration or individual effects. Simple disables the added occlusion and soft-sun settings.

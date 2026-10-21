# Lighting overhaul, 20 October 2026

Atmospheric lighting is enabled by default. **Options → Video → Atmospheric lighting** switches immediately to the original Simple lighting when disabled. The preference is saved and applies to gameplay, editor boards, replay boards and menu scenery. It does not change map state, RNG or army instance buffers.

The later [zoom lighting revision](zoom-lighting-2026-10-20.md) replaces the cutoff behaviour described below with eased accent intensity, covered shader warm-up and a stable orthographic shadow projection, and removes grass and pebble decoration. The measurements below remain the historical baseline.

The compromise uses the existing Compatibility renderer and one directional sun. Atmospheric adds warmer lower-angle sunlight, cooler ambient fill, restrained colour grading, deeper contact shadows, gently emissive windows, and at most three nearby blue/warm accent lights without shadows. Accents switch off beyond zoom 25, in the value heatmap, during transitions, and on inactive boards. Sprites now also respond to sunlight, real cast shadows and local accents; see the [sprite lighting extension](sprite-lighting-2026-10-20.md). There is no new fullscreen blur, volumetric fog, global illumination, shadow-casting point light or normal-map requirement.

Simple restores the original sunlight rotation, colours and energies, disables grading and accents, and restores contact-shadow textures and window materials. Daylight is an intermediate comparison preset, retaining the stronger direction and contact shadows with milder colour balance; the user-facing toggle selects Atmospheric or Simple.

## Native comparison

RTX 2060, Godot 4.6.3 Compatibility, shadows on, 4× MSAA, uncapped with VSync off. The requested window was 1920×1080; saved captures confirm the actual render buffer was **1685×1080**. Timings below therefore describe that measured buffer, not a full-width 1920×1080 render. Two 3-second samples per case, after 0.65 seconds of warm-up; the second pass reverses style order. No other test suites ran alongside this final comparison. Standard uses seed 71 with 255 tiles and six starting units. Huge uses the same seed with 1,019 tiles and a synthetic 300-unit occupied board.

These baseline measurements predate the sprite lighting extension. GPU columns are the mean of the two per-run median GPU times. FPS is the mean of the two run averages. These short static-board samples do not establish performance on other GPUs or include AI search and capture-time rebuilding.

| Map / view | Simple GPU | Daylight GPU | Atmospheric GPU | Extra GPU vs Simple | Simple / Atmospheric FPS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Standard / overview | 0.581 ms | 0.662 ms | 0.689 ms | +0.108 ms | 514 / 501 |
| Standard / close | 0.697 ms | 0.807 ms | 0.940 ms | +0.243 ms | 574 / 514 |
| Huge / overview | 0.663 ms | 0.769 ms | 0.796 ms | +0.133 ms | 394 / 386 |
| Huge / close | 0.837 ms | 0.947 ms | 1.064 ms | +0.227 ms | 458 / 422 |

Atmospheric added approximately **0.11–0.24 ms of measured GPU time**. Visible draw-call counts were unchanged between styles in each view. Overall frame times varied more than GPU times; use the raw samples rather than interpreting every FPS difference as lighting cost.

## Verification

- 30 lighting checks: live options switching, persistence and invalid values; exact Simple restoration; unchanged model/RNG/tile identities/army uploads; bounded shadowless accents; overview, heatmap and inactive-board suppression; menu and batched-window consistency.
- Existing checks: 1,174 static batching; 33,845 menu rendering; 374 performance regression; 499 UI layout; 76 menus. All passed.
- Native previews inspected for both gameplay styles, all three comparison presets, and the options toggle at 960×620.
- Localization catalogue regenerated and verified.

## Artifacts

- Raw measurements: `artifacts/lighting-comparison.json`
- Same-camera captures: `artifacts/lighting-large-close-simple.png`, `artifacts/lighting-large-close-daylight.png`, `artifacts/lighting-large-close-atmospheric.png`; equivalent overview and Huge captures are alongside them.
- Small-window options: `artifacts/lighting-options-960.png`
- Repeat with `tools/lighting_comparison.gd` using native rendering; `--duration=3.0` controls each sample.

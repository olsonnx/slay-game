# Zoom lighting and decoration cleanup, 20 October 2026

This describes the Compatibility revision. The later [Forward+ adaptation](forward-lighting-2026-10-20.md) limits manual shader warm-up to Compatibility and records current renderer-specific zoom captures separately.

Crystal and building light accents now ease in and out over 0.28 seconds, with a continuous zoom band from 20 to 28 and a proximity fade from 8 to 12 world units around the camera focus. Reversing zoom continues from the current intensity. Sources that remain nearby keep their light slots; replacements fade out before moving and changing colour. There are still at most three shadowless point lights. Heatmap, transitions, inactive boards and Simple lighting suppress them immediately. The controller sleeps once its fades settle.

The first visible light can require a new Compatibility shader variant. Loading now draws one, two and three overlapping accent lights using the actual board, materials and viewport under the existing preparation cover. The camera, light ranges and intensities are restored before reveal, with covered settling frames for queued driver work. Gameplay startup, editor map replacement and replay loading use this warm-up. It adds preparation work instead of deferring it to the first zoom. This follows Godot's [Compatibility shader warm-up guidance](https://docs.godotengine.org/en/4.6/tutorials/performance/pipeline_compilations.html).

Shadows no longer switch between one and two projections or abruptly remove small casters at zoom thresholds. One orthographic projection stays active, with shadow opacity easing continuously from full strength at zoom 24 to 0.68 at zoom 56. The minimum caster size stays fixed at 0.35. The camera clipping planes track the visible board depth; the old 1,000-unit far plane wasted shadow-map precision in an orthographic view. Trees and buildings retain directional shadows while zooming without adding a second light or duplicating shadow geometry.

Decorative grass tufts and pebbles are no longer generated, including on editor and menu terrain. Their procedural mesh/material factory and board-specific detail registration/zoom switches were removed. Trees, mountains, graves, crystals and gameplay objects remain. Generic batch detail support is retained for other callers.

## Verification

- 14 transition checks: partial intensity, reversing fades, continuous zoom strength, dark-before-relocation, heatmap suppression, smooth shadow opacity, unchanged gameplay/RNG and no zoom-driven terrain rebuilds or army uploads.
- Existing suites passed: lighting 30; map scaling 1,485, including decoration absence, stable shadow projection and picking across camera angles; static batching 952; architecture 79; editor loading 12; replay viewer 182; camera zoom 190; input 47; startup 14.
- Native probe uses the real preparation cover and 0.24-second reveal, then records the first and second zoom-in/out sweeps on a Modern map. On this RTX 2060 run, first/repeat median frame times were 2.510/1.994 ms, p95 3.432/3.109 ms and maximum 4.041/3.847 ms. The first sweep had no isolated light-activation hitch. Animations are frozen to isolate zoom rendering; these short measurements do not guarantee cold-driver behaviour on other GPUs.
- Native close and overview captures inspected for real cast shadows, light accents and removed decorations. Loading restores camera position/zoom exactly and preserves model snapshots and retained buffers.
- Final lighting 30, transition 14, sprite lighting 31, performance regression 374 and birds 54 checks passed after integration. Localization catalogue regenerated and verified.

The separate static comparison rendered at 1685×1080 with 4× MSAA, two three-second samples per case, reversing order. Atmospheric GPU medians averaged 0.797/0.897 ms for Standard overview/close and 0.851/1.105 ms for Huge overview/close on this RTX 2060. The fixed caster policy retains more small shadow casters in wide views than the old cutoff; this is the cost of avoiding abrupt removal. Results are current-run measurements, not a controlled speedup comparison with the earlier lighting revisions.

Raw first-zoom data: `artifacts/zoom-lighting.json`; captures: `artifacts/zoom-lighting-close.png` and `artifacts/zoom-lighting-overview.png`. Run `tools/zoom_lighting_probe.gd` with the native renderer. The Standard/Huge static comparison uses `tools/lighting_comparison.gd -- --sprite-lighting --output-prefix=zoom-fades --duration=3.0`, with separate `artifacts/zoom-fades-*` captures and raw measurements.

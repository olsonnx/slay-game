# Distant clouds

Clouds fade in between camera sizes 32 and 52, surrounding the island while
leaving the playable board readable. They work with Water and Sky backgrounds,
including rotated and overhead views. Options > Video > Clouds disables them;
the preference is saved and included in the Video category reset. Reduced motion
freezes their drift. Otherwise clouds drift at less than half a tile per second.
Loading, island transitions and retired boards hide them.

The island sits inside an asymmetric clearing parallel to the tile plane.
Twelve broad directional bounds enclose the island with unequal offshore
margins, including at least four world units of open water beyond tile edges.
Cloud density thins over a twelve-unit transition outside that envelope. The
edge uses the volume's own noise and lighting, so its billows have the same
appearance and drift as the surrounding clouds. There is no separate noisy
opacity cutout. Reduced Motion freezes the volume. The clearing follows camera
tilt, panning and zoom; its bounds update only when the board changes.

The volume shader adapts thepathgame's CC0
[Volumetric Raymarched (animated) Clouds v2](https://godotshaders.com/shader/volumetric-raymarched-animated-clouds-v2/).
It reconstructs orthographic world rays through an animated 3D-noise slab, with
24 bounded steps and separate density/light samples. Noise resources are shared
and the real shader passes are warmed behind the startup cover.

Raymarching runs in a transparent viewport at half logical resolution, capped
at 640 × 360. A separate full-resolution spatial pass reads opaque scene depth:
terrain and props are discarded from the cloud composite as an extra safeguard.
The volume's density envelope provides the broad offshore clearing rather than
following individual coastlines. Water is identified by its world-space surface height.
Depth samples reconstruct the sampled texel's exact ray,
which avoids false land classifications in orthographic views. Reverse-Z and
the Compatibility NDC range are handled separately. UI layers render normally.

At close zoom the volume viewport stops updating and its composite is hidden.
Stationary cameras reuse their parameters; only the drift clock advances.
No game RNG, cell records or movement/picking geometry is changed.

## Validation

`test_clouds` passes 340 checks for offshore clearance around every tile and
projection during panning and rotation, distance fade, no close-range volume rendering,
motion preferences, loading/lifecycle, resolution bounds, saved settings, Video
reset and unchanged game state/RNG. Startup, settings, UI layout, camera zoom,
opening camera, presentation, lighting and transition suites also pass.

`tools/cloud_preview.gd` renders actual Forward+ and Compatibility views of a
500-tile island, with both backgrounds at three angles. Every one of the twelve
cases checks 379 clear tile centers against a cloud-disabled reference: zero
sampled tile colors change. Each case also requires visible clouds outside the
board, so a missing effect cannot accidentally pass the exclusion check. It also
advances the normal animation clock by twenty seconds and checks that the
rendered volume visibly changes, rather than testing the clock alone.

Raw results and screenshots are under `artifacts/cloud-preview-*-results.json`
and `artifacts/clouds-*.png`. GPU timings in those diagnostic files are local
observations, not a whole-game performance guarantee. Run the tool with the
normal renderer and again with `--rendering-method gl_compatibility`.

The source notice is `resources/shaders/clouds.LICENSE.md`; future playtest
packages include it. No executable or ZIP was rebuilt.

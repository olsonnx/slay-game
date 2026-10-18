# Menu seams and falling-tile occlusion

The supplied crop identifies the edge between kingdom colour and earth. Inspection found two concrete problems, corrected on 13 October 2026.

## Coloured/earth wall overlap

Joined kingdom edges reach the full hex footprint. Their former cap walls descended to world y=-0.0645, overlapping the earth walls at exactly the same horizontal plane. Opposing colours could therefore compete in the depth buffer as the camera or neighbouring tiles moved.

`TerrainTile` now makes the cap a closed 0.0105-high layer whose bottom meets soil at y=0. The original surface height y=0.0105, kingdom footprint, border visibility slider and materials remain unchanged. The change is shared by gameplay and the menu. No shadow, antialiasing or depth setting was weakened to hide the overlap.

Regression coverage checks all 63 joined-cap masks for the soil-level lower bound and retained top height. Existing geometry, recycling, preference and filter checks also pass. This removes the identified coplanar wall geometry; it is not evidence that every form of shadow or pixel-edge aliasing is eliminated.

## Departure motion

The old departure vector cancelled vertical movement by adding the camera's backward axis. The resulting motion slid tiles toward the viewer along the land plane, so a rear tile could move in front of foreground land.

Menu departures now move straight down, retaining their horizontal footprint. Foreground geometry naturally hides the falling tile. The initial repair let the opaque water plane swallow the fall; the user requested that tiles leave the screen instead. Menu water now opts into `backdrop_depth` in the shared water shader: its original world-space palette/ripples are preserved, but its clip-space depth is placed at the far background, allowing falling tiles to remain visible until they exit the frame. Gameplay retains physical water depth outside departure. This requires no extra viewport or render pass. Departure distance accounts for screen position and a tall-prop margin, so tiles are not hidden while still in the frame. Independent schedules, durations and smooth easing remain. Entry motion was not changed.

## Gameplay follow-up — 16 October 2026

Gameplay island departure still used the original depth-cancelling slide and a
small upward lift. `BoardTransition` now drops tiles vertically with fixed X/Z,
calculating enough travel to clear the viewport with a margin for tall props.
Near overhead, the fall ends beyond the camera's far plane rather than requiring
unbounded travel. Water uses backdrop depth during departure only; cancellation,
completion and arrival restore its physical depth. Existing timing, staggered
delays, pause behavior and entry animation remain.

`test_presentation.gd` covers both background modes, four camera pitches through
89.9 degrees, three yaws, fixed footprints, increasing camera depth, clearance,
and cancellation/restoration. `tools/gameplay_departure_probe.gd` renders native
pixel comparisons proving foreground land occludes a rear falling tile and that
an unobstructed tile remains visible below water. Images are saved as
`artifacts/gameplay_drop_occluded_{water,sky}.png` and
`artifacts/gameplay_drop_unobstructed_{water,sky}.png`.

Verification: presentation 9,902; animation 44; menus 46; startup 5; static
batching 1,120; playback speed 30; results 68; menu rendering 47,415 checks passed.
Native Water/Sky pixel checks passed and the captured images were inspected.

Tests verify downward movement, fixed X/Z, increasing camera depth and offscreen clearance at three points in the menu orbit. Native renders in both background modes confirm a departing rear tile is hidden by the front tile. An isolated native departure additionally checks pixel-colour differences against the backdrop after crossing the physical water height, proving water no longer hides the tile.

## Verification

- Presentation: 5,143 checks passed.
- Menu rendering: 55,012 checks passed after the water/exit correction.
- Menu background: 4,324 checks passed (scenery-dependent count).
- Resources/terrain: 2,498 checks passed.
- Static batching: 1,311 checks passed.
- Value filter: 38 checks passed.
- Godot editor import/scan: clean.
- Native close-ups: `tools/menu_visual_fix_probe.gd`, fixed seed 42, 960×720, Water and Sky, retained video antialiasing and shadow settings. Images in `artifacts/menu_rim_fixed_*.png` and `artifacts/menu_drop_fixed_*.png`.

The earlier exposed-rim prototype stays disabled by default. No merged-terrain rewrite or new performance claim is included in this repair. The user's next requested experiment is merged 3D terrain, following the approach in `low-spec-rendering-review-2026-10-13.md`.

Shader reference: [Godot 4.6 spatial shader POSITION and CLIP_SPACE_FAR](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html).

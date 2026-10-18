# Unit sprite sheets

The game uses `assets/units/scout.png`, `warrior.png` (the Soldier rank), and
`knight.png`. Each cell is 32 × 32 pixels. Rows and frame counts are defined in
`src/rendering/unit_sprite_library.gd`.

| Action | Scout | Soldier | Knight |
| --- | --- | --- | --- |
| Ready idle | Row 0, 4 frames | Row 0, 4 frames | Row 0, 8 frames |
| Movement | Row 1, 6 frames | Row 1, 6 frames | Row 1, 6 frames |
| Charge toward an enemy | Movement | Movement | Row 2, 6 frames |
| Attack | Row 3, 7 frames | Row 3, 6 frames | Row 4, 7 frames |
| Surviving a blocked attack | Row 4, 3 frames | Row 5, 3 frames | Row 5, 2 frames |
| Death | Row 5, 5 frames | Row 6, 4 frames | Row 6, 6 frames |

Rows are numbered from zero. The warrior's additional row 4 is available as the
`thrust` clip. Jump clips are defined for future use; current rules
have no jump action. Available troops in the active kingdom play their idle clip.
Moved troops and inactive kingdoms use the first idle frame with a dimmed tint.
Ending a turn also dims unused troops; their ready pose returns next turn. This
is presentation state, so it does not change move records or replay rules.

A shared eight-frame-per-second clock updates idle source images for pixel
picking and swaps shared batch textures. It does not rebuild instance buffers.
Hover outlines follow the current frame, and pausing freezes the idle clock.

All ranks use the same `0.08` world units per source pixel. This keeps their pixel
sizes consistent, with infantry footprints close to the previous sprites and a
larger mounted silhouette. Ground anchors, hover outlines, and placement previews
derive their size from the same scale.

Attack impacts occur on the strike frame. Deaths finish before removal, including
both knights in a duel and troops lost during turn preparation. Animation frames
follow playback speed and pause. Facing follows movement relative to the camera;
settled batches and pixel picking retain the horizontal flip.

Recruitment, upgrades, summons, and merges share a warm tile flash and expanding
hex ripples. The resulting rank sets the pulse count (one, two, or three), glow
strength, radius, and duration. These short effects live outside movement
snapshots so merge arrival effects survive the final render. Cancellation and
map changes clear them; their tweens follow playback speed and pause.

## Kingdom clothing

The library replaces `#6098e8` and `#4058c0` with light and dark shades of the
kingdom's terrain color. Two additional masks combine exact palette matches with
regions inside each 32px pose:

- The scout's sleeves use `#5a7b94` in the lower arm regions. Helmet pixels using
  the same shade stay unchanged.
- The horse's tail uses `#373757` in the leftmost 12 pixels. Tack and rider trim
  using that shade stay unchanged, including during death animations.

This preserves shading, alpha, armor, skin, weapons, and the horse's coat. Bridge
troops use their unit owner's color.
Source PNGs remain unchanged; faction sheets and animation frames are generated
and cached at runtime. Recruit cards and placement previews use the same artwork.

If replacement artwork uses a different palette or changes sleeve/tail placement,
update the palette entries and mask regions in the library. Keep cell dimensions and row mappings consistent, or
update the clip definitions and crop together.

Run `tests/test_unit_sprites.gd` for palette, frame, timing, batching, cancellation,
and combat checks. `tests/test_unit_readiness.gd` covers idle animation, turn
handoffs, bridge ownership, pause, and batch texture updates.
`artifacts/unit_sprite_preview.gd` renders previews for six sample palettes;
`artifacts/unit_idle_preview.gd` verifies idle playback in the native renderer.

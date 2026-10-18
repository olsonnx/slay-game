# Content-sized UI text — 12 October 2026

Province hover tooltips now wrap inside a fixed 278 px width and derive their height from the rendered Label minimum size. Top and bottom padding are both 9 px. Mountains and stacked province modifiers get extra height; short neutral descriptions shrink the box. Screen-edge positioning uses the measured box size rather than the previous 88 px height assumption.

The help panel uses separate shortcut and description columns. Each row wraps to its column width, and the next row follows the taller label. Its panel height follows the last row. Notification banners also grow and shrink with their text, with 8 px vertical padding. Province details wrap the status description, move the Develop button down when necessary, and grow upwards while retaining their position above the resource dock. Mountain/bridge inspectors omit the unused action space. Encounter titles, stories, hints and choices now follow the preceding section's measured height, preserving 20 px bottom padding and centered positioning.

## Approach and performance

`src/ui/ui_theme.gd` provides shared `fit_text`, `fit_text_panel` and `keep_on_screen` helpers. Godot's Label supplies the actual word-wrap measurements; no approximate character-count sizing is used. A small cached signature tracks text, width, font, font size and line spacing. Matching inputs skip text assignment, shaping and resizing. Existing panels and labels are retained. Help is laid out when constructed, notifications when announced, inspectors when refreshed and encounters when presented. Tooltip refreshes check the signature and continue updating position while the pointer moves.

Godot containers are also a reasonable solution: they respond to minimum-size changes and do not inherently require continuous layout or GPU computation. For these few existing manually positioned panels, measured, cached sizing avoids a new hierarchy of container nodes and preserves the current anchors and animations. It is not a claim that containers are generally slower.

Matched headless CPU benchmark: Godot 4.6.3, Modern Small, seed 42, five batches of 1,000 calls, median microseconds per complete `show_world_tip()` call. Changed calls alternate mountain and neutral provinces. The unchanged case repeatedly refreshes the same mountain. This includes existing province/rule queries and pointer positioning, not only layout.

| Refresh | Before | After | Additional CPU time |
| --- | ---: | ---: | ---: |
| Same tooltip text | 15.180 µs | 18.158 µs | 2.978 µs (0.003 ms) |
| Different tooltip text | 16.772 µs | 141.111 µs | 124.339 µs (0.124 ms) |

At 60 unchanged refreshes per second, the measured extra work is about 0.179 ms of CPU time per second. A changed tooltip pays the text-shaping cost once per change, rather than once per frame. Hardware, text length and fonts affect these timings; this is not an FPS or GPU benchmark. Raw results: `artifacts/ui_layout_before.json`, `artifacts/ui_layout_after.json`. Reproduce with `tools/ui_layout_probe.gd -- --label=NAME`.

No shader, render target, 3D mesh or GPU layout pass was added. Panels still draw a background and glyphs. Their area and text wrapping can change the pixels drawn; help uses additional retained Labels for its columns. A material GPU impact is unlikely for these small overlays, but GPU time was not measured and no zero-cost claim is made.

## Verification and future limits

`tests/test_ui_layout.gd` checks immediate and deferred tooltip sizing, equal padding, all screen corners, stacked statuses, cached reuse, help containment, long/short notification resizing, province action spacing, all existing encounters and a longer synthetic title/story. Native previews at the minimum 960 × 620 window are saved as `artifacts/ui_help.png`, `ui_mountain.png`, `ui_neutral.png`, `ui_province.png` and `ui_encounter.png`. The test supports `-- --preview` for reproducing them.

Current menus, shop labels and options text fit their allocated spaces and retain their existing layouts. Native button tooltips already use Godot's content sizing. Future localization, larger UI fonts or much longer encounter text can exceed an entire viewport; those cases need bounded scrolling, rather than unlimited panel growth or smaller text. Options already has little spare vertical room at the minimum window size. If UI font or language preferences are introduced, relayout the static help rows and all visible text panels when those preferences change.

## Follow-up: dock padding and close buttons

Dock actions previously had 12 px left padding and 18 px right padding. Both rulesets now use 15 px on each side; gold labels and resource hit areas share those outer insets. Standard button style margins also made requested close-button rectangles larger and uneven, crowding the Knight card. Shared `place_close_button` uses 4 px internal margins and a true 32 × 32 px square. It anchors the button with matching top/right insets.

Recruit/Build/Spells headers now leave 15 px below the close button before cards begin. Card left/right/bottom margins are all 15 px. Shop height is derived from header, grid and footer (188 px for Recruit/Build, 307 px for Spells), growing upwards above the unchanged resource dock. Classic building cards use an 8 px gap to preserve equal side padding. Province and statistics close buttons also share the square sizing. These are construction-time geometry/style changes, with no added per-frame layout work.

Affected verification passed: 96 layout checks, 33 economy/restart checks, 160 events/spells checks and 5,080 presentation checks. Native minimum-window screenshots include `artifacts/ui_recruit.png`, `ui_build.png`, `ui_spells.png` and `ui_build_classic.png`.

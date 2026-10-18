# Movement indicators

Click a unit to see a **gold area perimeter** around the tiles it protects, matching the cyan movement range's width, dark backing, rounded joins and subtle wash. Shared internal edges are omitted. No additional text appears. Coverage includes its own tile and adjacent tiles with the same terrain owner; enemy, neutral and more distant tiles are excluded. Neutral bridge garrisons defend their bridge only. Units still protect after spending their move. Enemy units can be inspected without selecting movement commands; clicking a legal attack target with a friendly unit already selected retains the existing attack behaviour.

Protection shows the unit's contribution, including overlapping coverage from stronger defenders; actual defence remains the maximum provided by units, capitals and towers. Existing combat/duel/ward rules are unchanged. Gold outlines coexist with cyan movement range in both movement styles and camera views, hide with the value filter, and clear on cancellation, placement actions, new games and opponent turns. Protection uses the visible board snapshot and retains geometry on unchanged hover. `KingdomMovement.unit_protection` defines coverage; `board_overlays.gd` shares `show_area` for both movement and protection (three meshes each). Gold is slightly raised so coincident borders remain visible without flickering. No terrain materials or rule state are changed.

The default movement presentation outlines the union of the selected unit's legal destinations and its source in cyan. Shared internal edges are omitted; holes and separate reachable patches retain their own boundaries. A very soft uniform wash marks the region while preserving normal terrain and ownership. Only the source and hovered destination receive individual emphasis. The source is cream; hover uses cyan for moves, gold for captures, coral for attacks and purple for merges. Ordinary kingdom outlines are suppressed while a unit is selected. Terrain and units retain their original materials.

The route is one continuous arrow with smooth quadratic bends, one terminal arrowhead and a dark outline. Its color matches the destination action. It starts clear of the source and ends on the destination. There are no intermediate arrow glyphs or separate arrow badges for moves/captures/attacks. Merges retain their plus badge. The arrow is one triangulated polygon with a constant-width offset outline; fill and outline share the same plane, avoiding projection shifts and uneven head borders. Models still occlude indicators naturally. Invalid targets retain the existing red preview/X; raised mountains can obscure the central X, but their red tile surround remains visible.

**Options → Gameplay → Clear movement indicators** defaults on. Turning it off restores the original selection/kingdom outlines, reachable outlines, dotted route and destination preview. This saves in `gameplay_settings.cfg`, applies immediately without clearing selection, and works from the main and pause menus. Legacy files and malformed values default on. Recruitment, construction, spells and the noninteractive menu landmass retain their existing presentation.

`board_overlays.gd` owns the visuals. Legal destinations and paths still come from the authoritative movement rules. Hover colors use the board's visible snapshot, including bridge garrison ownership. The retained-overlay signature includes the preference, and the game's preference-change signal refreshes overlays immediately. The region uses three meshes (wash, boundary backing, boundary color); the entire arrow uses one vertex-colored mesh regardless of route length. Only source/hover rings use cached hex meshes. Shared `flat_strokes.gd` creates the polygon outline and full-length boundary segments with rounded endpoint joins. Movement and value-filter borders use the same join helper so corners stay closed. Unchanged hover retains its geometry. The value filter hides indicators and restores them on exit.

## Verification — 13 October 2026

Latest visual simplification: removed the contextual text and replaced individual inset rings with the shared area perimeter/wash. Indicators **391**, heatmap **38**, performance **458** passed. Native minimum-window Water/angled and Sky/overhead previews inspected. This supersedes the text and ring presentation described in the initial protection revision below.

Latest unit-protection revision: native indicators **403**, input **42**, heatmap **38**, performance **458**, UI layout **106**, menus **46**, animation **40** passed. Checks cover exact defensive coverage, moved/hostile units, stronger overlapping defenders, neutral bridge garrisons, absence of enemy movement commands, cache retention, style/camera/filter restoration and cancellation/action/new-game cleanup. Native 960×620 angled Water and overhead Sky previews inspected (`preview_range_focused_small_water_modern.png`, `preview_range_focused_small_sky_modern_top.png`). Unrelated game simulation suites were not repeated.

Latest outline/join repair: indicators **337**, heatmap **38**, input **42**, performance regression **284**, presentation **5,080**, all passed without engine errors. Native angled/overhead movement and Water/Sky value-filter previews inspected. Replaced the unequal-height arrow backing and inset/disconnected border endpoints; original-indicator toggle remains intact.

- All 20 existing suites from `test_animation` through `test_heatmap` passed. General game and AI suites were not repeated for this presentation change.
- Current `test_indicators.gd`: **337 checks passed**, covering three seeds in both rulesets, exact agreement with legal targets/routes, omission of shared boundary edges, holes, disconnected patches, a single terminal arrowhead, blocked destinations, matching hover colors, merges, bridge ownership colors, retained geometry, both camera views, live style switching, selection/state preservation, value-filter restoration, cancellation and preference round trips.
- Final checks after the area/arrow revision: indicators **337**, input **42**, performance regression **284**, heatmap **38**, expansion **409**, all passed without engine errors. Earlier per-tile revision also passed menu **46**. The indicator-only test mutes audio to avoid unrelated headless MP3 playback cleanup warnings.
- Native 960×620 previews inspected on Water at an angle and Sky overhead, plus original-style comparison, a merge, a mountain hover and Gameplay options. This is visual inspection and regression verification, not a human usability study or a new GPU benchmark.

Reproduce with `tools/preview.gd -- --modern --intent-move --movement-focus --water --small-window`. Add `--legacy-indicators` for the same scene with the original indicators; substitute `--sky --top-down` for the overhead view. Use `--movement-range --movement-focus --intent-merge` or `--intent-invalid` for alternate hover fixtures. Preview switches do not persist preferences.

Current captures in `artifacts/`:

- `preview_focused_small_water_modern_intent_move.png`
- `preview_legacy_focused_small_water_modern_intent_move.png`
- `preview_focused_small_sky_modern_top_intent_move.png`
- `preview_range_focused_merge_small_water_modern.png`
- `preview_range_focused_invalid_small_water_modern.png`
- `menu_options_gameplay_small.png`

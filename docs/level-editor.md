# Level editor

Open **Level editor** from the main menu. It uses the game's raised 3D terrain, procedural props, soldiers, camera and saved appearance settings. The UI follows gameplay: a title at the upper left, camera/heatmap/history/help/settings controls at the upper right, a compact tool dock at the bottom left, and **Save**, **Load** and **Playtest** at the bottom right. Tiles, Units, Build and Paint open tool cards above the dock. Picking a tool opens its own animated context panel, styled like gameplay province details. The panel stays open while painting; only the panel itself blocks map input. Events and Start open their tool contexts directly. Close a context with × or Escape and select the tool again to reopen it. The layout fits 960×620 without a scrolling sidebar.

Start with the generated island, or open the upper-right cogwheel and choose a size and rules under **New island**, then **Generate island** or **Blank island**. These selectors apply to the next island; they do not reinterpret the current level. The cogwheel also provides starting gold, Center camera and Main menu. Changing islands, loading another level or leaving the editor asks before discarding unsaved changes.

## Editing

- Choose a card and click/drag with the left mouse button to place or paint. **Tiles** (Land, Mountain, Bridge, Water) uses right click/drag to delete entire provinces and all their decorations, even when clicking a soldier, building or mountain. **Painting** (Units, Build, Paint) uses right click/drag to clear all decorations while retaining terrain, ownership and value. Painting preserves mountain/bridge terrain too. Opening a category immediately switches to a suitable brush; the heading identifies the current mode.
- Fast drags fill intervening hexes without gaps. Each province changes at most once per stroke, and a held button also paints while the camera moves. Moving over a UI panel interrupts the connecting line. Painting stays within the selected map size's bounds. Hover previews the hex, coordinates, value and owner.
- Owner assigns Neutral or any of the 12 current kingdoms. The Land tool context exposes owner, land value and random values. Owner and Value painting expose just their applicable fields. The owner list comes from the map's saved kingdom definitions; values range from 1 to 6. Existing land keeps its ownership and value when redrawing its shape.
- **Start** activates the starting-kingdom marker. Click an owned province to place or move the single **PLAYER START** marker, without replacing its capital, units or decorations. Playtesting gives you that province's current owner and initially selects its connected kingdom. Repainting ownership transfers the starting role automatically. Right click the marked province with this tool to remove only the marker. Deleting its land clears the marker; neutralizing its land leaves an invalid marker that must be fixed before playtesting. Marker edits support undo/redo. Generated islands start with a marker; blank islands require one.
- Each tool context includes placement instructions and a Brush selector for variants in its category. Units offer Capital, Scout, Soldier and Knight; Build offers House and Tower. Units and buildings use the existing province owner. Decoration, terrain, clearing and player-start tools each show their own behavior without unrelated settings. Water and Clear objects are also available in the Tiles and Paint categories.
- Place capitals, Scouts, Soldiers, Knights, houses, towers, trees or graves. Units can share capital tiles. Other object brushes replace incompatible objects, preserving mana sources. Units and buildings need owned land. Decoration clearing removes units, capitals, buildings, trees, graves and mana sources together.
- Modern also offers neutral, impassable Mountains, Mana sources and neutral Bridges over water. Land converts mountains/bridges to ordinary neutral land. Modern tools are disabled on Classic maps. Units cannot be placed directly on bridges; they can enter them during play.
- **Land / Value context → Random values 1–3** (V) gives newly placed/restored land and Value painting a random value per province. Existing land is not rerolled by the Land brush. The fixed input becomes read-only while random values are enabled. Undo/redo preserves the exact sampled values; this brush preference does not change the level's gameplay seed.
- **Events** searches the full event catalog by ID, title, description and choice outcomes. All search words must match, in any order. Selecting a result immediately updates the event brush and displays its choices. Keep the browser open while painting or searching; there is no confirmation step. A search with no results disables event painting until a result is selected again. Left drag places markers on land; right drag clears decorations. Events replace other objects while retaining terrain, ownership, value and mana sources. Entering a marked province always triggers and consumes its encounter. Unmet main-outcome conditions produce a one-time alternate story; the lumberjack adapts to the actual forest coverage and jokes if there are no trees. Encounters cannot be revisited. The event browser displays main-outcome requirements and searches them alongside the story and outcomes. Modern rules are required; mountains and bridges cannot hold events. Markers support sampling, undo/redo and save/load, and the browser automatically includes new catalog entries.
- **I / Alt + left click** samples a province's decoration/terrain brush, owner and value. Sampling turns off random values so the copied value is exact.
- **Value heatmap** uses the same raised 3D filter as gameplay, with a live range legend and exact values on hover. Painting, deletion and undo update it immediately. Its state is preserved when returning from playtesting; the playtest has an independent view.
- Set starting gold, shared as an initial amount for every connected kingdom. Each faction starts with one mana when its capacity permits under Modern rules.
- Undo/Redo restores a complete brush stroke; history retains up to 60 strokes. Ctrl+Z / Ctrl+Y (or Ctrl+Shift+Z) provide shortcuts.
- Alt + right drag rotates, the wheel zooms, middle drag or WASD pans, and Tab/the upper-right view button switches Overhead/3D. Returning the pointer to the map or interacting with it commits numeric text and releases textbox focus. Enter finishes editing; Tab switches the camera even from a text field. Normal typing remains available while the pointer is over the active field. Modal dialogs keep their own focus and keyboard navigation. The ? button lists shortcuts; tooltips and card numbers make them discoverable.

## Shortcuts

Camera, heatmap and Units/Build/Paint category shortcuts follow saved **Options → Controls** bindings. Defaults and additional editor shortcuts:

| Key | Action |
| --- | --- |
| T / Q / E / R | Tiles / Units / Build / Paint |
| 1–6 | Select a card in the open panel |
| Tab | Overhead / 3D, including from text fields |
| F | Value heatmap |
| WASD / middle drag / wheel | Pan / pan / zoom |
| Alt + right drag | Rotate |
| V | Toggle random values 1–3 |
| I / Alt + left click | Pick brush, owner and value from a tile |
| Home | Center and reset the camera |
| Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z | Undo / redo / redo |
| Ctrl+S / Ctrl+Shift+S | Save / Save as |
| Ctrl+O / F5 | Load / Playtest |
| Enter | Commit the active text field |
| Escape | Finish text editing, close cards/help, or open/close island settings |

## Files and playtesting

**Save** stores the player-start province and a snapshot of each map kingdom's name and colours. The start is independent of roster indices, and saved kingdom definitions remain available if the game catalog later changes. Old maps with a player-faction field migrate to a marker in that faction; maps predating that field use Fern when available. **Save** writes a versioned JSON file in the game's `user://levels` folder by default. The first save opens the explorer; later Save/Ctrl+S updates the chosen file directly. Ctrl+Shift+S opens Save as. **Load** opens saved maps; the explorer can browse normal filesystem folders and remembers the current level's folder. Save as asks before overwriting a file. Invalid/unsupported files report an error and preserve the current draft. A `*` in the editor heading indicates unsaved changes.

**Playtest** requires a player-start marker on a connected owned kingdom of at least two provinces, and at least one opponent. Kingdoms/capitals are rebuilt on a separate copy using normal game rules: missing capitals are created and duplicate capitals in a connected kingdom are consolidated. This does not alter the editable draft. Disconnected land is allowed. Resources, terrain, units, map size and rules come from the authored level; opponent difficulty uses the saved gameplay preference. Newly generated editor maps start without encounter markers; add specific events through Events.

The match HUD says **Playtest**. Pause → Quit → **Return to editor** returns to the same draft, camera and history. The defeat screen also offers Return to editor. **Restart** repeats the authored starting position, including its seed and resources. Rules cannot change during an authored playtest; choose the rules when creating an island in the editor.

The editor's scene is temporarily detached during playtesting to isolate its camera, environment and renderer from the match. Board construction and transitions use the existing gameplay preparation path. The editor reuses `board_view.gd` and its shared rendering helpers; no duplicate terrain renderer or global appearance settings are introduced.

Implementation: `src/editor/level_document.gd` owns editable data, painting, history, format validation and gameplay conversion. `src/editor/level_editor.gd` owns tools, gestures and file dialogs. `src/app/app.gd` owns navigation; `game.gd` accepts an authored initial level and the ordinary seeded generation path remains intact.

Verification: `tests/test_level_editor.gd` covers all four sizes/both rules, format roundtrips, tile/decorations erasing, interpolated held strokes, random bounds/exact redo, real keyboard/focus events (Tab, numeric Enter, typing, WASD, wheel, middle drag), category/card shortcuts, sampling, quick save, live heatmap painting/undo and playtest restoration, file-dialog roundtrips/malformed-file isolation, restart and cleanup. Native previews: `-- --preview`, optionally `--sky`; screenshots include normal/heatmap layouts at both window sizes, help, the save explorer and Island settings. The runner includes this suite.

## Local multiplayer maps

Save your map, return to the main menu, then choose **Multiplayer → Map & rules → Load editor map…**. The picker starts in the editor's default saved-level folder and can browse any location. At least two factions must own land, and each faction must have a connected kingdom of two or more provinces. Factions may use any editor colours; Fern is not required. Up to six active factions become consecutive lobby seats while retaining their original colours by default.

The map fixes terrain, units, starting treasury, rules, size and seed. Configure local/computer control, names, colours, AI difficulty and turn order in the multiplayer lobby. Invalid or missing files show an error and cannot start a match. A loaded map is copied into the session; Restart uses that original snapshot, and Quit returns to the main menu. No editor file or draft is modified during play.

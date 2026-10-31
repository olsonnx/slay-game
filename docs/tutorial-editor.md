# Tutorial editor

Double-click **Tutorial Editor.cmd** in the project folder. It opens a separate authoring window, without opening the Godot editor. The launcher uses the project's Godot 4 executable from PATH, GODOT_EXE, or a Godot download in your Downloads folder. Python and Godot are already available on this machine; no extra Python packages are required.

If Godot is installed elsewhere:

```powershell
python tools/tutorial-editor/launch.py --godot "C:\path\to\Godot.exe"
```

You can also run `godot --path . --script tools/tutorial_editor.gd` directly. Open a particular tutorial with `python tools/tutorial-editor/launch.py --file "C:\path\lesson.tutorial.json"`.

## A quick workflow

1. Use **File > Start from template** for a built-in chapter or **File > New tutorial** for a blank sequence.
2. Switch to **Edit level**. Choose terrain, kingdoms, armies, or structures from the palette. Click or drag to paint; right-drag to remove objects. Water removes a tile. Place land, assign its kingdom, then add capitals and armies. Wheel zooms and middle-drag pans.
3. **Edit level** edits the whole topic. Brush changes are saved to the topic map and applied to every prepared exercise position. Untouched exercise-specific units, objects, and terrain stay as authored. Opening gold applies across the topic too. Switching steps keeps the same topic level in the editor.
4. Switch to **Write steps**. Write the heading, explanation, and objective in Text, then choose what advances the step in Goal. Optional camera and highlighting settings and advanced IDs/grouping are collapsed initially.
5. Add board conditions in Conditions, or scripted actions in Opponent. Select a row and use **Update selected** to apply form edits. Use Course for the title, category description and opponent mode. Fern (owner 0) is the player.
6. **Play / Check** offers play from the beginning, play from the selected step, a simulated board preview, and script validation. Return from playtest to continue editing.
7. **Save** writes your tutorial JSON. **File > Use in game** installs it for its chosen category. Import, recovery, and Save as are also in File. Duplicate, reorder, and delete are in **Step actions** beneath the sequence.

You can still import a level editor JSON using **File > Import level**. Import replaces the base map and removes prepared positions while retaining step text and target coordinates. Check those targets before playtesting.

## Goals and conditions

For an explanation-only step, choose **No condition (read and continue)** under **Goal > Advance after**. The player advances by clicking Continue. Moves, purchases, spells, and End turn stay blocked while the text is open; inspection and camera controls remain available. Selecting this option clears previous action and board requirements; Undo restores them. Use **Continue after board conditions** when Continue should stay locked until additional conditions pass.

| Goal | Behavior |
| --- | --- |
| read (No condition) | Let the player read the explanation and click Continue when ready. No action or board condition is required. New steps use this option. |
| continue | Show a Continue button. Additional conditions must pass before it is enabled. |
| any | Allow free play and advance when the board conditions pass. Requires at least one condition. |
| recruit, move, build, spell | Wait for that committed action; optionally constrain the tile, source, rank, building, spell or move result. |
| road | Wait for a structure-to-structure or structure-to-road connection; the source field names its starting structure. |
| rename_settlement | Wait for the player to name the city or capital on the target tile using its editable title. |
| end_turn | Wait for a completed round, including enemy orders and income/upkeep. |
| finance, status | Wait until the gold tooltip or the specified status icon tooltip opens. Status uses its effect ID (for example `income_bonus` or `stainless_steel`). |
| kingdom, animal | Wait for selection of a friendly kingdom or inspection of a predator. |
| select, inspect, develop, entrench, relocate_capital, event, view, heatmap, stats | Wait for the corresponding game action. Capital relocation waits for confirmation and payment; event waits for a resolved encounter choice. Heatmap and Stats can require on/open or off/closed. |

**Keep details open until Continue** is available for inspection and Stats. It lets the player read the opened panel before advancing.

**Allow only the requested action** prevents unrelated purchases and moves. Inspection, camera controls and Stats remain available. Turn it off when the player should be free to find their own solution. Continue and any always permit free play.

Additional conditions combine with **all** or **any**. They are also required in addition to the selected action. Conditions include:

- Province owner equals a faction (-1 neutral, 0 player, 1 Ember, 2 Tide, 3 Ochre, 4 Aster, 5 Cove).
- Unit rank, province value, gold, mana, round, territory, or faction income is at least a specified number.
- A province has a particular building, is clear of trees/graves, or is entrenched by a faction.
- A specified army is cut off from every supporting kingdom, or a target tile has no army. These conditions verify isolation and its next-turn result.
- A specified enemy has no surviving capital. Use faction -1 for every opponent; isolated land does not prevent victory.

Gold uses the kingdom at the selected tile; leave the tile blank to total the faction's treasuries. Mana, round, territory and income do not need a tile. Owner conditions use Value as the expected owner; unit/mana/gold/territory/entrenchment conditions use Faction. Unused value fields on clear, entrenchment and victory are ignored.

For an open-ended final battle, choose **any**, add a **victory** condition for faction **-1**, select **ai** opponents, and enable **Require opponent defeat to finish**. For a specific lesson, use an action such as **recruit**, a target tile, and the required unit tier.

## Reading sub-steps

For an action objective that needs reading first, enable **Text > Require Continue before actions**. The player must acknowledge the main text and any reading sub-steps before the requested action is available. Continue unlocks the action; completing the action still advances the objective. Retry restores the reading lock.

Open **Text > Extra reading sub-steps** on a main step. **Add** creates another reading page with an optional heading and explanation. Use the page selector to edit or preview a page, and **Page actions** to reorder or remove it. Up to 20 extra pages can belong to one step. Undo/redo and saving include these pages, and duplicating a step copies them independently.

The player sees the main explanation first, then clicks **Continue** through each extra page. After the last page, a reading-only step finishes; an action step then waits for its normal objective. Board conditions apply to the objective after the reading sequence. Retry restarts the exercise's text sequence. Extra pages stay out of both the editor's main step list and the in-game objective checklist.

## Target areas

In **Goal**, enable **Accept any hex in a selected area**, then choose **Select area on map**. Click or drag to add hexes; right-click or right-drag to remove them. **Done** or Escape finishes selection. For a recruitment lesson, include the capital and the neighboring tiles where recruitment should count. Any one legal recruitment in the selected set satisfies the location requirement. Army rank, other action options, and additional board conditions still apply.

The editor and in-game lesson highlight the selected region with a light fill and a continuous outer boundary. Selected neighboring hexes share an outline; disconnected patches and unselected holes retain their own boundaries. In game, the tutorial uses a thick gold band beneath the normal movement-range outline, so both remain visible when their edges overlap. Area strokes support undo/redo, and the selection is saved with the tutorial. Switching back to a single target keeps the area's first hex. Single-target and unrestricted existing lessons keep their behavior. Conditions and scripted opponent orders continue to use individual tiles.

Portable JSON stores an area as `"target": null, "targets": [[q, r], [q, r], ...]`. Areas require at least one unique coordinate. **Check entire script** stops at an area with multiple choices and asks for a manual playtest; it does not pick an arbitrary path. **Play selected step** can start immediately before that objective. Later steps in the same exercise need a reproducible preceding path, as with other free choices.

## Opponent orders

Orders run in sequence on the selected End turn step, grouped by faction turn. Factions 1 through 5 must exist on the loaded map. Supported orders: move, recruit, build, spell, entrench and develop. Move uses From and To; other orders use To. Parameter is a unit rank (1/2/3), building (`city`, `tower`, `bridge`), or spell (`trailblaze`, `summon`, `shatter`) as appropriate.

All orders use the real costs, movement, defense and upkeep rules. An impossible order reports a failure in playtest; Retry restores the current checkpoint. No units or resources are secretly injected to complete an objective.

## Saving and installation

- **Save / Save as** writes a portable `slay-tutorial` version 1 JSON document, with an embedded `slay-level` map. Invalid input reports a specific step error and preserves the last saved file.
- **Undo / Redo** retains up to 80 editing snapshots. Draft changes autosave after a short pause to `user://tutorial-editor-autosave.json`; **Recover autosave** restores them after a crash. Save the recovered draft to a normal file.
- **Use in game** writes `tutorials/<topic>.json`, where the topic is `armies`, `encirclement`, `economy`, `construction`, `logistics`, `magic`, `exploration`, or `practice`. It asks before replacing a category and backs up the previous installed file as `.json.bak`. It does not publish the other categories.
- Remove the installed category JSON to return to the built-in lesson. The export preset includes `tutorials/*.json` in game builds. Re-export an existing executable to include edits.

The templates contain focused exercises with freely chosen placements and a final normal match. **Check script** reports a manual-playtest boundary when a goal allows multiple choices. **Play this step** can jump directly to the first objective of any prepared exercise, even when earlier exercises had free choices. Later objectives still need a reproducible preceding path. Script checking proves one authored path, not every possible decision or AI outcome. Long explanations scroll inside the in-game card.

Give consecutive objectives the same **Exercise group** to display them together as a persistent checklist. Leave it blank for independent objectives. **Required actions** counts distinct target tiles; **Allow End turn** lets the player ready armies during that goal. Prefer separate End turn objectives when readiness is part of the lesson. **Run wildlife** advances the normal predator phase on that End turn; leave it off for unrelated exercises. Matching restrictions in built-in templates are summarized in the Goal tab and can be cleared when changing an objective. Board conditions check the committed result; restrictions such as previous owner or predator check the state before the action.

Each prepared exercise stores an embedded `setup` level on its first objective. The runtime loads it only on entering that exercise, then captures a full retry checkpoint. Within an exercise, resources and actions use normal rules. Importing a map removes these positions rather than letting them silently override the import. Edit the topic in Edit level, or import a level made in the full level editor. Basic painting uses the same terrain, ownership, structure and army rules as that editor. Each brush operation is also applied to the prepared positions, preserving their untouched contents. A complete brush stroke is one undo action across all positions; edits use the normal tutorial autosave and portable JSON format.

## Verification

`tools/export_tutorial_examples.gd -- --update-examples` refreshes all eight portable chapter examples. Run the script without the flag to verify that the shipped examples match the current lessons. `tests/test_logistics_tutorial.gd` plays every guided chapter through real game commands; `tests/test_tutorial.gd` also checks menu completion, retry, cancellation, saved progress and the final practice match.

Run `godot --headless --path . --script tests/test_tutorial_editor.gd`. The suite covers serialization, invalid-file preservation, predicates, simulation, installation loading, UI editing, undo/redo, map import, autosave recovery, real game playtests, manual/state/action conditions, normal AI, and starting from an authored checkpoint. Add `-- --preview` with a graphical renderer to save UI screenshots under `artifacts/tutorial-editor-*.png`.

Keyboard shortcuts: Ctrl+S saves, Ctrl+Shift+S opens Save as, and Ctrl+Z / Ctrl+Y undo and redo when a text editor is not consuming those keys.

Reading objectives of kind **inspect**, **stats**, or **finance** can require confirmation. The normal interaction opens the information first; **Continue** then acknowledges it without dismissing the lesson early.

## Authoring workspace

Drag the dividers beside the step list and inspector to give the map or forms more room. Long player prompts scroll in the preview. **Reset view** fits the map again after zooming or panning; the map heading distinguishes the starting map from a simulated step checkpoint.

Goal menus use readable labels while saved JSON keeps the existing action IDs. Condition and opponent forms show fields relevant to the chosen rule. **Add** creates and selects a row; **Update selected** applies further edits to that same row. Remove and reorder controls are available when a selected row supports them. Selecting another step clears the row forms.

Use **Pick** beside a coordinate field, then click a tile. The map displays the field being picked; Escape, switching tabs, or selecting another step cancels picking. **Clear** removes an optional coordinate. Step actions and undo/redo reflect the available actions; hover over toolbar buttons for guidance and shortcuts.

# Tutorial editor

Double-click **Tutorial Editor.cmd** in the project folder. It opens a separate authoring window, without opening the Godot editor. The launcher uses the project's Godot 4 executable from PATH, GODOT_EXE, or a Godot download in your Downloads folder. Python and Godot are already available on this machine; no extra Python packages are required.

If Godot is installed elsewhere:

```powershell
python tools/tutorial-editor/launch.py --godot "C:\path\to\Godot.exe"
```

You can also run `godot --path . --script tools/tutorial_editor.gd` directly. Open a particular tutorial with `python tools/tutorial-editor/launch.py --file "C:\path\lesson.tutorial.json"`.

## A quick workflow

1. Choose a category and **Load template**, or use **New** for a blank sequence. All seven current topics are also available in `tools/tutorial-editor/examples`.
2. **Import map** loads a JSON map saved by the game's level editor. It embeds a copy, so the tutorial does not depend on the original file staying in the same folder. Existing step text and coordinates are retained; exercise-specific prepared positions are removed so every exercise uses the imported map. Validate the targets against it.
3. Use **Course** for the title, category description, opening gold and opponent mode (scripted orders, normal AI, or waiting). Fern (owner 0) is the player. Use **Text** for each step's heading, explanation, objective and optional highlighted tile.
4. Set the **Goal**. Use Pick and then click a map hex to assign a target or source. Scroll to zoom; middle-drag to pan. Water coordinates can be selected as bridge targets.
5. Add board conditions in **Conditions**, and any scripted enemy actions in **Opponent**. Add/Update commits a condition or order row; editing its form alone does not change the row.
6. **Preview step** shows the board after simulating preceding steps. **Check script** checks the complete specified path. **Playtest** starts at the beginning; **Play this step** starts at the simulated checkpoint. Return to the editor without changing your draft.
7. **Save** your tutorial JSON. When ready, **Use in game** installs it for its chosen category. The next time you select that category from Tutorial in the game, it loads your version.

## Goals and conditions

| Goal | Behavior |
| --- | --- |
| continue | Show a Continue button. Additional conditions must pass before it is enabled. |
| any | Allow free play and advance when the board conditions pass. Requires at least one condition. |
| recruit, move, build, spell | Wait for that committed action; optionally constrain the tile, source, rank, building, spell or move result. |
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
- A specified enemy has no surviving capital. Use faction -1 for every opponent; isolated land does not prevent victory.

Gold uses the kingdom at the selected tile; leave the tile blank to total the faction's treasuries. Mana, round, territory and income do not need a tile. Owner conditions use Value as the expected owner; unit/mana/gold/territory/entrenchment conditions use Faction. Unused value fields on clear, entrenchment and victory are ignored.

For an open-ended final battle, choose **any**, add a **victory** condition for faction **-1**, select **ai** opponents, and enable **Require opponent defeat to finish**. For a specific lesson, use an action such as **recruit**, a target tile, and the required unit tier.

## Opponent orders

Orders run in sequence on the selected End turn step, grouped by faction turn. Factions 1 through 5 must exist on the loaded map. Supported orders: move, recruit, build, spell, entrench and develop. Move uses From and To; other orders use To. Parameter is a unit rank (1/2/3), building (`house`, `tower`, `bridge`), or spell (`trailblaze`, `summon`, `shatter`) as appropriate.

All orders use the real costs, movement, defense and upkeep rules. An impossible order reports a failure in playtest; Retry restores the current checkpoint. No units or resources are secretly injected to complete an objective.

## Saving and installation

- **Save / Save as** writes a portable `slay-tutorial` version 1 JSON document, with an embedded `slay-level` map. Invalid input reports a specific step error and preserves the last saved file.
- **Undo / Redo** retains up to 80 editing snapshots. Draft changes autosave after a short pause to `user://tutorial-editor-autosave.json`; **Recover autosave** restores them after a crash. Save the recovered draft to a normal file.
- **Use in game** writes `tutorials/<topic>.json`, where the topic is `armies`, `economy`, `construction`, `conquest`, `magic`, `exploration`, or `practice`. It asks before replacing a category and backs up the previous installed file as `.json.bak`. It does not publish the other categories.
- Remove the installed category JSON to return to the built-in lesson. The export preset includes `tutorials/*.json` in game builds. Re-export an existing executable to include edits.

The templates contain focused exercises with freely chosen placements and a final normal match. **Check script** reports a manual-playtest boundary when a goal allows multiple choices. **Play this step** can jump directly to the first objective of any prepared exercise, even when earlier exercises had free choices. Later objectives still need a reproducible preceding path. Script checking proves one authored path, not every possible decision or AI outcome. Long explanations scroll inside the in-game card.

Give consecutive objectives the same **Exercise group** to display them together as a persistent checklist. Leave it blank for independent objectives. **Required actions** counts distinct target tiles; **Allow End turn** lets the player ready armies during that goal. Prefer separate End turn objectives when readiness is part of the lesson. **Run wildlife** advances the normal predator phase on that End turn; leave it off for unrelated exercises. Matching restrictions in built-in templates are summarized in the Goal tab and can be cleared when changing an objective. Board conditions check the committed result; restrictions such as previous owner or predator check the state before the action.

Each prepared exercise stores an embedded `setup` level on its first objective. The runtime loads it only on entering that exercise, then captures a full retry checkpoint. Within an exercise, resources and actions use normal rules. Importing a map removes these positions rather than letting them silently override the import. Change terrain in the level editor, then import the map; this tool remains a sequencer rather than a map painter.

## Verification

Run `godot --headless --path . --script tests/test_tutorial_editor.gd`. The suite covers serialization, invalid-file preservation, predicates, simulation, installation loading, UI editing, undo/redo, map import, autosave recovery, real game playtests, manual/state/action conditions, normal AI, and starting from an authored checkpoint. Add `-- --preview` with a graphical renderer to save UI screenshots under `artifacts/tutorial-editor-*.png`.

Keyboard shortcuts: Ctrl+S saves, Ctrl+Shift+S opens Save as, and Ctrl+Z / Ctrl+Y undo and redo when a text editor is not consuming those keys.

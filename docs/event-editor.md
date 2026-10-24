# Event Editor

Double-click **Event Editor.cmd** in the project folder. Python and the same Godot installation used by the Tutorial Editor are sufficient. You can also open **Level editor → Events → Create events…**.

The editor changes event data through forms. You do not need to write code or edit JSON. The game reads the saved pack at startup. In an open level editor, press **Reload** after saving; an already running match keeps its current event catalogue until the game is restarted.

## Create an event

1. Choose an existing event from the library and click **Duplicate**, or choose **New**. All fifteen built-in events have editable templates, including their conditional and random behavior.
2. Select the event row in **Story & outcomes**. Set its unique lowercase ID, title, story, **Event weight** and rule mode. Higher weights make an event more likely: weight 10 is ten times as likely as weight 1 in the same draw. Random maps select unused event types first; after every type has been used, remaining markers allow weighted random repeats. This means a map large enough to use every type will include even rare events. A weight of zero makes it available for authored maps without including it in random draws. Disabling an event excludes it from eligible encounters.
3. Add requirements to the event, then add up to four choices. Select each choice to edit its caption, effect tooltip, gold/mana costs and AI preference. Higher AI preference wins among available choices.
4. Add weighted outcomes under a choice. Weights of 60 and 40 mean a 60/40 split. An outcome can have several ordered effects. A choice with one outcome is deterministic; an outcome with no effects deliberately does nothing.
5. Use **Preview & test**. Set the sandbox's gold, mana, unit ranks, trees and other conditions. Preview uses the actual game dialog. Click a choice to run the same effect code the game uses and compare the before/after state. Change the random seed to repeat or vary the result. **Test every eligible outcome** runs each branch independently on a fresh sandbox.
6. Click **Save to game**. The event becomes part of `resources/events/custom_events.json`. Restart the game, or press **Reload** in the level editor's Events panel, to use it.

Saving a built-in event's original ID overrides that event. Duplicating first creates an independent encounter. **Remove override / event** restores the built-in version or removes a custom event. Referencing an event from an authored map requires that its definition remains installed.

Unsaved edits are marked with an asterisk. Undo/Redo covers field edits, additions, removal and reordering. Switching events or closing asks before discarding changes. **Ctrl+S** saves.

## Conditions and alternate stories

Requirements on the same row are combined with AND. Every requirement can be inverted with **NOT**.

Event requirements control whether an encounter is eligible. An ineligible marker draws an eligible replacement, following the normal encounter system. Choice requirements disable a button. Outcome requirements select the applicable branches before their weights are normalized. If an eligible outcome cannot execute, the whole choice is disabled rather than silently changing its advertised odds. Events with no usable choice are ineligible.

Available conditions cover connected kingdoms, recruitment space, trees, forest income coverage, multiple armies, Knights, other living factions, spare rebel identities, existing steel landmarks, income trading, local gold/income thresholds, mana thresholds/storage, arriving army rank, temporary effects and mana-source terrain. The duel-prize condition covers a rank gain or an existing treasury for a Knight's reward.

**Conditional stories** replace the story and choices when their requirements match. The first matching story wins. Selection happens before reveal and stays fixed while the player chooses. This supports the lumberjack's overgrown-forest variant and other context-dependent encounters. Move variants up/down to change their priority.

## Effect reference

| Effect | Settings and behavior |
| --- | --- |
| Give / take local gold | Signed minimum and maximum; equal values are fixed. Can use the event's gold roll made once at reveal. |
| Change treasury by percent | Signed percent; -100 empties the local treasury. |
| Give / take mana | Signed minimum/maximum; storage capacity still applies. Requires Modern rules. |
| Kill arriving army | Uses normal unit death/grave behavior. |
| Promote army | One or two ranks, capped at Knight; configurable gold instead when already a Knight. |
| Recruit free army | Scout, Soldier or Knight, ready or spent, on a free province in the local kingdom. |
| Clear kingdom trees | Configurable gold per tree; optional no-payment rule when trees block over half the potential income. |
| Disband faction armies | Configurable recruitment-price refund, including supported units on bridges. Refunds route to their home treasuries. |
| Neutralize friendly land | Radius zero to four; removes friendly armies, capitals and ordinary buildings. Landmarks survive. |
| Create rebel kingdom | Radius zero to four; transfers passable provinces and armies to an unused faction identity. |
| Construct permanent landmark | Signed fixed/random local income, signed fixed/random mana regeneration, and optional steel discount. All rewards share one indestructible, conquerable site. |
| Create / remove mana source | Changes the encounter province's mana-source terrain. Combine with a landmark to reproduce the altar. Requires Modern rules. |
| Temporary effect | Grant/remove the next free spell or Trailblaze. Normal consumption rules apply. Requires Modern rules. |
| Ordinary building | Construct a house or tower on a province without a building/capital. These retain ordinary destruction rules. |
| Province value | Signed change, bounded by the game's normal minimum/maximum. |
| Clear province terrain | Removes trees/graves with the normal tree-clearing reward. |

Effects run in the order shown in the tree. Death, disbanding and territorial changes must come last. Use one structure effect per outcome; put all permanent rewards into that one landmark. Choice costs are paid once before the selected outcome. The editor and game reject invalid ranks, ranges, weights, impossible recruitment, overspending and unknown effects.

## Artwork and text

**Choose / copy painting…** copies a PNG, JPEG or WebP into `assets/paintings/events/` and assigns its project path. Set its title and artist for the hover caption. Blank artwork uses the game's default painting. Newly copied artwork can be previewed immediately without opening Godot's project editor.

Story, caption and tooltip tokens:

| Token | Value |
| --- | --- |
| `{gold}` | Gold sampled once at reveal using the event's reveal-roll minimum/maximum. Set a nonzero maximum before enabling this reward mode. |
| `{trees}` | Current local tree count. |
| `{tier}` | Arriving army's current rank. |
| `{treasury}` | Current local treasury. |
| `{scout_upkeep}`, `{knight_upkeep}` | Current wages, including discounts. |

Outcome messages additionally support `{amount}` (the latest gold, mana, clearance or landmark-income amount), `{refund}` (disband refunds), and `{cleared}` (cleared trees). Use concise choice hints to state costs, odds and lasting consequences. Long event dialogs scroll within the window. Custom event text participates in the normal translation lookup; after saving events, run `python tools/localization_catalog.py` when preparing translation packs. Tokens are substituted after translation.

## Import, export and recovery

**Export** writes the selected event as a versioned JSON pack. **Import** opens a pack as drafts; each imported event is installed only when you choose **Save to game**. Artwork is stored separately: include the referenced images when sharing a pack, or assign new artwork after import.

Saving validates the complete pack, writes a temporary file, preserves the previous pack as `.json.bak`, then replaces the pack. An invalid installed pack is left untouched and saving is blocked until it is repaired or restored. Backups and temporary files are ignored by Git; the actual pack and images can be committed normally.

For a source-project launch, use `python tools/event-editor/launch.py --check` to check engine discovery, `--file path/to/pack.json` to import on opening, or `--godot path/to/Godot.exe` to select an engine explicitly. Exported game builds must include the event JSON pack and referenced artwork in their export settings; the editing tool is intended for the source project.

The `tools/event-editor/examples/builtin-templates.json` pack contains independent copies of all existing events for import and inspection. Classic map generation continues to omit encounter markers; the Modern-only setting controls eligibility when a marker is actually encountered.

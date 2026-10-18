# Keyboard bindings

Options → Controls is available from the main menu and paused gameplay. Click an action's current key, then press a replacement. Changes apply immediately and save to `user://key_settings.cfg`. Escape cancels capture, and Restore defaults reinstates the full default layout. The action list scrolls inside the existing 600 px options panel, retaining the minimum 960 × 620 window support.

| Action/context | Default |
| --- | --- |
| Open Recruit / Build / Spells | Q / E / R |
| Recruit Scout / Soldier / Knight | Q / E / R, left to right |
| Build Tower / House / Bridge | Q / E / R, left to right; Classic has two choices |
| Spells: Trailblaze / Summon / Shatter | Q / E / R |
| Develop inspected province | G |
| Change top-down / 3D view | Tab |
| Value heatmap | F |
| End turn | Space |
| Cancel action / pause | Escape |
| Hold to speed up | Ctrl |
| Camera pan forward / left / backward / right | W / A / S / D |

The three left-to-right choice bindings are shared by recruitment, building and spells. While a shop is visible, matching choice keys take priority over menu-opening shortcuts. Selecting a card follows the normal button callback and existing targeting mode; it does not immediately place a unit/building or cast a spell. An unavailable Classic third building is ignored rather than opening another menu. Echo/repeated key events do not repeatedly open or select cards.

The heatmap is an independent view toggle; see `value-heatmap.md`. Older control files with a custom F assignment preserve that action and receive a free heatmap fallback, displayed in Controls. The normal default and Restore defaults use F. Development similarly defaults to G; older custom G bindings retain their action and receive a free development fallback. Development only acts while a province inspector is open and commands are unlocked.

Bindings use one physical keyboard key per action, keeping hand positions consistent on alternate keyboard layouts. Chords and additional alternate bindings are not implemented. Conflicts are rejected with an explanation: menu-opening actions can share keys with contextual choices, while conflicting keys in the same context, or with global camera/view/cancel/speed/turn actions, are rejected. Escape remains reserved as a menu/capture-cancellation fallback even if the gameplay Cancel action is rebound. To return a rebound Cancel action to Escape, use Restore defaults. Mouse gestures and the loading turn-button speed hold retain their existing controls.

`src/settings/key_settings.gd` owns defaults, physical event matching, held-key queries, conflict checks, validation, load/save and change notifications through the `Keys` autoload. All settings are loaded together before resolving malformed/conflicting overrides back to defaults, so valid saved permutations survive. Missing files leave defaults. Options reports save failures without discarding the live setting.

`src/ui/controls_view.gd` owns scrollable action rows and key capture. Capture works while paused and consumes keyboard input before focused UI can activate it. Escape, focus loss, switching tabs or leaving Options cancel capture. The view disables its input callback outside capture. `game_input.gd` handles contextual card selection and consumes the view key before Godot's default Tab focus navigation in gameplay. `board_view.gd` queries rebound pan keys; `playback_speed.gd` uses the rebound hold key and clears holds on a binding change.

Help rows, main action tooltips, the view/turn buttons, shop-close tooltip and open card tooltips update on binding changes. Shared text sizing refreshes the previous unwrapped minimum before assigning a narrow width, preventing a long new description from retaining its old one-line width.

Verification: the complete **21-suite run passed**, with 49 key checks at that point. The final targeted `tests/test_keys.gd` passed **50 checks**, including defaults, physical positions, conflict rejection, persistence and valid saved permutations, malformed settings, all unit/build/spell choices, changed and old shortcuts, live tooltip updates, speed/cancel rebinding, paused capture, cancellation, defaults restoration and an opening key overlapping an inactive spell-row key. UI layout passed 104 checks, playback speed 30, and the editor scan was clean. Native previews: `artifacts/menu_options_controls_small_water.png` and the updated `artifacts/ui_help.png`. `tools/menu_preview.gd -- --options --controls --small-window --water` reproduces the Controls preview. Tests use an isolated config path and restore the original in-memory bindings, so they do not alter the user's saved controls.

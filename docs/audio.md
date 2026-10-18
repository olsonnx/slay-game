# Audio system

`Sound` is an autoload so voices and mix settings survive a scene restart. Game code requests semantic IDs; file paths and per-cue mixing live only in `resources/audio/sounds.tres`.

| Cue | Asset | Trigger |
| --- | --- | --- |
| `ui_hover` | `assets/sfx/ui_hover.mp3` | Entering an enabled UI button |
| `ui_click` | `assets/sfx/ui_click.mp3` | UI activation, keyboard activation, friendly tile selection, or issuing a move |
| `ui_close` | `assets/sfx/ui_close.mp3` | Closing a menu or cancelling an active action |
| `action_place` | `assets/sfx/action_place.mp3` | Successful recruitment, upgrade or construction; movement/attack/merge arrival; AI recruitment and construction |

Invalid placements, disabled controls, idle mouse movement over map tiles and no-op cancellation are silent. Cancelled movement never emits arrival audio. Placement is tied to the animation's completion signal, so audio follows what is visible rather than the earlier rules commit.

## Adding a sound

1. Import the asset into `assets/sfx/`.
2. Add a `sound_cue.gd` Resource to `resources/audio/sounds.tres`, with its `streams`, bus, gain, cooldown, voice cap and priority.
3. Give it a unique key in the bank's `cues` dictionary.
4. Call `Sound.play(&"your_id")` at the meaningful gameplay event, or use `Sound.bind_button(button)` for normal UI feedback. The bank and cue fields can be edited in Godot's Inspector.

`streams` supports alternative recordings of the same cue, selected randomly. `pitch_min` and `pitch_max` support optional variation (both remain 1 for the supplied effects). Future cues do not need new players or file-loading logic.

## Mixing and lifecycle

The bus layout separates **Master**, **UI**, **SFX**, **Ambience** and a reserved **Music** bus. One-shot cues use the bounded voice pool. Each board owns two looping players on the independent **Ambience** bus, which defaults to -6 dB (about 50% on the slider). The close layer uses `assets/sfx/ambient/nature_closeup_ambience.ogg`. It is silent at camera size 14 and above, growing louder toward the closest size of 8, with a quiet -26 dB maximum before bus volume. Nine central-view samples scale its gain by land coverage, excluding bridges. The overview layer uses `assets/sfx/ambient/nature_zoomedout_ambience.ogg` at a -34 dB maximum. It only starts beyond the greater of camera size 30 or 75% of the map's maximum zoom, reaching full gain at maximum zoom. It plays over land and water. The middle zoom range has neither layer. Both use 1.5-second fades. Hidden/inactive boards and island transitions fade to silence; freeing the board removes both players. Ambience continues while paused, respects overall/ambience volume and mute, and restarts with a fade after unmuting. Game-effect volume controls one-shots independently. Tuning lives in `src/audio/land_ambience.gd`.

The manager reuses 12 `AudioStreamPlayer` voices. Per-cue caps and cooldowns keep simultaneous faction actions from stacking excessive copies. When full, higher-priority cues can replace lower-priority voices; hover feedback cannot interrupt important cues. UI hover has a single voice and never replaces itself while playing. Each play resets stream, bus, gain and pitch, preventing settings from leaking between cues.

**Pause → Options → Audio** exposes overall, interface, game-effect and ambience volume plus master mute. The main menu opens the same Options screen. Changes persist in `user://audio_settings.cfg`; slider changes are batched after 250 ms, with pending changes flushed on exit. Older settings files without an ambience value keep the bus default. The audio manager processes while the game is paused so UI sounds and preference saving remain active. Save failures emit a signal and show a notice. Mute stops active sounds and blocks new playback. Zero-volume categories also suppress playback. Unknown IDs fail with a warning rather than crashing gameplay.

`tests/test_audio.gd` checks assets, buses, caps, priorities, binding, mute, volume persistence and actual game triggers. Its temporary settings file is separate from the player's preferences.

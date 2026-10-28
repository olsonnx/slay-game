# Player settings

Options is shared by the main and pause menus. Changes apply immediately and are
saved automatically; language changes take effect on the next launch. Pages
scroll independently, while Back and the category reset stay accessible.

| Tab | Controls |
| --- | --- |
| Audio | Overall, interface, effects, ambience and music volumes; master mute; mute when unfocused; output device |
| Video | Windowed/fullscreen; 720p through 4K; VSync; active and unfocused FPS limits; MSAA; shadows; contact shadows; depth of field; brightness; island background; animated menu |
| Game | Camera following; island transitions; movement playback speed; pause on focus loss; pan, rotation and zoom sensitivity; inverted scroll and vertical rotation |
| Controls | Rebindable action, camera and contextual keys; restore key defaults |
| Interface | UI scaling; tooltip delay; FPS display; reduced motion; clear movement indicators; internal border visibility; language |

UI scaling applies to menus and the HUD together. The requested range is 75–150%.
Enlargement automatically stops at the largest size that preserves the existing
960x620 logical interface area. The applied percentage appears beneath the slider
and updates when the window changes size. This prevents the scale setting from
making its own recovery controls inaccessible.

Fullscreen resolution controls 3D rendering quality; interface text remains
sharp at the output size. VSync can limit FPS below the requested frame cap.
The background cap never increases a lower active cap. Contact shadows require
shadows. Depth blur can be disabled independently, and brightness changes scene
exposure rather than fading the interface.

Reduced motion stops decorative menu movement, animated loading tiles, island
transitions and automatic camera pans. Playback speed affects presentation only;
rules and AI decisions are unchanged. The speed-up hold remains a fixed 6x and
releasing it restores the chosen normal speed. Focus-loss pause applies to solo
and local games; online games keep running.

Temporary focus muting does not overwrite the saved master-mute preference.
Missing audio output devices fall back to the system default. Existing volume
settings and key bindings are retained when loading older configuration files.

Restoring a tab requires confirmation and affects only that category. Profiles,
statistics, tutorial completion, authored maps, replays and other tabs are kept.
The Controls tab retains its dedicated key-reset button. Video reset also restores
the authored art defaults if an older configuration selected an experimental look.

The plastic-tile, atmospheric-lighting-style and alternate-water comparison
switches were removed from the player menu. Their rendering support remains for
the development tools and older configuration files. Difficulty and kingdom
selection remain in match setup rather than being duplicated here.

## Implementation and verification

Preferences live in the existing Video, Gameplay and Sound settings owners.
New values are validated before application and again on loading. Defaults do
not delete player data. New settings tests cover persistence, malformed values,
frame-limit focus changes, audio focus restoration, real camera movement and
depth blur, reduced motion, scrollable pages and isolated category resets.

Native screenshots under `artifacts/settings-*.png` cover every tab, scrolling,
enlarged UI and a 960x620 window. Reproduce with `tools/settings_preview.gd`.
Focused regression logs are under `artifacts/settings-test_*.log`. The existing
broad game-suite failures from the playtest preparation report are separate;
the complete regression runner was not run for this change.

Thirteen focused suites passed (1,807 checks) for the settings update, covering
display, menus, audio, keys, music, playback speed, depth blur, lighting, tile
materials, UI layout, startup and the new settings tests. The updated package is
`builds/Slay-and-Reign-0.2.0-closed-05-windows-x64.zip`.

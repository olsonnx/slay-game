# Widescreen display and music player

The base viewport and default window are 1280x720. Canvas scaling uses Expand,
preserving proportions and filling the available screen rather than adding side
bars. Available resolutions are 1280x720, 1600x900, 1920x1080 and 2560x1440.
Saved 960x620 and 1280x820 preferences migrate to 1280x720; manually resized
windows can still use the existing 960x620 minimum.

Fullscreen remains at the monitor's native desktop mode. The enabled Resolution
selector controls the 3D rendering size while UI text stays at output resolution.
The scene scale follows window size changes, resets in windowed mode and also
applies to the decorative menu viewport. Wider aspect ratios gain visible area.

The top-right music-note button opens the current song, pause/resume and next
controls. All eight supplied tracks play in filename order and wrap. Music
continues between menus and matches and during pause; skipping while paused
does not resume playback. Options > Audio includes a saved Music slider. See
[audio](audio.md) for lifecycle and routing.

## Validation

Seven headless suites pass: display (12), music (18), menus (110), audio (96),
localization (32), startup (117), UI layout (576): 961 checks total. New suites
are registered in the full runner. Version metadata and the localization catalog
also pass their checks. The earlier broad game-suite failures recorded in the
playtest preparation report were outside this change and were not rerun.

Native Forward+ / Direct3D 12 previews on a 1920x1080 display confirmed windowed
1280x720, fullscreen 720p scene scaling (2/3) and fullscreen 1080p scaling (1).
Reviewed menu/player, gameplay and both options-page screenshots under
`artifacts/music-*.png`; the view fills the screen without side bars. The helper
is `tools/display_music_preview.gd`. Other monitors remain unverified.

Follow-up: the music button shares the top toolbar row, and loading covers hide
both the button and popup without interrupting music. Music (21), startup (129)
and UI layout (576) checks pass after this adjustment. Native captures confirm
the loading screen has no music button.

Updated release export: `builds/Slay-and-Reign-0.2.0-closed-04-windows-x64.zip`.
Use this archive instead of earlier builds for the latest music controls.

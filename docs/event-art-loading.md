# Event artwork loading

Full-resolution paintings caused synchronous image decoding and texture upload
when an event opened. Collection discovery also loaded the original a second
time to validate its reveal. JPEG file compression did not address the decoded
texture size: several paintings are thousands of pixels across.

Events now use prebuilt **1024 × 512 WebP banners**, encoded at quality 90.
The builder applies the existing focal-point crop without stretching. Full-size
sources remain untouched for the Collection viewer. Twenty banners, including
the fallback, total about **2.6 MiB** on disk and **40 MiB** of RGBA texture data;
the nineteen current events account for 38 MiB.

Application startup loads and renders each small banner in a private viewport
behind the existing loading cover, yielding between images. Strong texture
references and retained specimens keep both textures and their shader variant
ready. New matches reuse the completed preparation; if the installed event
catalogue changes, the match loading screen prepares the new set. Collection
discovery validates the already prepared banner and retains the original source
path as the unlock identity. It does not decode the original during the reveal.

New or edited crops without a generated banner safely use the existing original
image path and shader crop. Rebuild previews after changing source artwork or
focal points:

```powershell
godot --headless --path . --script tools/build_event_previews.gd
godot --headless --editor --path . --import --quit
```

The mapping is `resources/art/event_previews.json`. Export presets explicitly
include artwork JSON so packaged games use the same small resources. No export
or ZIP was regenerated for this change.

The same builder also creates uncropped Collection thumbnails with a maximum
dimension of 512 pixels. Twenty thumbnails total about 976 KiB on disk. Gallery
entry uses these resources without decoding or resizing the originals. On its
first visit with uncached paintings, the shared loading screen shows real
progress and yields between thumbnails. Subsequent visits retain both thumbnails
and cards; changes to the catalogue, collected paintings, filter, or language
refresh the cards. The individual painting viewer still uses the full original.

## Validation

Native Godot 4.6.3 Compatibility measurements on this machine, opening all
nineteen event dialogs in a minimal scene:

| Synchronous dialog construction | Before | After preparation |
| --- | ---: | ---: |
| Median | 232.3 ms | 3.6 ms |
| Worst | 721.4 ms | 16.2 ms |

Most prepared dialogs measured 2–6 ms. The first dialog was 16.2 ms; this probe
also includes first-use dialog/font work. These are one-run CPU observations,
not a whole-game FPS guarantee. Raw results are in
`artifacts/event-art-performance-before.json` and
`artifacts/event-art-performance-after.json`.

`tools/event_art_performance.gd -- --optimized` measures the prepared path.
`test_event_art_loading` checks bounded texture sizes, reuse, original-resource
absence during preparation and discovery, repeat preparation, and safe custom
crop fallback. Collection, startup, and UI-layout suites cover the surrounding
flow. `tools/event_art_preview.gd` renders the actual small banners for visual QA.

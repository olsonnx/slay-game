# UI consistency review — 29 October 2026

Reviewed the shared styles and menu flows for the main menu, setup/multiplayer, pause and confirmations, settings, profile, collection, results, HUD/shop/province controls, replay library, and level/event/tutorial editors. Verification combines source review, interactive GUI regression checks, and rendered representative screens. It is not an exhaustive screenshot comparison of every possible game state.

## Settings and confirmations

- Replaced settings' default window dialog with an embedded confirmation using the game's panel surface, text colors, spacing and buttons. It names the selected tab and starts keyboard focus on **Keep settings**.
- All five tabs now have the same footer reset action. Controls no longer has a separate instant-reset button. It cancels any pending key capture before asking for confirmation.
- The prompt blocks pointer interaction behind it, traps keyboard focus, and consumes Escape without exiting Options. Confirm applies only to the captured category. Leaving Options also removes the overlay.
- Level-editor discard confirmation reuses the same component, retaining its existing wording and safe **Keep editing** action.

## Collection

- Uses the shared panel, typography, spacing, button states, muted text and accent colors. The gallery is centered and sized to its contents, with scrolling for larger collections.
- Added discovery progress and **All paintings / Collected** filters, including a useful empty state.
- Reworked cards with smaller lock icons, consistent image frames, two-line titles and aligned artist credits. Long titles have hover text; locked cards never reveal undiscovered artwork or its metadata.
- Viewer controls use compact navigation icons and the project's buttons. Keyboard focus moves into the viewer and returns to the selected card on closing. Original-color artwork, native-size viewing, zoom, fit, and previous/next navigation are retained.
- Narrow layouts leave space for the global music control. Titles, counters, artwork controls and credits remain within the supported viewport.

## Shared controls and editors

- Added matching checkbox, multiline text-field and native tab-container styles to the common theme.
- Applied the shared theme explicitly to replay-import, event-editor and tutorial-editor dialogs. Embedded window frames include a proper styled title area.
- Tutorial-editor map and prompt minimum sizes adapt to the logical viewport height, preventing enlarged UI scale from pushing its inspector off screen.
- Refreshed the localization catalogue. Updated the editor Build-palette test to account for the existing Road tool alongside City, Tower and the three lairs; the old five-item expectation was stale.

## Verification

Passing targeted checks include settings reset safety and focus handling, collection discovery/storage and original textures, geometry across button states, keyboard bindings, editor discard behavior, native editor forms, replay navigation, and localization.

Rendered and inspected gallery, locked/collected states, original-image viewer and reset prompts at 1280×720 and 960×620, including the largest requested UI scale (subject to the game's fit limit). Also inspected tutorial-editor controls and a themed authoring confirmation at 1280×800.

Previews are in ignored `artifacts/ui-audit-*.png`. `tools/ui_consistency_preview.gd` reproduces the menu/collection/settings previews without exporting the game. Use isolated writable `APPDATA` under artifacts for test runs.

Version remains 0.2.0. No executable or ZIP/export rebuild was performed.

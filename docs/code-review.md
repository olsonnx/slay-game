# Project reviews

The reviews cover game rules, generation, movement, visual playback, picking, input, UI, audio, tests and resource references.

## Reliability fixes — 16 October 2026

- Editor saves write and flush a sibling temporary file before replacing the old
  map. A failed replacement preserves the old file and leaves the draft dirty.
- Replay readers reject malformed patches before changing state. Godot checks
  command fields, initial dictionaries and encoded coordinates before decoding.
  Both readers limit files to 64 MiB and expanded details to 256 MiB; writers
  reject recordings beyond those limits instead of saving unreadable files.
- Required AI replay positions live in `tests/fixtures/ai_replays/`; missing
  fixtures fail their tests. The test runner also runs Python replay tests
  (`-Python` selects an interpreter, default `python`).
- Hotseat results show the outcome above a separate faction statistics selector.
- F3 is reserved for the FPS overlay, rejected during binding capture and repaired
  to defaults when loading saved bindings. The overlay yields during capture.
- The Windows export excludes tests, tools, editor addons and reference artwork.
  Localization JSON remains included by the editor export plugin.

Regression coverage includes blocked Windows map replacement, malformed replay
patches, bounded Python decompression, reserved bindings and hotseat result layout.
All 45 Godot suites and 14 Python tests passed. The final Windows package excludes
development files, retains localization, and boots successfully in headless mode.

## Fourth pass — 12 October 2026

Movement/command recording, opponent phases and command-preview rendering now have dedicated modules. Immutable AI query contexts reduce repeated route/economy work; unchanged overlays and arrow geometry are retained; material cull variants no longer mutate shared resources. All 18 suites pass. The fixed standalone CPU benchmark shows roughly 20–25% less AI search time, 38% less unchanged HUD refresh time and 22% less route-query time, with identical AI benchmark decisions and scores. See [the post-refactor review](post-refactor-review-2026-10-12.md) for module boundaries, raw evidence, validation and prioritized future watchpoints.

## Third pass — performance and responsibility split

The latest pass batches mana/spell queries, retains status controls, merges question-mark geometry, avoids repeated stationary picks and unused player economy snapshots, and shares recruitment validation. Player actions, magic/events, popup layout, status UI and visual primitives have separate modules. The broken unused root scene was removed, and all 15 regression suites pass. See [the performance review](performance-review-2026-10-11.md) for repeatable measurements, correctness coverage and remaining profiling targets.

## Second pass — 11 October 2026

The three largest scripts had grown to 979, 971 and 937 lines. This pass separates responsibilities through composition, retaining the controller and rules entry points used by existing scenes and tests.

| Finding | Result |
| --- | --- |
| Generation and opponent planning shared the entire rules implementation. | Seeded terrain/resources moved to `src/game/map_generator.gd`; opponent preparation and movement planning moved to `src/game/kingdom_ai.gd`. Rules retain authoritative state, topology, economy and command validation. The rules file is now 622 lines. |
| Picking and lengthy playback coroutines obscured board synchronization and camera behavior. | `src/rendering/board_picker.gd` owns picking; the board-owned `board_playback.gd` owns movement, impact and surrender tweens. The board file is now 644 lines. Playback inherits the board's lifetime and pause state. |
| Input gestures and context-menu construction crowded the session controller. | `src/game/game_input.gd` handles gestures/shortcuts; `src/ui/game_presenter.gd` handles purchase cards, statistics, tooltips and action overlays. The controller is now 736 lines and continues to own selection, turns, transitions and rollback. |
| Ground picking scanned every hex and built temporary polygons. | Axial rounding identifies one candidate; an analytic hex-boundary check preserves gaps and mountain click priority. Ground lookup is constant work per query. Object/sprite picking still scans visible features; this is not an FPS claim. |
| AI preparation retained kingdom dictionaries after topology-changing commands. | Each scheduled capital resolves against live kingdoms. After demolition, candidate provinces are filtered to the surviving kingdom without another RNG shuffle. Ordinary purchases pass the selected capital. Removed capitals are skipped after bridge merges. AI can bridge to a separate friendly kingdom, and a regression verifies its pooled treasury is processed once. |
| Cancelling movement did not cancel the preparation hold or its eventual completion events. | Preparation now shares the playback cancellation revision and kills its hold tween. Cancellation unwinds on the next frame without late completion callbacks. |
| Test processes could remain alive after errors, or silently exit before reporting completion. | The runner bounds execution and requires a successful check summary as well as a clean exit/error log. |
| A legacy root `main.tscn` referred to deleted `res://game.gd`; generated previews and test settings accumulated. | Removed the broken unused scene and 34 generated files (6.23 MB). Preserved source assets, sound effects, the character reference, `.gdignore` and engine-managed imports. Stale editor references to that scene now point to the actual application entry. |

Verification includes all thirteen suites, reference resolution for source resources, and native previews of the Modern HUD and New Game screen. New review fixtures cover direct tile picking and gaps, merged AI treasuries and cancelled preparation callbacks. Existing tests exercise both rulesets, all map sizes, movement rollback, sequential/concurrent playback, sounds, pause/restart and transitions. Generated test settings and previews remain reproducible and ignored.

Remaining extension considerations: cell/command dictionaries are still intentionally retained to avoid changing the state format during a structural cleanup; versioned typed records should accompany save/load or multiplayer. Model links in the new helpers remain dynamic to avoid circular script imports, with explicit types for data and scene values at module boundaries. Tall-object picking remains linear, so add a spatial index only if profiling warrants it. No FPS benchmark was performed.

## First pass — 10 October 2026

Existing gameplay behavior was retained in the first pass; the shortest-route defect was corrected.

## Findings addressed

| Priority | Finding | Change and evidence |
| --- | --- | --- |
| P2 | Enemy/neutral destinations used the first friendly neighbor as an approach, even when the source itself was adjacent. This produced unnecessarily long animation routes. | Border paths now choose the shortest friendly approach. A regression fixture verifies an adjacent capture remains a two-coordinate route despite a longer approach appearing first in neighbor order. |
| P2 | Every board synchronization destroyed and recreated all tile nodes, props, soldiers, and geometry. | Synchronization compares visual fields and replaces only changed tiles. Explicit animation dirtiness forces source/destination cleanup even after playback has already updated the visible snapshot. Tests verify zero rebuilds for an unchanged board, exactly one for a single-cell edit, and preserved scene identity elsewhere. |
| P2 | Meshes and shop icons were repeatedly allocated with identical geometry. | Immutable box, cylinder, roof and icon resources are cached and shared. Instances still own their transforms; ghost materials remain duplicates so transparency never changes real buildings. |
| P2 | Hovered routes rebuilt a breadth-first search, and recorded commands validated the same route again during mutation. | Hover uses the selection's validated route graph. Recorded moves validate once, then use the internal mutation helper. Public direct moves still reject illegal destinations. |
| P2 | A mouse release outside the window could leave orbit input active after focus returned. | Window focus loss resets the RMB gesture and rotation state without discarding an otherwise valid selection. |
| P2 | Volume sliders wrote settings for every change, and save failures were ignored. | Changes are debounced for 250 ms, pending changes flush on exit, and failures emit a signal handled by a short game notice. Tests cover pending saves and explicit flushing. |
| P2 | Prices, upkeep, names and tooltip values had independent hardcoded copies. | Existing balance values and presentation metadata now live in `src/game/game_catalog.gd`; rules and unit/building tooltips use it. |
| P3 | UI construction and procedural asset generation obscured gameplay and rendering behavior in large scripts. | HUD construction moved to `src/ui/game_hud.gd`; procedural resources moved to `src/rendering/board_assets.gd`. Controller and board retain their tested APIs. |
| P3 | Map generation bounds were expressed in pixel coordinates from the previous 2D layout. | Shared axial geometry is independent of viewport size. Generation now uses equivalent world bounds. |
| P3 | Preview images, video, imported preview metadata, and frame captures cluttered the project and editor import scan. | Removed 389 generated files, including over 50 MB of capture frames, plus empty editor template folders. New output goes into ignored `artifacts/`, with `.gdignore` to prevent importing it. |

## Structure and preserved files

Scripts, scenes, resources, tests, tools, documentation and assets have separate folders. All resource references and the project entry scene/autoload were updated. Existing script UID files and asset import settings were preserved during moves.

The unreferenced `knight1.png` is preserved at `assets/reference/knight1.png`: it appears to be a user-supplied character asset rather than a generated preview. Original MP3 files are preserved under `assets/sfx/`. Godot's `.godot/` directory remains engine-managed and ignored.

## Verification

`tools/run_tests.ps1` now runs all thirteen regression suites. It checks exit status, engine errors and successful completion summaries, since a scene runtime error can sometimes accompany exit code zero. Tests isolate preference output under `artifacts/` and allow the dummy audio mixer to drain before process exit.

Preview and recording tools remain available under `tools/`. Their outputs are reproducible, so generated media is no longer part of the source tree. A native Godot render checks the reorganized scene and HUD after the refactor.

The renderer improvement is measured in tile rebuild counts and retained objects, not a claimed FPS increase. No frame-rate benchmark across machines was performed.

## Future work considerations

- Save/load should serialize versioned rule state (cells, kingdom treasuries/capitals, turn and RNG state), rather than scene nodes or procedural meshes. Playback and cancellable player commands already use separate visual snapshots.
- The rules still use dictionaries and string action kinds. For substantially more unit types or multiplayer, introduce typed cell/command records and stable unit identifiers. That migration should include explicit command validation; current public commands retain it.
- Three unit tiers remain the current limit; map profiles support two through six factions. Adding tiers requires expanding metadata, sprite generation, merging limits and the recruitment layout together; changing prices/upkeep alone is centralized.
- Object picking still scans the board's buildings and soldiers. Larger maps may benefit from a spatial broad phase and instanced grass/prop rendering; the current small board does not justify that complexity yet.
- Hover overlays still replace their small temporary node group when the target changes. Static board geometry and identical mesh/icon resources are now reused; persistent overlay instances are a separate possible improvement if profiling shows a need.
- Separate connected kingdoms, graves and trees follow this prototype's documented rules, not every original Slay rule. Capitals may coexist with units, and replacement-capital placement can consume an existing feature if no clear cell is available. Changing those rules would be a gameplay decision, not a silent refactor.
- There is no Git repository or export preset in this workspace. Version control and a release preset are useful next steps, but were not created as part of a code cleanup.

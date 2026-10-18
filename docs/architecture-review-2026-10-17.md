# Architecture review — 17 October 2026

**Follow-up:** the recommendations and menu-cache investigation below have since been implemented. See [implementation boundaries and validation](architecture-implementation-2026-10-17.md). This review preserves the findings as they stood before that work.

The project has useful subsystem boundaries and substantial regression coverage, but several coordinators have grown back into god objects. The main problem is shared mutable state and helpers that know the entire controller. Moving methods into another file improves navigation, but does not by itself remove that coupling.

This review inspects the application/session flow, authoritative rules, AI workers and queries, board synchronization and batching, replay state, editor history, and UI construction. It includes targeted refactoring and regression checks. It is not a performance benchmark or a complete redesign of the session lifecycle.

## Findings, ordered by impact

### 1. The game controller is still a god object — high maintenance risk

[`game.gd`](../src/game/game.gd) inherits the HUD and combines startup, selection, encounter dialogs, province commands, undo, completion, camera following, hotseat state, and disposal. Helpers such as [`player_actions.gd`](../src/game/player_actions.gd) and [`opponent_turns.gd`](../src/game/opponent_turns.gd) reach through `game` into controls, renderer internals, rules, and session flags. These are useful file boundaries, but their effective interface is almost the entire game object.

Concrete examples: `click_hex` contains roughly 140 lines of dispatch, tutorial checks, authoritative mutations, animation, rollback, selection, sound and UI refresh. `kingdom_ai.search_async(game, ...)` reads `game.view` for profiling and waits on the game's scene tree and pause state. This ties AI orchestration to a UI host even though the actual worker has properly isolated state.

**Addressed here:** HUD formatting now lives in the existing presenter. Selection/target queries remain in the controller. Visible-economy projection is a separate module with explicit board/bank/mana inputs and no scene dependency.

**Remaining:** the controller is still 846 lines, and the presenter still depends on the controller. The next substantive improvement should introduce a session-owned model for selection and phase, then compose the HUD around it. Pass AI execution a small host/cancellation contract rather than the gameplay scene. Do this incrementally with existing playback and shutdown tests; simply moving all `game.*` calls to more utility files would disguise the problem.

### 2. Snapshot schemas are copied by hand in multiple places — high extension risk

[`ai_analysis.snapshot`](../src/game/ai_analysis.gd), [`player_actions.click_hex`](../src/game/player_actions.gd), [`game.cancel_action`](../src/game/game.gd), [`replay_log.raw_position/position`](../src/game/replay_log.gd), and the visible-economy projection each enumerate model fields. Adding a persistent rule field requires remembering which snapshots must capture it, how deeply to copy it, and which restore path must write it back.

These snapshots intentionally differ. AI hides unknown encounters and uses an independent RNG; replay preserves authoritative history; the HUD needs a partial view synchronized to animation impacts. They cannot safely be replaced with one indiscriminate deep copy. No currently omitted field is established as a gameplay bug by this review.

**Addressed here:** visible-economy relevance is defined once and reused by projection and invalidation signatures. The projection copies records before kingdom reconstruction can mutate them. Added tests prove that mutations in either direction cannot affect borrowed inputs and that signatures detect in-place changes.

**Next:** introduce an explicit state snapshot schema with documented policies for simulation, rollback, replay and presentation. Test round trips for authoritative state and deliberate omissions for simulation. Keep temporary UI selection outside that schema. Retain the existing scoped query-cache lifetime: [`ai_queries.gd`](../src/game/ai_queries.gd) correctly documents that a context must be discarded after mutation.

### 3. Session phases are encoded by overlapping flags — medium maintenance risk

`busy`, `closing`, `game_over`, `completion_started`, `defeat_notified`, `inspecting_results_map`, scene-tree pause, and renderer transition state jointly determine permitted actions. Guards appear in `commands_locked`, `_process`, input, player actions, AI loops and application transitions. Cancellation also relies on coroutines observing `closing` and eventually clearing `busy` before disposal.

The cancellation checkpoints and worker completion acknowledgements are valuable and should be preserved. The debt is that permitted state combinations are implicit. A new modal or phase must update multiple guards, making apparently unrelated input/playback regressions plausible.

**Next:** write down session transitions and centralize command eligibility. Use an explicit session phase plus separate orthogonal facts such as pause and modal visibility; avoid one enormous enum containing every combination. Add transition-level tests before migrating flags.

### 4. Rules accumulated unrelated algorithms — addressed in this pass

[`kingdom_rules.gd`](../src/game/kingdom_rules.gd) mixed kingdom reconstruction, capital replacement, purchases, development, relocation, movement, resources and turn settlement. Reconstruction is particularly sensitive: traversal order affects capital selection, treasury merging, AI decisions and replays.

**Changed:** [`kingdom_topology.gd`](../src/game/kingdom_topology.gd) owns reconstruction and deterministic capital replacement; [`kingdom_construction.gd`](../src/game/kingdom_construction.gd) owns recruitment, bridge/building validation, development and relocation. Both receive state per call, retain no model, and use local cell references in loops. The rules object retains authoritative ownership and its public entry points.

The facade decreased from 640 to 440 lines. These helpers still use the rules model's existing dynamic interface; this is a cohesive implementation split, not a typed domain-model migration. Internal calls within an extracted subsystem now call that subsystem directly. Overriding facade wrappers alone is not an extension contract; there are no such overrides of the extracted methods in the current project.

### 5. Board rendering has a broad contract and positional records — medium maintenance risk

[`board_view.gd`](../src/rendering/board_view.gd) still owns camera navigation, synchronization, picking caches, units, hover effects, tile assembly and animation integration. Rendering helpers communicate using node metadata and positional arrays. For example, [`static_batches.gd`](../src/rendering/static_batches.gd) relies on nine-slot source records where mesh/material, transform, color, layers and shadows are accessed by index. This is compact, but extending one producer without updating all consumers is easy.

**Changed:** [`board_tile_effects.gd`](../src/rendering/board_tile_effects.gd) now owns barrier, fortification and encounter geometry. It uses the existing board asset caches and leaves lifetime, synchronization and resource ownership with the board. `board_view.gd` decreased from 811 to 739 lines. Static batching's 201-line `sync_tiles` now separates scanning/cleanup from `publish_chunk`, preserving signature reuse and terrain recoloring.

**Next:** separate camera/navigation and unit presentation when those features next change. Name the positional-record schema using constants or typed records and document metadata ownership. Choose the representation with allocation cost in mind; replacing every hot-loop record with an allocated object is not automatically an improvement. Keep incremental batching, retained identity and shared-resource isolation tests.

### 6. The editor mixed history policy with input and layout — partially addressed

[`level_editor.gd`](../src/editor/level_editor.gd) previously owned stroke interpolation, visited-hex tracking, document snapshots and direct undo-stack writes alongside pointer handling, file dialogs and UI. Both the document and editor separately enforced the 60-entry history limit.

**Changed:** [`brush_stroke.gd`](../src/editor/brush_stroke.gd) owns one edit transaction, interpolation, deduplication, erase mode and path breaks across UI. The document owns the history policy; the editor supplies coordinates and brush settings and refreshes the view. Finished strokes release their snapshots. Tests cover interpolation, revisits, empty strokes preserving redo, UI path breaks, erasing, undo and bounded history.

**Remaining:** the editor is still 733 lines, including a 171-line layout builder. Its `set_suspended` method directly manages the board's `Video.changed` connection, backdrop and camera; that belongs behind a board activation method. A dedicated editor view with semantic signals would be the next useful split. Manual positioning throughout editor/options/menu construction also makes each new control a layout regression risk.

### 7. Large procedural stages and stale checks — medium/low maintenance risk

[`map_generator.generate`](../src/game/map_generator.gd) remains a roughly 193-line sequence of terrain growth, erosion, connectivity and resource stages. Named stages would improve readability, but extraction must preserve RNG consumption and dictionary insertion order. Existing generation golden fixtures are a good foundation. This pass does not change generation.

Regression execution exposed two assertions left behind by the Scout-wage rebalance: `test_review` expected a pre-purchase merged treasury of 112 instead of 108, and `test_resources_terrain` expected a summoned Scout's upkeep to be 3 instead of 4. Both assertions now use the current catalog wage while preserving their actual invariants: merged treasury accounting and ordinary upkeep for summoned units. Balance-specific assertions remain in the balance tests.

The workspace has no Git repository. A source snapshot is saved at `artifacts/architecture-before.zip` for this pass, but it cannot provide the history, attribution or reliable incremental review that version control would. Generated artifacts are already ignored and excluded from Godot import; they were left intact.

The randomly generated menu-background fixture also failed its combined chunk/material-cache bound once and passed unchanged on the next run. The failing run did not record which bound or seed was responsible, so this review cannot establish its cause or attribute it to the refactor. The assertion now prints both sizes and the landscape seed. Its limits remain unchanged. Investigate with a captured failing seed; a passing rerun does not resolve this reliability issue.

## Scope and verification

| Existing module | Before | After |
| --- | ---: | ---: |
| Rules facade | 640 | 440 |
| Session controller | 908 | 846 |
| Board view | 811 | 739 |
| Level editor | 759 | 733 |
| Presenter | 251 | 297 |

Counts include blank lines. A smaller file is not the acceptance criterion: state ownership, deterministic traversal, playback timing and public entry points must remain correct. The new modules are 38–169 lines each. No engine migration or new dependency was introduced.

Validation used Godot 4.6.3 and Python 3.14:

- All **50 Godot suites** completed with zero failed checks across the initial run and resumptions after the stale assertions and intermittent menu failure. The final resumed run (`-From test_menu_background`) passed its 34 suites. The menu flake described above remains unresolved.
- All **14 Python replay-reader tests** passed.
- The new architecture suite passed **21 checks** for brush transactions and visible-economy isolation.
- A separate comparison against the saved original rules passed **192 state-hash checks across 32 seeded maps**: both rulesets, two sizes, eight seeds. It exercises generation, development, relocation, recruitment, bridge topology, tower construction, turn settlement and incremental reconstruction. The original and extracted rules also produce identical seeded state hashes for the merged-treasury fixture.
- Editor import registered all new scripts with no script parse/compile errors. It emitted an editor-settings safe-save error in this restricted environment; this is not reported as a completely clean editor run. Gameplay/editor behavior was checked by the headless suites; no new native visual capture or performance claim is made.

Reproduce the regression run with `./tools/run_tests.ps1 -Godot 'C:/path/to/Godot_console.exe'`. Evidence: `artifacts/architecture-test-summary.json`, individual `artifacts/test_*.log` files, `artifacts/architecture-parity.log`, and `artifacts/architecture-import-final.log`. The source-only comparison patch is `artifacts/architecture-refactor.patch`; the README and this report are separate documentation changes. The comparison probe and original rules copy are retained under ignored `artifacts/` so the parity check can be repeated locally.

## Recommended next work

1. Formalize state snapshots and their distinct policies; this protects future features across AI, rollback and replay.
2. Define session transitions and command eligibility, then reduce the controller/HUD coupling through composition.
3. Give the board an activation API and separate navigation/unit presentation; document batching record contracts.
4. Extract procedural generation stages under golden tests and move editor/menu layouts toward dedicated views and containers.

Keep the existing strengths: isolated AI worker snapshots, main-thread command revalidation, deterministic map fixtures, incremental render updates, transactional replay cancellation, and atomic level loading/saving. Those are sound foundations to extend.

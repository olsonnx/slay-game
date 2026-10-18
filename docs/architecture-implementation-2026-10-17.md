# Architecture recommendations implemented — 17 October 2026

This implements the follow-up work from the [architecture review](architecture-review-2026-10-17.md). The existing gameplay rules, replay wire format and generation version remain unchanged. Compatibility adapters preserve scene/test/tool entry points while the production controller uses composed owners.

## Ownership and interfaces

| Area | Implemented boundary |
| --- | --- |
| Model snapshots | `state_snapshot.gd` owns the authoritative schema and configuration policy, simulation copies, replay field mapping and presentation metadata. Rollback captures/restores this schema instead of enumerating fields independently. |
| Session | `session_state.gd` owns rules, faction/round metadata, outcome and phase. `session_selection.gd` owns transient selection, modes, paths and targets. Neither selection nor UI controls enter authoritative snapshots. |
| HUD | The game owns a separate `GameHud` node. Its constructor receives an explicit command table and activation callback. The presenter receives the session, HUD, board and defined actions; it no longer receives the entire controller. Event dialogs receive only a button factory. |
| AI | `ai_execution.gd` supplies frame scheduling, pause, cancellation and optional profiling. `kingdom_ai.gd` no longer reads the gameplay scene's renderer or controls. Legacy standalone Node hosts are adapted at the boundary. Workers still receive isolated models and main-thread commits still revalidate commands. |
| Board | `board_navigation.gd` owns camera state, bounds and pan tweens; `unit_presentation.gd` owns actor registries, sprites and hover tweens. The board coordinates synchronization, playback and presentation notifications. |
| Activation | `board.set_active` owns camera activation, controls, backdrop and the video-settings subscription. Editor suspension and gameplay shutdown use it. |
| Batching | `batch_records.gd` names source, suppression and signature slots. Static batching and terrain merging share the contract, preserving compact array storage in hot loops. |
| Editor | `editor_view.gd` owns controls, tool cards and named layout sections. It emits semantic intentions; the controller owns document mutation, file operations and input. Island settings use container layout. |
| Generation | The main generation routine delegates home connection/growth, mainland connectivity, land budgets, erosion, trimming and offshore-safe growth to named stages, in the original RNG/traversal order. |

The editor controller decreased from **733 to 460 lines** and the board from **739 to 593**. Generation's main routine decreased from **193 to 78 lines**. The game controller remains large: this work separates ownership and removes HUD inheritance rather than treating a line limit as proof of good architecture. Input, tutorial and turn orchestration still coordinate through its public interface.

`game_compatibility.gd` and `editor_compatibility.gd` contain forwarding aliases for existing consumers. They contain no rule or layout logic. They can be retired as tools/tests migrate to `game.hud`, `game.session`, and `editor.ui`. HUD, editor view and board components are parented during construction, so abandoning a scene before it enters the tree cannot leave those nodes orphaned.

## Snapshot policies

- **Authoritative/rollback:** captures position, configuration, AI telemetry and exact RNG state into independently owned records. Restore copies records back without transferring recorder ownership. Internal snapshots carry a schema version; a coverage test requires every rule-model property to have a data or runtime policy.
- **Simulation:** copies the same declared configuration and appropriate position fields, hides undiscovered encounters, starts with no pending encounters/telemetry/recorder, and seeds an independent RNG with zero. Cell records retain the existing flat scalar-value contract and efficient per-record copies.
- **Replay:** preserves the existing eight position fields, insertion order, RNG string encoding and v1/v2 archive contracts. Internal snapshot metadata is not added to replay files.
- **Presentation:** copies only declared readout metadata and the relevant visible territory, banks and mana; reconstruction cannot mutate borrowed live or playback state.

## Session transitions

| Transition | Effect |
| --- | --- |
| Ready → player playback / opponent turn | Locks commands and marks outstanding work. |
| Work finishes | Returns to ready only if the session has no terminal phase. |
| Match completes during work | Enters completed while retaining the work flag until the coroutine drains. |
| Completed ↔ result inspection | Commands stay locked; camera navigation remains available. |
| Any phase → closing | Rejects new work; cancellation drains outstanding work without reopening the session. |
| Reset after work drains | Resets outcome, phase and transient selection. |

Pause, modal visibility and board transitions remain orthogonal inputs to the centralized command/navigation policy. Input releases are still observed during level transitions so gestures cannot become stuck. Existing boolean entry points now delegate to the session rather than storing independent copies of phase state.

## Menu cache failure resolved

The intermittent review failure was reproduced with fixed seeds. After 165 simulated seconds, five of six seeds retained more than the old 1,500-material test limit; seed 1 retained **1,632**. The stream's coordinate-dependent tint variants accumulated in a shared cache.

All material variants now enter through one cache-registration method with a **1,024-entry FIFO budget**. Eviction removes only cache references; live meshes retain their materials and their appearance is not mutated. The same six seeds now end with exactly 1,024 cached materials, with 4–5 retained island chunks. A permanent seed-1 menu regression and synthetic mixed opaque/detail-material tests cover the budget and resource isolation. This is a bounded-retention fix, not a claim of improved frame rate.

## Validation

- One uninterrupted run of **all 50 Godot suites** passed, along with **14 Python replay-reader tests**. Final targeted reruns cover subsequent ownership, modal-factory and form-padding adjustments: **79 architecture checks**, startup, input, menu lifecycle, results, UI layout and the fixed-seed menu test passed without engine/script errors.
- Existing generation-v10 golden snapshots passed in `test_scaling`; world generation passed **68,585 checks**. No golden fixtures or generation version were changed.
- The saved-original-rules comparison passed **192 state-hash checks across 32 seeded maps**, including construction, relocation, settlement and reconstruction.
- Editor import completed without script or engine errors after isolating both roaming and local application-data directories. New script UIDs were generated by the engine.
- The editor settings were rendered with the native OpenGL backend at **960×620**, visually inspected and corrected for right padding. Container-bound assertions cover that correction.

Evidence is retained under ignored `artifacts/`: `architecture-implementation-before.zip`, `architecture-implementation.patch`, the implementation test/import/parity logs, `architecture-menu-cache-before.log`, `architecture-menu-cache-after.log`, and `architecture-editor-settings-960.png`. The source snapshot includes the state at the start of this implementation request. No repository history was created or existing generated artifacts removed.

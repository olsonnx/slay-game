# Replay frame-stall repair — 15 October 2026

The regression was synchronous recorder CPU work. During each actual command, the recorder encoded the entire position, compared it with the previous encoded position, decoded/re-encoded that position for hashing, serialized it and hashed it. Each AI command then repeated this work for its diagnostic annotation. The archive subsequently discarded those hashes because they can be reconstructed. No replay files were written during active AI turns: disk writes were already limited to completed games.

## Implementation

The live recorder now keeps a native initial snapshot and an in-memory journal. It compares native dictionaries and copies only changed cell/kingdom records; unchanged records are not recursively converted or copied. Captured records remain immutable, so later moves cannot alter earlier positions. AI diagnostic annotations copy their arguments without scanning the board again. These annotations are emitted after the command and any encounter resolution have already been captured; their only additional mutations are AI bookkeeping, which is outside replay position state.

Transactions shallow-copy the position indexes while sharing immutable captured values. Cancelled moves restore those indexes and discard their buffered entries. The normal play path performs no JSON conversion, JSON serialization, hashing, compression or replay file writes. Encoding and compression occur once when a game finishes. Explicit inspection of an in-memory recording can still materialize legacy JSON and hashes; production gameplay never calls that inspection API.

The compact version-2 format, complete state deltas, AI diagnostics, random outcomes, finished-games-only policy and version-1 reader compatibility are preserved. The recorder still scans native cell dictionaries to detect changes; this is not a claim of constant-time capture. Completed-game encoding/writing is still synchronous and occurs after the result, not inside ordinary AI moves.

## Measurements

All measurements use the same machine. Recording microbenchmarks change one cell per command, then separately append unchanged-state AI diagnostics. Each case has 40 samples. The crowded board uses real generated terrain and 120 units.

| Recorder call | Tiles | Before median | After median |
| --- | ---: | ---: | ---: |
| Move | 279 | 26.895 ms | 0.577 ms |
| AI diagnostic | 279 | 24.972 ms | 0.024 ms |
| Move | 1,000 | 91.978 ms | 1.888 ms |
| AI diagnostic | 1,000 | 91.074 ms | 0.025 ms |

`tools/replay_performance_probe.gd` produces `artifacts/replay-performance-before.json` and `artifacts/replay-performance-after.json`. The before case uses the retained pre-repair script at `artifacts/replay_log_before_performance.gd`.

The native rendering comparison used Windows, Godot 4.6.3 Compatibility, RTX 2060, 1280×820, uncapped rendering and VSync off. It ran the production asynchronous AI and movement animations on the same 1,000-tile board. All three cases committed the **same 11 AI moves**; 12 commit samples include a final empty attempt.

| Case | Median AI commit | Maximum AI commit | Worst observed frame |
| --- | ---: | ---: | ---: |
| Recording off | 1.606 ms | 5.149 ms | 38.425 ms |
| Previous recorder | 189.760 ms | 203.297 ms | 226.035 ms |
| Repaired recorder | 4.053 ms | 8.485 ms | 43.054 ms |

These are measurements of this fixed workload, not a promise of a constant FPS on every island. Occasional rendering/search stalls remain with recording disabled. Rare commit stalls are poorly represented by median overall frame time; the report therefore includes commit duration and worst-frame duration. Full frame distributions are retained in `artifacts/replay-frame-comparison.json`; `tools/replay_frame_probe.gd` reproduces the comparison using the retained before snapshot.

## Comparison with other games

[Wesnoth's replay implementation](https://raw.githubusercontent.com/wesnoth/wesnoth/master/src/replay.cpp) appends named commands and their arguments to a recorder. Its per-unit checksum helper is gated behind multiplayer debugging. This supports separating cheap live recording from verification work rather than serializing and hashing the world for every action.

[Factorio documents deterministic input synchronization](https://wiki.factorio.com/Desynchronization), and [its replay documentation](https://wiki.factorio.com/Replay_system) describes version and mod compatibility restrictions. An input-only replay can be very cheap, but reproducing it depends on the same simulation behavior. Our recordings are intended for analysis after balance/AI changes, so this repair retains exact changed-state data instead of switching to input-only resimulation.

No third-party implementation code was copied. The adopted pattern is an append-only command journal with deferred encoding and verification.

## Verification

Replay checks cover every-command reconstruction, immutable earlier positions and diagnostics, cancellation, bridge creation/deletion, events/RNG, AI actions, legacy compatibility, archive integrity, natural win/loss saves and unfinished-game disposal. The native comparison additionally checks identical AI orders with recording off, before and after the repair. Independent Python reader checks validate the produced format.

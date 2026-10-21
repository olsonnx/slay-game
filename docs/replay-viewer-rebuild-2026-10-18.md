# Replay viewer rebuild — 18 October 2026

The previous compact reader regenerated a full position hash for every command,
serialized the expanded records, then parsed them and calculated the same hashes
again. This ran in a background thread, but consumed substantial CPU for tens of
seconds. The viewer then validated all changed cells on the main thread and built
the complete island synchronously. Backward seeks replayed from the opening, and
every seek decoded the complete state.

The rebuilt spectator path keeps the existing v1/v2 recording formats and the
full inspection reader. Its compact reader relies on the existing SHA-256 tape
checksum and still validates metadata, the readable action timeline, command
sequence and complete state patches. It skips derivable per-position hashes only
for checksum-verified v2 archives that explicitly omit those hashes. Legacy
files and archives containing stored hashes retain their original verification.

Background preparation decodes each patch once, records its inverse and creates
sparse checkpoints (32 intervals, at most 33 snapshots). Values remain immutable;
each seek copies only the section indexes. Stepping uses the existing position
when nearby; distant seeks start at a nearby checkpoint. Reverse patches restore
removed cells, dictionary records and scalar fields. This remains independent of
rules, AI, random generation and later balance changes.

The library discovers files in the background and adds bounded batches. Metadata
previews now read only a bounded header/readable prefix during discovery, without
decompressing recordings. Hover does not load a recording. Worker tasks retain no viewer nodes.
Back, Escape and Choose recording can abandon an import immediately; readers and
indexers check cancellation between commands. A root-owned keeper collects every
completed pool task, even after the viewer closes, and drains pending tasks only
at application shutdown. Discarded results cannot replace a newly opened viewer.

The main thread constructs tiles in approximately 4 ms budgets, including material
inspection. Initial geometry is then published one 8-by-8 region at a time. The
opaque library covers construction. Returning to it releases the spectator island,
and slider events are combined into one seek per frame. Animated commands use the
existing playback implementation directly to avoid retaining a suspended wrapper
when the viewer closes during movement.

## Measurements

Read-only copies of seven existing player recordings were tested with Godot
4.6.3 on this machine. Headless measurements exclude rendering. The full original
reader was measured before editing; the new playback reader and index were
measured together afterward. These are individual runs, not hardware-independent
performance guarantees.

| Commands | Previous read | New read + index | Previous average seek | New average seek |
| ---: | ---: | ---: | ---: | ---: |
| 86 | 596 ms | 40 ms | 3.56 ms | 0.11 ms |
| 660 | 15,130 ms | 309 ms | 31.48 ms | 0.12 ms |
| 722 | 17,434 ms | 373 ms | 33.31 ms | 0.07 ms |
| 922 | 30,177 ms | 474 ms | 55.49 ms | 0.13 ms |
| 1,174 | 51,785 ms | 695 ms | 65.65 ms | 0.26 ms |
| 1,258 | 41,525 ms | 753 ms | 77.55 ms | 0.33 ms |
| 1,754 | 144,775 ms | 1,164 ms | 163.34 ms | 0.25 ms |

Seek samples alternate between the middle and end, 20 times per recording.
`tools/replay_loading_probe.gd` reproduces the new reader/index measurements.

The native rendering probe at 960-by-620 on an RTX 2060 opened the library in
11.3 ms and loaded the latest 500-tile, 1,754-command recording in 2.21 seconds
including rendering. Maximum measured tile construction batch was 17.7 ms,
geometry publication batch 4.2 ms and finalization 3.6 ms. The worst observed
frame during loading was still 190 ms. Cold graphics initialization can stall
longer: an earlier run before geometry batching observed a 2.23-second frame.
The rebuild does not claim to eliminate graphics-driver or shader compilation
stalls. `tools/replay_loading_frame_probe.gd` records native frame gaps and
captures the library and viewer for visual inspection.

### Uncapped menu follow-up

With VSync explicitly disabled and the application uncapped, the native library
probe reproduced 1,265 average FPS. Loading optimizations alone do not bound the
rendering load of an otherwise lightweight menu. The spectator now applies a
temporary 60 FPS ceiling during browsing/loading and 120 FPS during playback,
honors any lower application limit, and restores the previous limit on exit.
It does not change or save the user's VSync preference.

The same native probe measured 59.7 average FPS with the fix, a 16.97 ms 99th
percentile frame interval, and a 17.08 ms maximum interval while selecting and
hovering recordings for three seconds. The application returned to its original
uncapped setting on exit. This reproduces and fixes runaway rendering; it does
not establish that excessive FPS was the sole cause of every reported stall.
`tools/replay_menu_fps_probe.gd` reproduces this check; `-- --uncapped` explicitly
bypasses the temporary limit for a before/after comparison.

## Validation

The viewer suite checks exact indexed reconstruction of a 4,096-action timeline,
bounded checkpoint/seek work, immutable earlier positions, tile creation/deletion,
scalar rollback, legacy compatibility, checksum and patch rejection, cancellation
during reading/indexing/construction, paused and animated combat playback, seeking
during animation, unchanged files and repeated menu disposal. The recording suite
and independent Python reader tests cover the existing recording format. Native
captures were inspected at the minimum supported window size.

## Library metadata

New archives expose a compact summary in the first JSON line, generated from the
same recorded header and result as the reconstruction tape. Full playback checks
that the exposed summary agrees with the checksum-protected detail records.
The summary includes played kingdoms/player names, outcome/winner, duration,
rounds, mode, rules, authored map title, map size, AI difficulty, initial kingdom
count, UTC start time and seed. Custom player names remain distinguishable from
their chosen catalog kingdom; different opponent difficulties appear as Mixed.

Completion records capture the game's paused, unscaled match clock. No timing
work or extra serialization is added to ordinary commands. Older compact files
can expose names and results from the small readable timeline without touching
their compressed footer. Only selecting an older file requests its remaining
metadata in a cancellable background job. Missing historical durations are
labelled Not recorded. Existing files are never rewritten to invent missing data.

The native menu probe with VSync off still measured 59.7 FPS while rapidly
selecting recordings, with a maximum frame interval of 17.6 ms. Results tests
verify that a completed 125-second match retains that exact duration and outcome
after save/load. Viewer tests cover new/legacy previews, custom map titles, all
local seats, winner labels, mixed difficulties, malformed previews and rejection
of a summary that disagrees with the complete tape.

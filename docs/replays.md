# Recorded games and AI analysis

After a win, loss or draw, the results screen offers **Save replay**. This applies to Quick Play, editor maps and hotseat. Recording begins from the actual starting board in memory; finishing a game does not create a file. Choosing Save replay writes one `.jsonl` file. Leaving the results screen without saving discards the recording, as does restarting, leaving, closing or abandoning an unfinished game. The tutorial is excluded because its lessons deliberately reset the board.

Open **Replays** from the main menu to browse recordings. On Windows the files are normally in `%APPDATA%\Godot\app_userdata\SlayGame\replays`. Share the files from a few wins, ideally alongside any losses and a short description of what felt exploitable. Files stay on your computer; nothing is uploaded automatically. You can delete older recordings from that folder.

## Watching a replay

Choose **Replays** from the main menu. Select a saved recording and press **Watch replay** (or double-click it). **Open replay file** also accepts shared `.jsonl` recordings from other folders. The list refreshes when reopened and has a manual Refresh button. Discovery and bounded metadata previews run in a background task, and the list fills in batches of 64 entries per frame. New recordings expose a compact summary in their first line; older compact recordings expose their player names and readable result without decompressing the details. Selecting an older recording recovers its remaining metadata in a cancellable background task. File rows disable automatic tooltip popups. The filesystem file picker is created only when Open replay file is pressed, so entering Replays never initializes filesystem browsing. An empty library explains how to save a recording. Playback validates the complete recording in a background task; damaged or unsupported recordings report an error and leave the browser available.

Recordings open paused at their starting position. The bottom icon toolbar offers **Play / Pause**, **Previous / Next**, **Go to start** and **Go to end**; dragging the timeline seeks immediately. Speeds are **0.5×, 1×, 2×, 4×, 8× and 16×**, including movement animation speed. Space toggles playback, left/right arrows step, and End jumps to the complete final position. Movement, combat, merges and castle surrender use the normal unit animations. Playback stops at the end; pressing Play again restarts it. Every icon has a descriptive tooltip with its shortcut.

**Movement only** skips non-movement viewing steps. Recruitment, development, income and all other state changes are still applied, and the complete final position remains reachable. If a unit was recruited between two visible movements, its recorded pre-movement state is restored before animating it. Switching the filter pauses playback and preserves the nearest earlier visible action. AI diagnostic-only records are always skipped.

The camera stays under your control: wheel to zoom, right drag to rotate, and middle drag or the configured pan keys to pan. Like the live game, a short click on the camera icon switches overhead/3D, while holding it for 0.55 seconds recenters with the same border progress indicator. Home also recenters, and the configured View shortcut switches views. Camera instructions live in that icon's tooltip.

The header fits the title and kingdom legend at the top left. The folder icon in the bottom toolbar chooses another recording; Escape also returns to the library. The back arrow returns to the main menu. The eye icon or F10 hides the replay panels and FPS overlay without stopping playback or camera control. A small eye icon remains available to restore them; F10 or Escape also restores hidden controls before leaving the recording.

The viewer uses a separate spectator board. It applies the recording's state changes, never reruns AI, never starts a live match or recorder, and never modifies the file. It supports both legacy version 1 recordings and compressed version 2 archives, independent of later balance changes. To watch a replay, first return to the main menu from any live match.

Playback loading verifies the compressed tape checksum, metadata, readable timeline, sequence and every state patch without regenerating redundant per-position hashes. Legacy recordings still verify their stored hashes. A background task also prepares native forward/reverse changes and at most 33 sparse checkpoints. Seeking copies only state indexes and applies nearby changes instead of decoding the whole board or replaying the match from its opening. Slider movements are combined into one seek per frame.

Island construction and initial geometry publication run in separate batches while the library remains visible. The browser's Back button and Escape remain available during loading; cancellation stops background reconstruction cooperatively and discards partial islands. Returning to the library releases the spectator board. A task keeper collects completed work after a viewer closes, so navigation never waits for filesystem work. See [the viewer rebuild and measurements](replay-viewer-rebuild-2026-10-18.md).

Replays limits rendering to 60 FPS in the library and during loading, and 120 FPS while viewing a recording. These limits also apply with VSync disabled and respect any lower application limit. Leaving Replays restores the previous limit without changing the saved VSync preference.

The browser and playback controls use the shared menu panels, typography and primary buttons. Saved files show the played kingdom, result and date. Selection shows the local kingdoms/player names, outcome, elapsed duration, rounds, Quick Play/custom-map/local multiplayer mode, Modern/Classic rules, map title where available, map size, AI difficulty (including mixed settings), kingdom count, start time in UTC, seed and full filename. New durations use the same clock as the results screen, excluding preparation, pauses and the finished results screen. Missing historical fields are labelled **Not recorded**, never estimated from file timestamps. The library reuses the last menu background image while its decorative 3D viewport remains stopped. A colour legend identifies the recorded kingdoms during playback, and the acting kingdom's colour appears in the action status.

New recordings retain exact kingdom names, UI colours and terrain colours, including authored map colours and unused identities that a later revolt can activate. Older Quick Play and multiplayer recordings recover their palettes from the saved seat assignments. Legacy files without any colour metadata use the original indexed palette; custom colours absent from an old recording cannot be recovered from that file.

Completed recordings are written through a temporary file and renamed after a successful write. A player movement cancelled during animation is discarded. New filenames use the compact format `20261024-214503Z_QP_Fern_STD_H_W_v0.1.0_s42.jsonl`: UTC start date/time, mode, played kingdom(s), map size, difficulty when recorded, result, game version and seed. The rules label is omitted. Map sizes are `T` (Tiny), `S` (Small), `STD` (Standard), `L` (Large), and `H` (Huge); historical Very Small maps use `VS`, and missing sizes use `U`. Modes are `QP` (Quick Play), `LM` (local multiplayer), `SM` (Steam multiplayer), `CM` (custom map), or `SP` (single player fallback). Difficulties are `E`, `N`, `H`, or `M` for mixed. Results are `W` (win), `L` (loss), `D` (draw), `W-kingdom` for a multiplayer winner, `F` (finished without a recorded winner), or `U` (unknown). Custom player names are included with their kingdom where available. Names are sanitized and length-limited for portable filenames; an existing name gets a `_2`, `_3`, etc. suffix. The saved metadata supplies these fields even if settings change before saving. Previously saved files keep their names and remain readable.

## Match results

Victory and defeat both open a paused results screen before island departure. The panel uses the same 0.24-second cubic slide/fade as event dialogs, with a shared animated blur and dim backdrop. Restart (looping arrow) and Save replay (floppy disk) are side-by-side icon buttons with localized tooltips. **Show map** hides results and enables normal camera pan, orbit, zoom and view switching; the match, statistics and clock remain finished. **Back to results** or Escape returns to the animated results screen. It shows soldiers slain/lost, cumulative conquered tiles, captured capitals, rounds played, and elapsed wall time (HH:MM:SS). Time includes player decisions, AI thinking and playback, but excludes map preparation, pause menus/options and time on results. Playback speed does not alter it; gameplay has no visible timer.

All unit tiers count as one soldier each. Losses include combat, spells, encounters, surrender and starvation; friendly merges and upgrades are excluded. Slain credits defeated enemies, including surrendered castle garrisons and both sides of knight duels. Starvation is a loss but is not assigned a killer. Tile totals include neutral/enemy captures, castle surrender and recaptures; bridge construction and capital relocation are excluded. Hotseat results let each local player select their faction's totals.

Statistics inspect immutable recorded changes once at completion, with no new board scans or disk operations added to each move. Replay format/readers remain compatible. Failed saves keep the in-memory recording available for retry; successful repeated clicks cannot create duplicate files.

## What is recorded

Capital relocations record the old and new city hexes and the charged price.
The position also stores relocation counts per color, so escalating costs survive
territory splits and capital replacement in reconstructed matches. Visible chest
rewards live on their province records; collection and treasury changes are part
of the capture command. Older recordings without these fields remain readable.

Readers and writers accept replay files up to 64 MiB and uncompressed detail
tapes up to 256 MiB. Oversized imports are rejected before parsing/decompression
can grow without a bound; oversized saves report an error and retain the in-memory
recording. Malformed state patches are rejected before any section is applied.

The first JSON line identifies format version 2, rules, seed, names, human seats, checksum and the timeline's column labels. Each subsequent action has its own readable line: the action name followed by `[sequence, round, faction, arguments]`. Hexes use short `q,r` coordinates. Long routes and separate AI diagnostic annotations are omitted from this readable view and retained in full in the compressed details.

The last JSON line holds the complete reconstruction tape compressed once with gzip and encoded as base64. Compressing the tape together shares repeated board/field data across the whole match. Position hashes are regenerated from the exact state tape rather than stored redundantly at every action; a SHA-256 checksum protects the tape before reconstruction. All original header, state, command and diagnostic fields are recovered by the readers. Numerical values are preserved; JSON whitespace and integer-valued number formatting may change.

The full header retains recruitment prices/wages, map size, human/AI seats, names, difficulty, turn order and the exact starting position, including authored maps and hidden encounters. Names entered for hotseat seats are included in shared files.

Full records contain numbered commands with round, faction, controller, arguments, changed state and a position hash. They cover movement, captures, merges, mutual Knight deaths, blocked attacks, purchases/upgrades, construction, development, spells, encounter reveals/choices, settlement, starvation, tree growth and match results. AI annotations include its chosen command, score, algorithm and search counts/timing. Turn boundaries include treasury, income and wages for each kingdom. Random outcomes and the exact 64-bit RNG state are retained. Sequence numbers in the readable timeline may skip diagnostic-only records.

Only live rules record actions; simulated AI search branches are excluded. State deltas let the viewer and analysis reconstruct recorded positions independently of later balance or AI changes, without rerunning the old AI or relying on its timing.

During play, the recorder keeps native changed records and command arguments in memory. It does not serialize or hash the whole board per action. Encoding, compression and writing happen only when the player chooses Save replay after the match finishes; position hashes are generated when inspecting a recording. See [the frame-stall investigation](replay-performance-2026-10-15.md) for measurements and the implementation tradeoff.

## Inspect a recording

From the project directory:

```powershell
python tools/replay_report.py "C:\path\to\game.jsonl"
python tools/replay_report.py "C:\path\to\game.jsonl" --at 120 --position artifacts/position-120.json
python tools/replay_report.py "C:\path\to\game.jsonl" --output artifacts/game-report.txt
python tools/replay_report.py "C:\path\to\game.jsonl" --expand artifacts/full-details.jsonl
python tools/replay_report.py "C:\path\to\legacy-completed-game.jsonl" --compact artifacts/compact-game.jsonl
```

The report verifies the archive checksum and timeline and summarizes decisions, housing, starvation, deployment space and turn finances by faction. `--at 0` reconstructs the starting position; any other sequence number reconstructs that point in the game. `--expand` writes every original detail record in ordinary JSON Lines; `--compact` converts a completed legacy replay while preserving its data. The Godot reader is `ReplayLog.read_replay(path)`; its decoded position retains hex coordinates and integer dictionary keys. Both readers support version 1 and version 2. Legacy files can recover a valid prefix after an interrupted final line; compact files require their complete details footer. Parse errors, broken sequences, checksum failures and timeline mismatches are rejected.

For strategic review, compare the same moments from both perspectives: income investments versus army timing, unused gold, threatened capitals, missed attacks, stranded armies, overextended borders and failed follow-up moves. A few human games can identify concrete mistakes; improvements still need regression checks and more games to establish that they generalize.

## Housing policy

Houses continue to occupy their tiles. AI investment now preserves at least two permanent deployment sites, scaling to a quarter of the kingdom's land with a maximum reserve of six. A house also requires at least three currently unoccupied/unblocked deployment sites before it is built, leaving two afterward. Capitals count because recruitment on them is legal. Trees/graves count because recruitment clears them; mountains do not.

The AI stops proposing houses once spare income covers a reinforcement of the rank needed against its frontier plus two Scouts. Threatened sites are excluded as before. If more income is needed while space is scarce, development remains available. This policy applies to all difficulties and both AI planning backends. It prevents further housing congestion; it does not demolish previously built houses or guarantee that an army already occupying every reserved site always has a vacant tile.

# Recorded games and AI analysis

After a win, loss or draw, the results screen offers **Save replay**. This applies to Quick Play, editor maps and hotseat. Recording begins from the actual starting board in memory; finishing a game does not create a file. Choosing Save replay writes one `.jsonl` file. Leaving the results screen without saving discards the recording, as does restarting, leaving, closing or abandoning an unfinished game. The tutorial is excluded because its lessons deliberately reset the board.

Open **Options → Replays → Open replay folder** to find recordings. On Windows the normal folder is `%APPDATA%\Godot\app_userdata\SlayGame\replays`. Share the files from a few wins, ideally alongside any losses and a short description of what felt exploitable. Files stay on your computer; nothing is uploaded automatically. You can delete older recordings from that folder.

Completed recordings are written through a temporary file and renamed after a successful write. A player movement cancelled during animation is discarded. The filename includes the date, map seed and a unique session suffix. Previously saved legacy files are still readable and are not deleted automatically.

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

Only live rules record actions; simulated AI search branches are excluded. State deltas let analysis reconstruct recorded positions independently of later balance or AI changes, without rerunning the old AI or relying on its timing. This is an analysis replay format; there is currently no in-game replay viewer.

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

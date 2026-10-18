# Follow-up replay: Knights, a successful supply cut, and remaining gaps

Replay: `2026-10-15T21-42-08-754105633-1156990478.jsonl`.

The archive fully validates: **Hard, Modern, Large, 295 initial tiles**, player victory in round **14**, 1,174 recorded commands including diagnostics. The Huge-map feedback is a separate scale/usability observation; this recording is not a Huge game. Its automatic AI selection uses the smaller-map lookahead planner.

## What changed in actual play

Three opponents obtained Knights. Ochre's first appeared in round **4**, Cove's in round **5**, and Aster's in round **7**; the player's first appeared in round **5**. AI Knight purchases/upgrades totalled seven, with additional strength possible through merges. In the earlier supplied Large game, no opponent ever obtained a Knight. Different seeds and map tile counts prevent treating this as a controlled strength comparison, but the missing Knight capability is now present in real play.

The most important new event is a successful, explicitly planned AI supply cut:

- **Round 12, move sequence 1088:** Aster moved a Scout from `(4,10)` to `(5,3)`.
- Its decision annotation, sequence 1089, says **“cut enemy supply.”**
- The capture split the player's bank without capturing the player's capital.
- The detached 24-tile kingdom at `(16,-5)` had **0g treasury, 52g income and 153g wages** immediately after the cut.
- At the player's next settlement in round **13**, all **15 units** in that bank starved: **6 Scouts, 6 Soldiers and 3 Knights**. Their total upkeep is exactly 153g.

This is a concrete success for the new starvation tactic, not an inference from a move near the frontier. Aster also recorded a supply-cut choice in round 10 at `(6,3)`, but that earlier choice alone does not establish the same outcome.

AI bridge spending was limited to **one bridge**, built by Tide. It reconnected friendly banks. The player later crossed it four times; that later use is not itself a justification for its construction. There was only one AI house, so housing congestion was not the main issue in this game.

## Why the player still recovered

The AI never captured the player's capital. After the decisive cut, the retained 140-tile bank still had **255g income against 45g wages** at that moment. The large surviving tax base made replacing the lost army possible. The AI inflicted a major local loss without converting it into a decisive attack on the remaining economic centre.

The player made **149 movement commands**, **50 recruitment/upgrade purchases**, and **13 Trailblaze casts**. Purchases were 18 Scouts, 26 Soldiers and 6 Knights. The player's **33 capital captures** were divided between **20 Soldier attacks and 13 Knight attacks**; captured capital defense was strength 1 in 25 cases and strength 2 in eight. Capital pursuit and extra movement remained effective despite the stronger opposition.

Military composition is still uneven. Tide purchased 23 Scouts and no higher rank; Ember purchased six Scouts and two Soldier upgrades. Neither captured enemy land. In contrast, Aster and Cove captured 27 and 19 enemy tiles. Those are useful positions for the next recruitment/strategic-direction investigation, but counts alone cannot establish which higher-rank purchase was affordable and useful at each decision.

The next AI investigation should focus on converting a successful cut into pressure on the surviving bank, protecting the AI's own armies from fragmentation, and explaining the opponents that remain almost entirely Scout-based. No further AI changes were made with this replay; this turn adds the requested Huge warning and records the evidence.

## Thinking time in the recording

The replay contains 391 AI decision annotations:

| Decision kind | Count | Median recorded search | 95th percentile | Maximum |
| --- | ---: | ---: | ---: | ---: |
| Preparation | 172 | 19.15 ms | 28.38 ms | 47.04 ms |
| Movement | 219 | 1,078.32 ms | 1,605.06 ms | 1,736.51 ms |

Recorded search times total roughly **3.32 seconds for preparation** and **172.95 seconds for movement** across the whole match. This identifies lookahead movement as the thinking-time cost in this recording. It is not rendered frame-time telemetry, does not establish an FPS regression, and does not implicate replay file writes. Moving the strategic planner to smaller maps would be a separate policy/strength tradeoff requiring matched tests.

## Huge-map warning

Huge now displays **“Demanding”** in the shared size label. Quick Play and multiplayer show a visible amber message on selection:

> Warning: Huge maps can slow the game and require extensive micromanagement.

The same message appears in shared size tooltips, including editor size choices. It clears when switching to another size. The English source and blank translation template include both new entries; no translations were supplied. There is no additional confirmation dialog and the map dimensions are unchanged.

Verified the two setup views natively at **960×620**, with screenshots in `artifacts/huge-warning-quickplay.png` and `artifacts/huge-warning-multiplayer.png`. All affected checks passed: warning **8**, menus **46**, multiplayer setup **41**, multiplayer maps **36**, UI layout **198**, localization **32**. The 708-message catalogue also passed its consistency check.

Raw evidence: `artifacts/user-replay-2026-10-15T21-42-08.txt`, `artifacts/player-replay-followup/summary.json` and `artifacts/player-replay-followup/tactics.json`. Original replay untouched; earlier three-game analysis artifacts preserved separately.

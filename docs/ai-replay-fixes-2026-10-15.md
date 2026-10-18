# AI fixes from the player's replays

15 October 2026. Implements the follow-up to `player-replay-analysis-2026-10-15.md` and the player's observations about hole-filling bridges, missing Knights and encirclement.

## Behaviour changes

**Recruitment buys an actual capability.** Both planners now use the same bounded purchase policy. It estimates accessible targets a new unit could capture, the extra targets an upgrade opens, capital and supply-cut value, defensive needs, the real purchase cost and the added wages. A bounded campaign premium recognizes that breaching a defended frontier enables more than one future capture. The first rank that can break a defense receives additional credit when the ready army lacks that capability, including on poor border tiles; that credit disappears once the army already supplies the strength. Excess strength receives a large discount when a cheaper tier solves the target. Useful Soldiers and Knights no longer have to overcome a static wage penalty without credit for the attack they enable.

**Useful ranks survive shortlisting.** The best useful candidate for each rank is retained before filling the remaining alternatives. Total candidate limits remain 5/7/9 and preparation limits remain 4/8/12 for Easy/Normal/Hard. Affordability still uses each individual kingdom's bank. Easy/Normal require nonnegative income after added wages; Hard retains its existing three-deficit-ticks-plus-10g reserve requirement.

**Bridges must add access.** A bridge inside an already connected ring receives zero access value and is excluded. New neutral/enemy shores and reconnections between separate friendly banks receive credit, with construction cost included. Existing bridge chains are considered, and duplicate shore/bank credit is removed. Traversal counts are no longer treated as evidence that the original investment was useful. This is a local access policy; it does not plan long speculative sequences across open water.

**Supply cuts are tactical objectives.** Both movement planners now value captures that separate enemy land from its capital. An iterative articulation analysis estimates the detached components' income, wages and army value, as well as whether losing the income bankrupts the retained capital's bank. Existing bridge routes count as alternative economic connections. Strong supply cuts receive an explicit decision reason. Independent queued orders continue through normal authoritative validation; supply priorities refresh at the next ordinary replan. Capital captures and other existing major events still invalidate orders immediately. This avoids restarting faction-wide assignment for every local cut.

Settlement happens before movement. The strategic counterattack check excludes units predicted to starve in the detached or retained component before they can move. It retains threats from a detached but self-supporting army. For detached components, the estimate conservatively allows income recovered by clearing a new capital's terrain. Opponents may still change the position before the target faction's activation; this is a current-position forecast, not a forced outcome through every rival's turn.

**Capitals get earlier protection.** A capital one friendly approach behind the frontier is treated as exposed when at least two sufficiently strong units from the same opponent can breach and follow up. Recruitment, positioning and position evaluation use this additional signal. Projected exposure is weighted below an immediate attack. Soldiers can protect adjacent land, but Knight protection is capped at Soldier strength on neighbouring tiles, matching the actual rules.

Knight price remains **40g**, and wages remain **3 / 9 / 27**. No combat, capital relocation, territory, house occupancy or replay-format rules changed.

## Keeping thinking time bounded

The smaller-map planner no longer clones and scores whole boards for each purchase. Both purchase backends use cached analytical opportunities instead. Preparation on the strategic backend skips movement-objective construction that would immediately be discarded.

Supply analysis runs once per queried bank per immutable query context, using an iterative depth-first pass, subtree resource sums and discovery intervals. It does not simulate a board for each possible cut and does not recurse through large islands. Recruitment opportunities are shared across matching movement regions, old/new ranks and deployment sites. Bridge shores and threat forecasts are cached within the same immutable position.

Movement search depths, beam widths, strategic per-unit limits, command validation and worker-thread ownership remain unchanged. No analysis or file serialization was added to the live replay path. Cancellation remains between bounded planner steps. Timing evidence is recorded separately from assertions about tactical correctness.

## Verification

`tests/test_ai_tactics.gd` covers an affordable Knight that can actually breach a Soldier-protected frontier, avoiding Knights when cheaper units suffice, retaining every useful rank, rejecting enclosed-hole bridges, preserving offensive crossings and bank reconnections, and protecting a capital before a two-unit breach. Supply fixtures execute captures and the actual next-turn settlement to verify starvation; they also cover adequate detached income, retained-bank reserves and alternate bridge routes. Both movement planners pursue the profitable cut. Available reconstructed replay fixtures additionally check the earlier missed Soldier opportunities.

`tools/ai_replay_balance_probe.gd` reruns all 57 selected real positions, two identical Huge/120-unit faction-turn starts, and two matched-seed Small eight-round self-play games before/after the change. Those self-play games change every participant's policy; they demonstrate resulting play and runtime, not a head-to-head strength rating. `tools/ai_tactics_worker_probe.gd` checks asynchronous preparation and movement on 120/300/600-unit Huge fixtures.

All **42 game regression suites passed**. After the final tuning, the six directly affected suites passed again: AI **186**, housing **10**, new tactics **40**, strategic AI **2,509**, army optimization **1,129**, and replays **98** checks. The earlier optimization suite's old-policy equivalence assertion now permits the intentional supply/approach changes while retaining equivalence elsewhere, authoritative movement legality and candidate limits.

### Replay-position results

All 57 selected preparation positions ran successfully. The new first choices include:

- Small 127: the 10g Scout-to-Soldier upgrade at `(1,2)`, replacing the bridge choice.
- Small 174: Soldier recruitment, replacing a Scout purchase.
- Large 409: a Soldier purchase; the previously excluded useful Soldier rank now survives shortlisting.
- Large 371: useful Soldiers remain available, but the new policy prefers a Knight for the position's stronger tactical opportunity. Shortlist repair does not force every formerly omitted Soldier to be purchased.

Across these selected positions, Small chose three Soldiers and one Knight; Large chose nine Soldiers and nine Knights; Huge chose two Soldiers and six Knights. These are first purchase decisions at separate checkpoints, not purchases made consecutively in one game. The remaining choices include Scouts and towers. None selected a bridge first; legitimate access/reconnection cases remain covered by explicit fixtures.

### Thinking time

Godot 4.6.3 headless, same host and starting positions. Times include planner construction and synchronous execution. Samples are the selected real replay positions, not an unbiased workload distribution.

| Preparation decision | Positions | Before median | After median | After maximum |
| --- | ---: | ---: | ---: | ---: |
| Small | 5 | 26.57 ms | 7.86 ms | 8.55 ms |
| Large | 25 | 67.71 ms | 18.12 ms | 22.82 ms |
| Huge | 27 | 68.53 ms | 61.06 ms | 93.80 ms |

Purchase selection is about **3.4–3.7 times faster** on the smaller-map planner in these samples. That does not imply every full turn is faster:

| Full Hard Huge faction turn, 120-unit board | Before | After | Actions before → after | Final land before → after |
| --- | ---: | ---: | ---: | ---: |
| Seed 42 | 1.712 s | 2.088 s | 49 → 50 | 197 → 187 |
| Seed 71 | 1.249 s | 1.496 s | 40 → 31 | 152 → 137 |

These two full turns are **20–22% slower**, adding about **0.25–0.38 seconds**. The new movement analysis and different purchases/plans cost time despite cheaper preparation. They also take less land in this single phase, so neither speed nor strength should be presented as an across-the-board improvement. A prototype that restarted faction-wide assignment after every valuable cut was removed; independent validated orders continue instead. Search limits were not increased.

In the two eight-round Small self-play comparisons, elapsed simulation time fell from **11.61 → 7.23 s** and **8.74 → 6.30 s**, with different action sequences and outcomes. Final Knight counts changed from **0/0** to **4/3** across the two games. This confirms escalation now occurs in normal play; because every participant's policy changed, it does not establish a win-rate gain against the old AI or a human.

The final asynchronous Huge worker checks measured:

| Units on board | Preparation wall time | Movement assignment wall time | Movement orders |
| --- | ---: | ---: | ---: |
| 120 | 73.92 ms | 56.55 ms | 12 |
| 300 | 67.87 ms | 70.40 ms | 26 |
| 600 | 68.67 ms | 84.31 ms | 49 |

The headless main loop serviced **8–12 frames during each search**. Maximum movement worker steps were 19.86–27.60 ms; preparation's single analytical pass took at most 64.22 ms on the worker. These are planning/responsiveness observations, not native rendered FPS measurements or complete opponent-round durations.

Raw reports: `artifacts/ai-replay-balance-before.json`, `artifacts/ai-replay-balance-verified.json`, `artifacts/ai-tactics-worker.json` and `artifacts/ai-balance-full-suite-console.txt`. Final affected-suite logs end in `-tactics-final.log`. Earlier `after`, `final`, `retained-orders` and `local-cuts` balance reports are tuning stages; `verified` is the delivered implementation.

## Limits

Purchase evaluation is purpose-aware but analytical, not an exhaustive purchase-and-opponent-reply tree. Supply analysis identifies cuts caused by one capture; it does not search every multi-move encirclement. Capital forecasts cover a breach plus follower rather than an arbitrary attack chain. These bounds are intentional to keep turns short. Human replay follow-up remains the best way to check whether the changes close the observed strategic gaps without making the AI predictable in a new way.

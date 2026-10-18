# Why the player won these three Hard games

15 October 2026. Analysis of the three supplied completed replays. No game rules or AI behaviour changed as part of this investigation.

**Follow-up:** the player correctly pointed out that crossing a bridge does not establish that building it was useful: many bridges filled single-tile holes. The usage counts below are evidence of traversal, not a measure of marginal access or offensive value. Subsequent implementation assesses new frontier access and bank reconnections explicitly. See `ai-replay-fixes-2026-10-15.md` for the resulting changes and tests.

## Main finding

The repeatable advantage was **turning income into an army that could break defended territory, then pursuing capitals**. The AI often had resources, but failed to turn them into the right strength of unit soon enough. Once a capital fell, annexation and fragmentation created opportunities to capture replacement capitals in the same turn.

There are two concrete AI implementation problems behind this: purchase scoring penalizes stronger units before considering their attack, and purchase shortlisting can discard an entire useful unit tier. The larger-map planner has a different purchase policy, so repairing the smaller-map scorer alone will not solve every case.

These games justify targeted AI improvements before another economy nerf. They do not establish a general win rate or prove any proposed replacement policy would beat the player.

## Games and player strategy

All three games were on **Hard**, with automatic planner selection. Small and Large used the lookahead planner; Huge used the strategic planner. The automatic threshold is 750 cells.

| Replay start | Map | Initial tiles | Victory round | Recorded commands, including diagnostics | Player capital captures | First player Knight |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 20:18:44 | Small | 83 | 7 | 248 | 7 | Round 3 |
| 19:35:58 | Large | 251 | 11 | 900 | 31 | Round 6 |
| 20:11:46 | Huge | 1,110 | 13 | 1,561 | 68 | Round 8 |

Capital capture totals include replacement capitals after land splits or relocation. They are not counts of independent starting kingdoms.

| Player spending and attacks | Small | Large | Huge |
| --- | ---: | ---: | ---: |
| Recruitment and upgrades | 90g | 390g | 1,070g |
| Land development | 8g | 14g | 2g |
| Houses | 0 | 0 | 0 |
| Purchased Scouts / Soldiers / Knights | 6 / 3 / 0 | 12 / 13 / 2 | 42 / 30 / 3 |
| Capital captures by Soldiers / Knights | 4 / 3 | 22 / 9 | 63 / 5 |
| Enemy land captures | 18 | 67 | 141 |

Purchases include upgrades; merges are additional sources of stronger units. On Small, all three purchased Soldiers were upgrades, and the first Knight came from a merge. On Huge, the offensive was overwhelmingly Soldier-led: 63 of 68 capital captures. A diagnosis of “the player wins by rushing Knights” would miss the main pattern.

You spent little on increasing existing land's output. Instead, expansion and capture increased your tax base, and you spent on units that could keep taking land. On Huge, your turn-start income grew from 18g in round 2 to 163g in round 7 and 659g in round 13. Final wages were 357g: the army was expensive, but the growing territory paid for it.

## Confirmed problem: the purchase scorer cannot see the attack it buys

The Small/Large planner evaluates each purchase immediately. Its purchase search stops after that layer, even on Hard; the deeper movement search happens separately. Consequently, the purchase decision pays the wage penalty before seeing the offensive opportunity.

In `src/game/ai_analysis.gd`, unit values are 10 / 21 / 38, net income contributes 2.2 points per gold, and treasury contributes 0.12 points per gold. With current wages 3 / 9 / 27, the isolated score changes are:

| Action | Unit value gained | Income penalty | Purchase penalty | Net score change |
| --- | ---: | ---: | ---: | ---: |
| Recruit Scout for 10g | +10 | −6.6 | −1.2 | **+2.2** |
| Recruit Soldier for 20g | +21 | −19.8 | −2.4 | **−1.2** |
| Upgrade Scout → Soldier for 10g | +11 | −13.2 | −1.2 | **−3.4** |
| Upgrade Soldier → Knight for 20g | +17 | −39.6 | −2.4 | **−25.0** |
| Develop value-1 land for 2g | — | +2.2 | −0.24 | **+1.96** |

These are baseline components, not universal final scores: threats, terrain, survival and other position terms can change the outcome. Nevertheless, they explain why the AI repeatedly favours Scouts or development over an affordable upgrade that would enable an attack.

The actual games support this diagnosis. On Small, the AI bought only Scouts, made one Soldier through merging, and never obtained a Knight. On Large, none of the five opponents ever obtained a Knight. Combined development spending was 108g on Small and 288g on Large, versus your 8g and 14g respectively. Those totals combine multiple opponents and should not be read as a per-player efficiency comparison.

### Tests in reconstructed positions

I restored **57 selected AI preparation positions** from the real games into the current rules engine: 5 Small, 25 Large and 27 Huge. For each bank and unit tier, the diagnostic tried the cheapest legal sustainable purchase or upgrade, then a bounded selection of legal immediate captures. It also ran the current planner's first purchase decision. Hidden encounter identities were masked exactly as in normal AI snapshots.

In **11 positions**, a Soldier purchase had a negative immediate evaluation but a positive evaluation after a legal capture, and opened enemy targets unavailable to the existing ready army. This occurred in 3 Small, 7 Large and 1 Huge positions.

Selected examples below use the replay command sequence as a reproducible reference. Score changes compare with the same pre-purchase position; they are internal evaluation points, not gold or predicted win probability.

| Map / sequence | Round / AI faction | Current first choice | Soldier purchase alone | Purchase + tested capture | Newly accessible enemy targets |
| --- | --- | --- | ---: | ---: | ---: |
| Small / 127 | 3 / Ember | Bridge | −13.52 | +24.30 | 4 |
| Small / 174 | 4 / Ochre | Scout | −3.40 | +13.57 | 2 |
| Large / 326 | 4 / Ember | Tower | −3.40 | +20.25 | 3 |
| Large / 371 | 4 / Ochre | Tower | −3.40 | +18.07 | 2 |
| Large / 409 | 4 / Cove | Bridge | −3.40 | +12.80 | 1 |
| Huge / 396 | 4 / Aster | Bridge | −3.40 | +7.20 | 1 |

For example, Small sequence 127 had 25g and 19g net income. A 10g Scout-to-Soldier upgrade at `(1,2)` was sustainable and opened four enemy captures. The current planner instead selected a bridge. The experiment demonstrates a missed opportunity; it does not prove the tested capture was globally optimal or that a bridge had no future value.

## Confirmed problem: useful ranks disappear before evaluation

`src/game/ai_candidates.gd` retains at most two entries per action kind. All recruitment ranks share the `recruit` kind, so Scout or Knight candidates can consume both slots and remove Soldiers entirely. Hard's larger overall candidate budget does not prevent this.

The useful Soldier alternatives in **Large sequences 371 and 409** were absent from the shortlist. Adjusting score weights cannot repair an option the planner never sees.

The candidate generator also chooses a kingdom-wide required tier from its toughest frontier target. This can overlook the cheaper Soldier suited to a different, weaker target. Candidate selection should preserve different tactical roles and ranks rather than filling both recruitment slots with variants of one role.

## Capitals amplify the first breach

Of your 106 capital captures, **97 faced defense strength 1**, and the remaining 9 faced strength 2. No captured capital had a Knight standing on it. This does not mean every capital needed an expensive permanent garrison; it shows how often your existing Soldiers could continue the attack.

Examples of the resulting cascades:

- Large, round 11: nine capital captures against Ember in one turn.
- Huge, round 12: seventeen capital captures against Ember; another fourteen in round 13.
- Huge, Ember's first lost capital in round 11: Soldier versus defense 1, destroying a 72g treasury.

The AI needs to value the territory, bank and follow-on attack exposure behind a threatened capital, not merely the next border hex. It should prepare before a corridor opens and reassess after every capital loss or kingdom split.

Code inspection did **not** find a simple “enemy has already moved, therefore ignore it next turn” error: threat queries include spent enemy units. The more relevant limitation is that immediate boundary threats do not fully describe a breach followed by several captures. A defensive counterfactual has not yet demonstrated which particular garrison would have saved these games; that needs separate tests.

## Huge uses a different spending policy

The strategic planner selects preparation actions by candidate priority rather than the lookahead planner's purchase evaluation. Therefore the negative score arithmetic above directly explains the Small/Large purchase problem, but is not the direct cause of Huge's purchase selection.

On Huge, Ember purchased **35 Scouts, 5 Knights and no Soldiers**. It did obtain some Soldiers through merging, but its first Knight arrived in round 11, three rounds after yours. Target-specific recruitment and a shared opportunity-aware spending policy are better directions than merely increasing a global army-strength preference.

Not every stronger purchase was useful. Some restored positions had no new enemy targets for a higher tier; paying extra wages there could make the AI worse. Recruitment should buy a concrete offensive or defensive capability.

## What the evidence does not support

**Housing was not the cause of these losses.** The supplied games do not show a house-spam bottleneck warranting a change to house occupancy.

**Bridge traversal does not establish investment value.** Huge Ember built twenty bridges for 300g, and subsequently crossed every one with its own army. That does not show that those bridges opened useful access: a bridge inside an already connected territory may be crossed without improving the kingdom's position. One Large example did reconnect friendly banks and open eleven targets, so legitimate reconnections should remain available. The fix should reject hole filling and score the extra access each bridge actually provides.

**Starvation counts alone do not prove reckless recruitment.** You lost no units to starvation on Small/Large, and four on Huge; AI totals were four, eighteen and eleven. Captured capitals and split banks can strand an otherwise affordable army. A future classifier should separate that outcome from buying unaffordable units before blaming wage management.

## Recommended implementation order

1. **Make purchases evaluate their purpose.** Compare a bounded purchase-plus-attack sequence, including the opponent's credible reply on Hard. For defensive purchases, measure the avoided capital/territory loss. Keep sustainability checks and the current wages; do not solve this by forcing Knights everywhere.
2. **Keep meaningful recruitment options.** Preserve useful rank/role alternatives within the candidate budget. Prefer the cheapest tier that solves each target, including upgrades and merges.
3. **Share the purchase policy between both planners.** Keep the strategic movement planner on Huge, with bounded work and the existing worker-thread architecture. Do not bring replay serialization or whole-game analysis into live move processing.
4. **Anticipate capital cascades.** Include exposed approaches, replacement-capital vulnerability and the cost of fragmented banks in defense decisions. Test against the first-breach positions in these replays before changing capital rules again.
5. **Then measure whole-match strength and performance.** Replay these openings as tactical fixtures, run matched-seed games with both policies, and measure capture efficiency, surviving territory, bank losses, stranded armies, results and planning/frame times. Include opponents that punish overinvestment in expensive units. Evaluate bridges by actual access and use, not construction count alone.

The first acceptance tests should require the AI to consider the missing Soldiers in Large 371/409, recognize the sustainable attack in Small 127, retain useful bridge reconnections, and avoid upgrades that add wages without a useful target. Passing those is evidence of the intended repair, not proof of competitive strength against a human.

## Method, artifacts and limitations

The existing replay reader fully validated all three completed archives, reconstructed their state histories and confirmed player faction 0 as the winner. Additional extraction checked the compressed tape's SHA-256, readable decision lines and command ordering. Original files were left untouched.

New diagnostic tools:

- `tools/analyze_player_replays.py`: spending, unit timing, captures, defenses, bridge use and checkpoint extraction.
- `tools/player_replay_position_probe.gd`: restore selected positions and test current choices against legal sustainable purchases and bounded immediate follow-ups.

Evidence is in `artifacts/player-replay-analysis/summary.json` and `counterfactual-results.json`, with 57 checkpoint files and the probe log at `artifacts/player-replay-position-tests.log`. The standard per-game reports are `artifacts/user-replay-<original filename without .jsonl>.txt`.

The 57 positions were selected for diagnosis, including healthy bank states and preparations before first capital losses; they are not an unbiased sample. The probe tests one cheapest site per bank/tier and up to three follow-ups, not every purchase site or a full alternative match. Positive evaluation is evidence that the existing scorer misses its own future benefit, not an independent estimate of optimal play. No win-rate improvement is claimed, and no production AI changes were made in this investigation.

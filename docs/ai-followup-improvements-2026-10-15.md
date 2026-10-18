# AI follow-up: exploiting cuts, protecting supply and preparing for contact

Implemented from the fourth player replay, `2026-10-15T21-42-08-754105633-1156990478.jsonl`. See `player-replay-followup-2026-10-15.md` for the original evidence. No prices, wages, combat, map dimensions, territory or replay-format rules change.

## Changes

**Prepare for the army beyond the neutral buffer.** Tide's round-six bank had 64g, 87g income and 33g wages, but the immediate frontier mostly presented undefended neutral captures. That made another Scout look attractive while the player already had a Knight in the kingdom beyond the buffer. Recruitment now checks the visible armies that could retaliate against an expansion tile. The first affordable unit able to meet that strength receives a reserve-role premium. The premium disappears when the accessible ready army already supplies that strength. Troops already due to starve at settlement do not justify an expensive reserve.

This is a bounded frontier-and-adjacent-region check, not a search over every future recruitment sequence. The existing individual-bank sustainability guards still apply. It can choose a Soldier or Knight earlier without imposing a fixed army composition or buying Knights against Scout-only opposition.

**Protect the supply neck, not just its tile income.** A threatened border hex can be worth far more than its own tax yield when its loss separates an expensive army from the capital. Shared evaluation, recruitment, towers and movement defence now include that supply-cut risk. A local connected-neighbour check avoids a full articulation pass for ordinary convex border tiles; uncertain necks reuse the existing cached bank analysis. The strategic planner also prices the supply loss caused by moving away from a critical defender's position.

**Pressure the surviving economic core.** After the replay's successful cut, the player retained a large income-producing bank and could recover. Enemy targets now receive bounded campaign value based on their bank's income and treasury, with extra value at its capital. A bank whose army is already due to starve receives reduced urgency. Both planners use the same signal, and the strategic planner refreshes it from the current position rather than retaining stale campaign weights in cached objectives. Basic land/capital capture value remains, so bankrupt offshoots are not ignored entirely.

**Fix Hard's missing reply checks on short turns.** Previously, a branch with no remaining moves disappeared from the beam. If all branches finished before depth five, the beam became empty and Hard could return its earlier favourite without ever comparing the enemy's reply. Finished sequences now remain candidates within the existing beam width. When all sequences finish, Hard proceeds directly to the normal reply comparison. The baseline holding position receives the same replies.

**Make sampled replies relevant and respect settlement.** Hard skips opponents whose current armies cannot reach its territory in that sampled reply. Opponents with expiring barriers remain eligible because settlement can reopen a route. Relevant opponents begin their actual turn on the private snapshot before movement sampling: starvation, income, movement reset and barrier expiry use the authoritative rules. Every mutation discards the old query context. This prevents counterattacks by troops already killed at settlement and avoids assuming temporary barriers last into the opponent's turn.

No extra whole-faction replanning is triggered by each supply cut. Independent queued strategic orders still use normal live validation. Search depths, beam widths, per-node candidate limits, per-unit strategic limits and preparation decision limits remain unchanged. Live analysis stays on the worker; no replay serialization or disk writes were added to normal moves.

## Verification

The new `tests/test_ai_followup.gd` covers:

- Both backends choosing the rich surviving core over an already bankrupt offshoot.
- Both backends buying legal defence that actually prevents a threatened supply cut.
- Preparing a Knight for an enemy Knight beyond a neutral buffer, stopping the reserve premium once that role is filled, and avoiding expensive reserves against Scouts or already doomed troops.
- Tide's actual round-six position receiving an affordable Knight purchase.
- A short Hard turn checking a remote Soldier's retaliation after its barrier expires, rather than bypassing replies.

The army optimization suite still checks authoritative destination equivalence, legality and candidate budgets. Its historical policy-equivalence comparison allows the deliberate economic-pressure and supply-defence changes while retaining equivalence elsewhere.

`tools/ai_followup_probe.gd` inspects 18 selected positions from the replay. `tools/ai_followup_timing.gd` compares three samples of selected movement searches and matched Huge faction-turn starts against a preserved copy of the preceding AI. `tools/ai_followup_matches.gd` rotates one updated faction through every seat against three previous-policy factions, on two Small seeds for up to twelve rounds. Opponents use identical current game rules and resources.

The preserved baseline is under `artifacts/ai-followup-baseline/`; timing and match tools intentionally depend on that baseline. It is not loaded by gameplay. Replay checkpoints and results stay under `artifacts/ai-followup-*`, separately from the earlier replay investigations. The original supplied replay is unchanged.

### Final results

Twelve affected suites passed: new follow-up **22** checks, existing tactics **40**, AI **186**, strategic AI **2,513**, army optimization **1,129**, housing **10**, replays **98**, performance **458**, rebalance **39**, capital replacement **44**, Modern rules **10,695** and game rules **113,223**. The focused AI suites were repeated after the final reserve filtering/cache adjustment. Localization source consistency still verifies at 708 entries; no UI messages or translations were added.

All 18 selected replay checkpoints were inspected. Tide at sequence **557 / round 6** now chooses an affordable Scout-to-Knight upgrade instead of another Scout. Aster at sequence **1087 / round 12** retains the successful `(5,3)` supply-cut choice. At **1089**, its only surviving Scout has already moved, so returning no move remains correct; this change does not invent a follow-up army that was not present. The core-pressure regression fixture separately verifies the intended preference when an army can act.

Headless timing on the same host, preserved previous-policy modules versus the delivered code, three movement samples per position:

| Replay sequence | Previous median | Updated median | Interpretation |
| --- | ---: | ---: | --- |
| 557 | 1,073.63 ms | 908.62 ms | Expensive Tide search, fewer irrelevant reply branches |
| 644 | 903.80 ms | 737.66 ms | Expensive Tide search, fewer irrelevant reply branches |
| 937 | 159.45 ms | 314.56 ms | Additional reply coverage and different unit assignment |
| 1087 | 23.31 ms | 281.90 ms | Previously skipped short-turn replies now run; successful cut retained |
| 1089 | 13.77 ms | 8.47 ms | No ready unit; no movement branches |

The two heavy searches are approximately **15–18% faster**. This is not a universal speed improvement: repairing omitted reply checks adds real work to short turns. Neither depth nor width was raised. Timing samples record different policies, not identical moves guaranteed to run faster.

Matched full Hard Huge faction turns on 120-unit boards:

| Seed | Previous | Updated | Actions previous → updated | Final land previous → updated |
| --- | ---: | ---: | ---: | ---: |
| 42 | 1.570 s | 1.684 s | 50 → 50 | 187 → 186 |
| 71 | 0.974 s | 1.011 s | 31 → 31 | 137 → 143 |

The extra full-turn cost was about **0.11 s / 0.04 s** in these fixtures. Raw three-sample data, branch counts and decisions are in `artifacts/ai-followup-timing.json`. These are CPU/planning observations, not rendered FPS measurements.

Final asynchronous Huge checks on 120/300/600-unit boards took **42.60 / 63.58 / 70.69 ms** for movement assignment and **52.07 / 53.69 / 54.91 ms** for preparation. The headless main loop serviced 6–10 frames during these worker searches; maximum movement worker steps were 15.91–19.97 ms. Snapshot/worker ownership and cancellation checks passed. Raw data is saved separately in `artifacts/ai-followup-worker.json`, preserving the prior report's worker dataset. Reproduce with `tools/ai_tactics_worker_probe.gd -- --label=followup`.

Eight Small comparisons rotated the updated policy through all four seats on seeds 42 and 71, against three independent previous-policy opponents. At the end of up to twelve rounds, the updated faction led territory in **3/8**, survived in **4/8**, and was the sole territory holder in **2/8**. The starting positions matter strongly: the updated faction lost both seat-three games, for example. This is a small smoke comparison, not a reliable win-rate estimate or evidence of guaranteed difficulty improvement. Do not compare aggregate old/new timing or deaths without accounting for three old factions per game and different survival lengths. The output's `preparation_death_records` counts only visible preparation diffs and can miss a death followed by replacement on the same tile; it is not exact starvation telemetry.

Final match results: `artifacts/ai-followup-matches.json`. The separately retained `ai-followup-matches-initial.json` predates the short-turn reply repair and is not the delivered policy. Final checkpoint decisions: `artifacts/ai-followup-after.json`. Regression logs end in `-followup-final.log`.

## Interpretation limits

The reserve forecast uses visible current armies and current settlement finances. Another faction can change that state before the opponent acts. Supply analysis still focuses on cuts caused by one capture; it does not solve arbitrary multi-move encirclements. The campaign signal prioritizes valuable reachable targets rather than guaranteeing an entire attack on a distant capital. Reply pruning intentionally drops third-party moves that cannot directly threaten the AI in the sampled reply; that is a bounded tactical forecast, not full next-round simulation.

The rotated games are a small smoke comparison with one new-policy faction per game. They do not establish a population win rate or prove that Hard will beat the player. The concrete acceptance criteria are the corrected decisions and short-turn reply coverage, preserved legal/affordable commands, and measured thinking cost.

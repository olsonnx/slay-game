# Strategic AI for large maps

**16 October update:** automatic selection now starts at 200 actual cell records, covering Large, Very Large and Huge presets and similarly sized editor maps. Large-map Hard simulations reproduced growing midgame waits with the old backend (individual faction turns exceeding 11 seconds by turn 8). On identical crowded Large positions across three seeds, individual searches took about 0.3–1.6 seconds with the beam planner versus 11–29 ms with strategic assignments. Three nine-round Large/Hard simulations completed after the change, including Aster's turns 7 and 8. This is a planning-performance fix; the original reported position could not be reconstructed without its seed or replay. It does not establish identical playing strength between the planners.

**15 October update:** the [replay-driven AI fixes](ai-replay-fixes-2026-10-15.md) revise shared spending priorities, bridge access valuation, supply-cut objectives and breach protection. Independent queued orders retain normal validation and supply priorities refresh on replanning. The assignment budgets and worker architecture described here remain in place; measurements below predate that update.

Implemented 14 October 2026, following the [capture-update investigation](capture-updates-2026-10-14.md).

## Architecture and rollout

The existing beam planner remains available. With the default `ai_algorithm = "auto"`, boards with at least 200 cell records use the strategic planner; smaller boards retain the beam planner. Large, Very Large and Huge presets therefore use strategic assignments. Diagnostics can explicitly select `legacy` or `strategic`. This is an internal switch, not another technical option in the player interface.

The new planner works on an independent worker snapshot and builds faction objectives: protect threatened capitals, advance towards enemy capitals, secure mana sources, restore income when finances need it and merge units to breach defended frontiers. Units share accessible-region analysis and reserve distinct destinations. Stronger units are assigned first, with bounded local alternatives rather than complete cloned-board search branches.

Orders persist across ordinary movement batches. Local region and target data are always refreshed on a new immutable position; cached query objects are never reused after mutation. Major changes—castle surrender, merging, ward removal, duels, revealed encounters or renewed movement—discard pending orders. Changed capitals, bridges and barriers invalidate the strategic context. Exhausted or stale orders trigger a fresh assignment pass. Cached objectives extend to newly accessible frontier sites rather than rebuilding the same global search after every ordinary capture.

Local tactical checks account for the defence lost when a unit leaves, the support it will receive at its destination and remote hostile armies that could retaliate through adjacent regions. Knight trades require an available follower that can breach the remaining defence without abandoning critical protection. Unknown encounter identities remain masked during planning. No worker mutates live rules, consumes the game RNG or touches rendering objects.

The new preparation policy uses the existing legal purchase/spell candidates and affordability guards, choosing analytical priorities instead of simulating whole-board branches. Preparation decision limits remain 4/8/12. Movement alternatives per unit are bounded at 16/40/64 for Easy/Normal/Hard; Normal and Hard consider local retaliation, and Hard prices unsafe trades more strongly. **These are different difficulty policies from the legacy beam's depths 1/3/5**, not an equivalent cheaper execution of the same search. Legacy Hard's sampled whole-position replies remain in the legacy backend.

## Command and kingdom updates

Captures reconstruct the attacking and displaced factions' kingdoms rather than every faction. Unaffected banks remain intact, including the original full rebuild's cleanup of trees/graves at surviving capitals. The algorithm retains the original component traversal, capital selection, surviving-capital gold rules and board-order bank insertion. Full reconstruction remains available for generation, bridge topology, spells and diagnostics. Commands still validate against the authoritative current position.

The movement recorder accepts a route already validated immediately on the owning thread, avoiding a second identical route search. This internal path never accepts an unvalidated worker route. Strategic movement groups contain at most four commands; the asynchronous path yields between atomic commands and checks pause/closing before the next commit. Ordinary rules, movement legality, merge receiver movement status, spells and encounter resolution remain shared with the legacy planner.

Arriving units retain their original actor, picking sprite, shadow and unchanged rank markers instead of being destroyed and recreated at each animation completion. Defeated units still disappear and merges still update the receiver's movement status. Arrival observers can cancel synchronously without resurrecting the traveler. This reduces resource churn as the faster planner produces captures more frequently.

## Verification

The new strategic suite compares selective capture reconstruction with full reconstruction across generated Classic/Modern Huge fixtures and explicit bridge, encounter and castle cases. It checks every cell field, bank contents/order, mana, effects, pending encounters and RNG state. Planning checks cover deterministic assignments, unique reservations, authoritative legality, secret-event independence, capital protection, unsupported neutral captures, worker cancellation, bounded groups, retained objectives and pause/closing between cooperative commit phases.

All 31 regression suites passed during the implementation run. After final tactical, surviving-capital and actor-retention changes, the relevant AI, Modern rules, expansion, animation, input, rollback, heatmap, playback, turn feedback and batching checks passed again. The final strategic suite passed **2,509 checks**, and animation **44 checks**. Existing map determinism, editor, startup and shared menu checks also passed in the complete run.

## Decision quality and turn time

`tools/ai_strategy_compare.gd` runs both backends from identical Huge/120-unit snapshots, then rotates one strategic faction through four starting positions against three legacy factions on two Small seeds. Both backends use the updated command rules, so that comparison primarily measures policy/planning cost rather than comparing against the older full-rebuild implementation.

The recorded eight Small matches are ten rounds each (40 scheduled faction phases). They are a small smoke test, not evidence that the new policy is universally stronger. Short-term land gain, income, treasury, units, starvation and the old evaluator score are recorded separately. The old evaluator is useful for comparison but is not an unbiased proof of strategic strength.

| Huge single-faction turn | Legacy time | Strategic time | Legacy land gain | Strategic land gain |
| --- | ---: | ---: | ---: | ---: |
| Seed 42, 120 units, Normal | 17.49 s | 1.22 s | +27 | +18 |
| Seed 71, 120 units, Normal | 18.54 s | 0.97 s | +33 | +24 |

That is approximately **14–19× faster** in these two headless faction-turn fixtures. The new policy captured less land and scored lower under the old evaluator in both, so this is a clear speed gain with a measured decision-quality tradeoff, not equal-strength certification. Its final income was 1,026/828 versus the legacy 1,104/882; upkeep was 160/177 versus 161/176. Both use the same legal economy and wage guards.

In the final eight ten-round Small matches, the strategic faction finished with the most land in **2/8**, survived in **3/8**, and suffered **2 starvation deaths**. The three legacy factions together suffered 21 starvation deaths across three times as many scheduled phases. Those asymmetric totals do not by themselves prove superior economic play. Raw outcomes, treasuries, armies, scores and timing are in `artifacts/ai_strategy_comparison.json`; intermediate policy-tuning datasets are retained separately.

### Native 1080p rounds

Godot 4.6.3 Compatibility, i5-9300HF / RTX 2060, 1,000 tiles, seed 71, six factions, Normal, saved 8× MSAA, Water, shadows on, uncapped/VSync off. Playback is pinned to 6× and verified by recorded scale telemetry. Fixtures are synthetic crowded territories rather than normal economy-feasible endgames.

| Native workload / stage | Opponent round | Decisions | Mean FPS | p99 frame | Worst frame |
| --- | ---: | ---: | ---: | ---: | ---: |
| Previous capture pass, legacy / full reconstruction, 120 units | 123.21 s | 137 | 186 | 24.14 ms | 85.76 ms |
| Legacy with selective reconstruction, 120 units, earlier stage | 109.71 s | 137 | 196 | 23.88 ms | 82.30 ms |
| Strategic, 120 units, retained actors | 22.16 s | 145 | 172 | 36.04 ms | 74.85 ms |
| Strategic, 600 units, before actor retention | 90.37 s | 374 | 165 | 38.30 ms | 125.86 ms |
| Strategic, 600 units, retained actors | 85.42 s | 374 | 215 | 30.45 ms | 81.55 ms |

The new 120-unit round is roughly **5× shorter** than the retained-legacy sample, with a different sequence and slightly more decisions. However, mean/p99 FPS did not improve: captures are concentrated into a much shorter interval rather than separated by long searches. **This is not stable 240 FPS.** The old full-reconstruction sample timed whole movement groups at 27.37 ms average / 59.24 ms peak; the first strategic native sample timed individual atomic commands at 5.52 ms / 12.94 ms. These are different transaction sizes: the reduction in blocking duration comes from both narrower kingdom work and cooperating between commands.

The two 600-unit runs retain the same 374 decisions and 139 terrain builds. Actor retention preserves the traveler object and avoids unnecessary marker rebuilding; the later sample has lower frame tails, but separate native runs also have environmental variance. The final dense run's median frame is **3.48 ms**, p95 **12.03 ms**, and **25.97%** of frames miss the 240 FPS budget. Its atomic rule commits average **4.13 ms**, peak **13.52 ms**. Tile updates average **1.34 ms**, peak **5.71 ms**. Army sync still peaks at **22.20 ms**, and owning-thread snapshots at **7.84 ms**. Those presentation/snapshot tails remain meaningful work.

### Worker assignment latency

| Huge units | Normal | Hard | Normal / Hard queued orders |
| ---: | ---: | ---: | ---: |
| 120 | 40.46 ms | 43.03 ms | 11 / 12 |
| 300 | 55.68 ms | 64.27 ms | 26 / 26 |
| 600 | 88.62 ms | 83.24 ms | 48 / 48 |

The largest worker step is **22.54 ms** across these samples. Legacy Hard previously took 6.75 seconds for its 600-unit search, but that was a depth-five beam/reply search returning a short sequence; the new pass assigns many units with local tactics. It is a different policy and workload, not an equivalent search sped up 80×. These worker runs last only 40–89 ms, so their recorded FPS/p99 values are too short to establish sustained rendering performance. Owning-thread snapshot time remains 4.4–7.1 ms in those samples.

Native datasets are under `artifacts/map_stress_heavy_*strategic*.json` and `*legacy_selective.json`. The final dense file is `map_stress_heavy_turn_normal_600_strategic_retained_actors.json`, worker results `map_stress_heavy_ai_strategic_final.json`, and final 120-unit file `map_stress_heavy_turn_normal_120_strategic_retained_actors.json`. Reproduce a turn with `--path . --script tools/heavy_strain_probe.gd -- --mode=turn --algorithm=strategic --difficulty=normal --units=600 --turn-limit=180 --label-suffix=strategic_retained_actors`; change `--algorithm=legacy` for the reference planner. `--mode=ai` measures a worker assignment/search on 120/300/600-unit boards.

## Remaining limits

The strategy backend deliberately trades exhaustive whole-position lookahead for reusable objectives and local tactics. It can make different, weaker choices; retaining the old backend and reporting quality outcomes is essential. More seeds, longer games, fragmented kingdoms, bridge-heavy maps and difficulty matchups are needed before claiming equal or superior strength.

Individual commands are still synchronous. A faction containing most of the island can still require a large connectivity reconstruction, and global turn settlement/spells can use the full path. Graphics, visible economy readouts and snapshot creation also have their own frame costs. Faster planning does not establish an every-frame 240 FPS guarantee.

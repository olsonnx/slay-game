# Enemy AI — 12 October 2026

**16 October bridge follow-up:** [Ember replay fixes](ai-bridge-campaign-fixes-2026-10-16.md)
preserve useful short Hard plans, match recruitment to uncovered jobs, reward
affordable bridge campaigns and price demolition against lost access. Movement
shortlists retain distinct destinations/ranks. Hard checks up to seven reply
positions; the other search budgets and worker architecture remain unchanged.

**Latest follow-up:** [core pressure, supply defence and short-turn reply fixes](ai-followup-improvements-2026-10-15.md) extends the shared policy with a combat reserve for visible threats beyond a neutral buffer. Hard now checks replies for short finished sequences, settles relevant opponents on snapshots, and skips unreachable replies while respecting barrier expiry. Depth/width/candidate budgets and worker ownership remain unchanged. See that report for current verification and measured timing tradeoffs.

**15 October update:** both backends now share purpose-aware analytical purchases, retain useful recruitment ranks, reject hole-filling bridges, anticipate a two-unit capital breach and value supply cuts. Purchase search no longer applies the static evaluator to isolated purchases. See [replay-driven AI fixes](ai-replay-fixes-2026-10-15.md) for the current policy and measurements; older purchase descriptions and timings below are historical.

This document describes the retained beam-search backend. The [large-map strategic backend](strategic-ai-2026-10-14.md) is now selected automatically for boards with at least 200 cell records; it uses different movement and difficulty policies while retaining the same authoritative rules.

The shared planner replaces the original shuffled checklist. Difficulty is selected in Quick Play, defaults to Normal and is remembered for future matches. Match difficulty remains independent of that preference: restart and rules changes preserve it. Legacy or malformed saved difficulty values load as Normal.

## Profiles

| Profile | Movement depth | Beam width | Candidates per node | Preparation decisions per turn |
| --- | ---: | ---: | ---: | ---: |
| Easy | 1 | 1 | 5 | 4 |
| Normal | 3 | 2 | 7 | 8 |
| Hard | 5 | 3 | 9 | 12 |

Easy applies a smaller exposure penalty and more variation among close choices. Normal coordinates short action sequences. Hard also compares the strongest sequences with holding against a sample of rival replies: up to two candidate moves per rival, selecting one response, in cyclic turn order. This is not an exhaustive simulation of every action in the next round. All profiles use the same economy, legal commands, visibility and starting resources. No rival receives a special preference for attacking the human player.

## Responsibilities and turn flow

- `src/game/ai_analysis.gd`: independent snapshots, route-based threats, position evaluation, wage affordability, policy variation and revealed encounter choices.
- `src/game/ai_candidates.gd`: useful purchases, spells and movements, with limited alternatives across kinds and units.
- `src/game/ai_planner.gd`: resumable beam search and Hard's bounded response sampling.
- `src/game/ai_queries.gd`: memoized read queries for an immutable search position, shared between evaluation and candidate generation; never reused across model mutations.
- `src/game/kingdom_ai.gd`: validated commits, preparation diffs, movement groups and synchronous simulation APIs.

Threats follow an enemy's connected friendly routes and accessible bridges rather than checking only adjacent troops. Currently spent enemies are treated as threats on their next activation. Evaluation weighs capital exposure, threatened income/units, sources, treasury, net income, unsupported units, attrition and actual surviving enemy capitals. Capitulation/annexation and replacement capitals are applied through the authoritative rules rather than approximated as faction elimination. Holding is the baseline; a move must improve on it.

Military spending uses the true wage delta, including Soldier-to-Knight upgrades. Easy/Normal require nonnegative projected income after an army addition. Hard can accept a deficit when post-purchase reserves cover three such ticks plus ten gold. Construction and development retain enough treasury for the existing army's next settlement. Recruitment requires a useful attack capability or defensive need, with a bounded campaign premium and an excess-strength discount; all useful ranks survive shortlisting. Houses retain deployment space and an income target. Bridges receive credit for reconnecting friendly kingdoms and opening new border access, with enclosed hole filling excluded. Live kingdom records are regenerated after every commit.

Mana opportunities compete across the faction. The three spells have tactical policies: hostile bridge Shatter, sustainable Summon and useful extra-action Trailblaze. Threatened ready units can spend their action to entrench during preparation. Revealed altar/duel choices compare expected benefit with unit value and avoid gambling a threatened capital defender.

The current preparation-before-movement order remains. Search can coordinate movements, including a merge followed by attack. Independent movements play together; paths relying on newly captured land, merging, wards, Knight duels, annexation and encounters finish visibly before another search. Encounters are resolved on the live board, then planning starts from the actual result.

## Fairness, determinism and cancellation

Search deep-copies cells, kingdom records, mana and effects. Hidden event IDs are removed from copies; no future encounter roll is simulated. Policy variation hashes seed, decision revision and coordinates without advancing gameplay RNG. Identical seed, difficulty, board and actions reproduce decisions.

Each search step evaluates one candidate or reply stage. Live play now runs those simulations in a WorkerThreadPool task on a private snapshot, keeping initialization and long individual steps off the render thread. Pause prevents commits, and departure/shutdown cancels outstanding searches before freeing the scene. Synchronous `ai_turn` remains available for rules simulations. Immutable query contexts account for all banks' wages in one unit pass; Hard reply evaluation and candidate generation share a context. Search depth, scoring, candidates and deterministic decisions are unchanged. `ai_last_decision` records the chosen action/reason, evaluated candidates, search duration and peak step time for diagnostics; none of this appears in the normal UI. See [capture and AI performance](capture-and-ai-performance-2026-10-13.md) for current measurements and limits.

## Verification and practical limits

All 18 regression suites passed across the full run, continuation after fixture repairs, and final affected-suite reruns. The targeted AI suite passes 178 checks, including remote threats, holding a defender, wage safety, merge-to-attack planning, supported Knight trade rejection, every spell, hidden-event fairness, snapshot isolation, reproducible turns across all sizes/rules/difficulties, preference loading, restart, rules changes, pause and cancellation. AI simulations controlling faction zero also resolve events on arrival; human commands retain the popup choice. The animation, merge and treasury fixtures now use explicit independent fronts, meaningful attacks and actual expenditure accounting, avoiding assumptions about the old AI's purchases.

`tools/ai_performance_probe.gd` measures a fixed Large scenario with 30 units. On this host, one synchronous search measured approximately 29 ms Easy / 167 ms Normal / 685 ms Hard, with maximum individual steps 4.9 / 10.4 / 16.8 ms and initialization about 7 ms. Hard evaluated 130 branches and yielded through 99 frames in the asynchronous probe. These are CPU/search observations for one fixture, not FPS guarantees or full faction-turn durations. Raw data: `artifacts/ai_performance.json`.

`tools/ai_playtest.gd -- --seeds=2 --rounds=16` ran 12 Modern Very Small comparisons with the final policies, rotating profile assignments across starting positions. Both sampled seeds had three factions, so some profiles controlled two kingdoms and others one; this is a smoke test, not a balanced head-to-head rating. Hard won six matches, Normal three and three reached the round limit. There were economic/stranded-unit deaths. Raw data: `artifacts/ai_playtest.json`. These results do not establish population win rates or guarantee the difficulty ordering on every map.

Difficulty is initially calibrated by search capability. Human playtesting and broader matched tournaments are still needed to establish how forgiving Easy or challenging Hard feels. Candidate pruning, heuristic economic weights and the limited reply sample can miss good strategies. There is no persistent campaign strategy, personality, diplomacy, adaptive difficulty or mid-match difficulty switch. Barrier-expiry timing and hypothetical enemy purchases are not fully modeled in the threat/reply forecast. Any later deeper forecasting must retain private snapshots, unknown encounters and responsive cancellation.

The later [code-review refactor](post-refactor-review-2026-10-12.md) reduced fixed five-sample median search time by about 20–25% while retaining identical actions, scores and branch counts. Its report contains the current benchmark methodology and watchpoints; the earlier single-run timings above are historical measurements.

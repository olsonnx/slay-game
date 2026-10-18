# Balance playtest — 11 October 2026

Two specialist agents tested economy and tactics. The main run compared legal strategy policies against the current opponents. Production rules, balance and user preferences were left unchanged.

## Scope and method

- Modern rules; current starting economy, mana cap and capital-based victory.
- 160 active-opponent matches: five policies, seeds 0–15, Very Small and Small, 25-round limit. All 3,188 recorded custom-policy movement commands passed public validation. Opponents took actual `ai_turn` actions; global tree spread occurred between rounds.
- 128 paired-opening matches on the same seed/map combinations. Only the opening changed; every faction subsequently used the stock AI. Player turn one correctly received no extra income tick. One match hit the 25-round limit; extending that exact case produced a player win on round 29.
- 200 controlled economy scenarios on Small seeds 0–19: 80 stationary investments, 100 neutral-expansion scenarios and 20 opening checks. Those scenarios deliberately omit enemy actions/tree spread, so they measure potential rather than practical win rates.
- Targeted combat/bridge fixtures and 100 generated Small maps for mana-source availability. A supported midgame fortress was tested for 100 complete rounds with active opponents and tree spread.

These are engine-driven rules simulations, not mouse-and-keyboard usability tests or exhaustive strategic search. Policies are simple heuristics. Seed-matched results are useful comparisons, not population win-rate estimates. Classic, Medium and Large full-game balance were not covered.

## Priority findings

### 1. Supported Knights have no direct combat counter

Maximum strength is 3, while attacks require strictly greater strength than defense. A Knight on a capital protects that capital and its six friendly neighbors at defense 3. No unit can attack those provinces, and current spells cannot damage enemy-owned structures or troops.

Reproduction: Small seed 42, a **pre-established midgame fixture**, seven owned provinces at value 2, Knight on the capital, two houses and four Scouts occupying the remaining provinces. Gross income 22, wages 20, initial gold 0. All provinces contain a unit or structure, preventing tree spread into them. After **100 complete rounds**, the capital remained intact, no player units died and gold reached 200.

This proves a sustainable defence lock, not an unbeatable opening. Establishing the mature economy was done directly rather than through a contested construction sequence. An early bare Knight bunker with income 12 and wages 12 failed under complete rounds on seeds 0, 1, 42 and 2026: capitals fell on rounds 15, 2, 7 and 6. Forest losses starved the army, or opponents arrived before deployment.

Recommendation: choose a deliberate maximum-tier counter, such as equal-strength attrition, siege or an offensive weakening spell. Raising upkeep alone delays but does not remove the eventual lock. This is the highest-priority design issue.

### 2. Fortified bridges ignore unit attacks

**Status: fixed on 11 October 2026 after this playtest.** Rules mutation and command recording now share a fortification check that includes hostile bridge garrisons. First hits preserve the defender and spend the attacker's action; normal crossing and friendly merging preserve the ward. Regression coverage includes second hits, insufficient strength, animation and cancellation. The observations below describe the pre-fix build.

An enemy Scout on a neutral bridge was fortified successfully for 3 mana. An opposing Soldier attacked it; the Scout died immediately, the Soldier occupied the bridge, and the ward remained active. Both movement mutation and action recording exclude bridges from blocked attacks. Shatter correctly consumes the bridge ward first.

This is a **confirmed implementation bug**, rather than a balance judgment. The first valid unit hit should consume the ward and the attacker's action while preserving the defender, matching the agreed Fortify behavior.

### 3. Investment returns make high development unattractive

Safe clear-province payback:

| Investment | Cost | Income gain | Payback |
| --- | ---: | ---: | ---: |
| Develop 1→2 | 2 G | 1 G/round | 2 rounds |
| House | 20 G | 4 G/round | 5 rounds |
| Develop 2→3 | 8 G | 1 G/round | 8 rounds |
| Develop 3→4 | 18 G | 1 G/round | 18 rounds |
| Develop 4→5 | 32 G | 1 G/round | 32 rounds |
| Develop 5→6 | 50 G | 1 G/round | 50 rounds |

Every tested start had four value-1 provinces. Spending 8 G develops all four, immediately raising income from 10 to 14. Houses then beat further development in pure return wherever safe building space is available. Value 3+ development looks like a niche long-game investment: the median active heuristic match lasted **6.5 rounds**.

This does not make development strictly useless. It works on occupied/capital/defensive provinces where houses cannot be placed, and value survives capture while houses are destroyed. Suggest smoothing the cost progression or defining high development explicitly as a late-game/space-constrained option.

### 4. Summon enables a very efficient opening, but not a universal winner

All 20 tested Small seeds allowed: Summon a Scout, merge it with the starting Scout into a ready Soldier, then develop the four value-1 provinces. Result before capture: **2 G, 14 income, 5 wages**. Upgrading the original Scout directly costs the entire 10 G.

However, the paid upgrade can also use the starting mana to summon a **second unit**, so it preserves an extra action/front. Two Scouts capture more neutral provinces per turn; merging sacrifices that expansion capacity for attack strength. The paired full-game tests demonstrate this trade-off:

| Opening, followed by stock AI | Very Small wins /16 | Small wins /16 |
| --- | ---: | ---: |
| Stock AI opening | 9 | 6 |
| Paid Soldier upgrade + Summon | 9 | 7* |
| Free merged Soldier + four developments | 5 | 7 |
| Two Scouts + four developments | 9 | 8 |

*The paid-Soldier Small seed 0 match won on round 29 after the initial 25-round cutoff. Other results resolved within 25 rounds. With just 16 seeds per size and a fixed continuation policy, small differences are not decisive.

Do not nerf Summon solely from the opening arithmetic. Its synergy is strong, but the free-Soldier opening was noticeably worse on Very Small in these tests. Retaining two ready units can matter more than early unit strength.

### 5. Fortify and Shatter are much less available than Summon

Both cost 3 mana, but starting capacity is 1. Waiting cannot increase storage beyond the source cap; the player needs at least three owned sources and must bank mana rather than spend every regeneration on Summon.

Small seeds 0–99 produced 3 neutral sources on 90 maps, 2 on four maps and only 1 on six maps. On those six maps, capturing **every neutral source still cannot unlock 3-mana spells** without capturing an enemy source. In the eight-turn neutral-expansion probe, 12/20 runs still had capacity below 3 despite prioritizing reachable sources.

If these spells should offer early tactical alternatives, lower selected costs or guarantee sufficient accessible sources. If they are conquest rewards, make that role explicit. This is an availability concern, not proof that the spells are universally weak.

## What did not hold up

- **Blind investment was not reliably dominant against active opponents.** The continuous development policy won only 3/16 Very Small and 1/16 Small matches; greedy expansion lost defenders and income. Its neutral-frontier wealth cannot be treated as a winning strategy.
- **Wages matter now.** The four custom policies suffered 351 bankruptcy/separation deaths across 128 matches; 97 of those matches recorded at least one death. Stock-AI death counts were not instrumented and are excluded. These deaths also reflect crude defensive heuristics, so they do not establish that wages are too high.
- **Paid recruitment is not proven useless.** Uncontested tests reward saving gold and using Summon, but active threats and simultaneous fronts change troop urgency.
- **An unresolved 25-round game was not necessarily a permanent stalemate.** The one paired-opening cutoff resolved on round 29.
- **Enemy-occupied bridges sharing funds is intentional current behavior.** Movement is blocked while economic connectivity persists until bridge destruction. This can surprise players, but it is documented and should not be mislabeled as a bug.

## Suggested next pass

1. Fortify's unit-attack behavior on bridges is now fixed; keep its regression coverage.
2. Decide how maximum-tier defenders can be challenged.
3. Make spell source requirements clearer and decide whether their late availability is intended.
4. Smooth development incentives after the first upgrade, then repeat the same seed-matched probes.

## Reproduction and raw evidence

- `tools/balance_playtest.gd -- --seeds=16` → `artifacts/balance_matches.json`.
- `tools/opening_playtest.gd` → `artifacts/opening_matches.json`.
- `artifacts/economy_probe.gd` → `artifacts/economy_probe_results.json`; detailed explanation in `artifacts/economy_balance_report.md`.
- `artifacts/tactics_probe.gd` → logged output in `artifacts/tactics_results.txt`.
- `artifacts/long_match_probe.gd` reproduces the round-29 extension.

Use Godot `--headless --path . --script <script> --quit-after 18000` for these probes. No production balance settings or user preference files are changed.

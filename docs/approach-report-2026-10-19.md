# Standard-map approach comparison - 19 October 2026

## Finding

The most primary-match wins went to **Aggressive** (14 of 36). Economic won 12, Defensive 4, and Aggressive 14; 6 games remained unfinished. The map-level uncertainty interval does not separate Economic from Aggressive, so their observed ranking should be treated as provisional.

Aggressive play's round-ten mean gross income was 95.0, versus 74.5 for Economic and 69.3 for Defensive. Rapid expansion is itself an economic investment in these rules. Defensive positions had more towers and a higher entrenched share at the checkpoint; compare that protection with wins and survival rather than assuming fortification implies victory.

## Scope

36 primary matches on the map labelled **Standard** in the game menu (`large`, approximately 250 tiles), with six independent factions: two Economic, two Defensive and two Aggressive. They are enemies, not teams. Modern rules, Normal shared tactical analysis, unchanged resources and prices, and an 80-round limit. The generated boards had 216-305 cells, including bridges added during play.

Seeds: [0, 1, 2, 3, 4, 5]. Six assignments per seed cover both cyclic orders of the three styles and all three offsets. Every style occupies every faction/turn-order seat twice on each map. This controls geography and first-player effects without claiming independent evidence from every seat. There are 72 faction outcomes per style, drawn from 36 actual matches, not 216 matches.

Events, spells, tree spread, bridges, support, bankruptcy and capital surrender remain enabled. Everyone receives opening income/upkeep before their first turn. No production gameplay code or balance values changed.

## What the policies mean

| Policy | Investment and army choices | Hostile expansion |
| --- | --- | --- |
| Economic | Prioritise efficient development and houses; ordinary recruitment targets wages within 60% of current local gross income | Wait until gross faction income is at least 1.50 times the average surviving rival, then commit to war |
| Defensive | Similar investment, but ordinary recruitment targets 50%; proactively build nonredundant frontier towers, assign blocking garrisons and prioritise threatened entrenchments | Same income threshold |
| Aggressive | Prioritise useful recruiting and expansion; ordinary recruitment targets 90%; invest when useful recruitment is unavailable or too expensive | Attack from the opening |

All can expand into neutral land, construct useful bridges, cast available spells, defend an endangered capital, and entrench ready units that otherwise hold an exposed frontier. Economic/Defensive policies may counterattack enemy units within two hexes of a capital before unlocking war. Unlocking war is permanent, avoiding repeated withdrawal when income fluctuates. Income is recurring gross income, not stored gold, and is measured across the faction's connected kingdoms; spending still uses each local bank.

Emergency recruitment may exceed the percentage target but cannot exceed current local income. All policies reject recruits or same-rank merges whose resulting wages exceed local income, and check next-settlement affordability for paid development/towers/houses/bridges. A useful merge may exceed the ordinary recruitment percentage while remaining sustainable. The same existing strategic movement planner supplies combat legality, enemy replies, capital protection, supply analysis and coordinated movement, with experiment-only objective preferences for the styles. Each receives up to eight preparation actions per turn. These are concrete AI implementations of the ideas, not exhaustive optimal versions of each philosophy.

## Results

30 matches finished and 6 remained unfinished at the limit. Mean observed length: 43.4 rounds, including unfinished matches at the limit.

| Style | Winning faction | Eliminated factions | Factions still alive in unfinished matches |
| --- | ---: | ---: | ---: |
| Economic | 12 | 55 | 5 |
| Defensive | 4 | 62 | 6 |
| Aggressive | 14 | 52 | 6 |

Each row sums to 72 faction outcomes. A match has one winner. Because there are two independent factions per style, a style's match wins equal its number of winning factions; do not interpret wins/72 as the style's share of matches. No-capital positions count as eliminated even if isolated land remains. Unfinished games are not assigned to the richest or largest faction.

### Economy and position after ten rounds

Population means include eliminated positions. If a game finishes before a checkpoint, its terminal board is carried forward without inventing later income collections. Entrenchment is entrenched units divided by all surviving units at that checkpoint, avoiding the misleading comparison of raw entrench counts between differently sized armies.

| Style | Gross income | Provinces | Houses | Towers | Units entrenched |
| --- | ---: | ---: | ---: | ---: | ---: |
| Economic | 74.5 | 29.0 | 2.1 | 2.1 | 47.7% |
| Defensive | 69.3 | 26.6 | 1.9 | 3.2 | 55.2% |
| Aggressive | 95.0 | 42.4 | 0.3 | 2.0 | 43.5% |

### War and financial risk

| Style | Bankrupt kingdom settlements per 100 active faction turns | Hostile attacks per active turn | Mean war-unlock round among unlocked factions |
| --- | ---: | ---: | ---: |
| Economic | 5.3 | 0.91 | 13.9 |
| Defensive | 5.1 | 0.44 | 15.9 |
| Aggressive | 6.3 | 1.25 | 1.0 |

Bankruptcy counts a local bank whose gold plus income minus upkeep is negative immediately before settlement. It is separate from unsupported-unit deaths, which are recorded in the raw telemetry. Troop affordability at recruitment does not guarantee future safety: enemy captures, splits, tree growth and events can remove the supporting income before the next settlement. `deficit_at_end` separately records an already-insolvent bank when a faction finishes its own actions. No policy receives debt forgiveness or extra resources.

### Map-to-map variation

| Seed | Economic wins | Defensive wins | Aggressive wins | Unfinished |
| --- | ---: | ---: | ---: | ---: |
| 0 | 3 | 0 | 3 | 0 |
| 1 | 3 | 2 | 1 | 0 |
| 2 | 2 | 1 | 3 | 0 |
| 3 | 1 | 1 | 4 | 0 |
| 4 | 1 | 0 | 0 | 5 |
| 5 | 2 | 0 | 3 | 1 |

There are only 6 distinct maps. Multiple assignments on one map are correlated. A small lead in aggregate wins is not enough to establish a universal best strategy, especially if the winning style changes by map.

Resampling whole maps with replacement 10,000 times (fixed RNG seed 20261019), the 95% percentile interval for Economic minus Aggressive match-win share is [-0.2778, 0.1667]. This exploratory interval preserves the six assignments belonging to a map as a cluster; it is not a guarantee about unseen maps or human play.

## Sensitivity to the economic lead requirement

Only the income threshold changes in these additional tournaments. The policies and rules are otherwise identical. These tests use seeds [0, 1] and assignments [0, 1, 2, 3, 4, 5]. The 1.50x row reuses the exact matching primary cases (same seeds and assignments), not extra simulations; compare threshold rows against that matched control rather than against a different map mix.

| Income needed vs average rival | Matches | Economic wins | Defensive wins | Aggressive wins | Unfinished |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1.25x | 12 | 3 | 2 | 7 | 0 |
| 1.50x | 12 | 6 | 2 | 4 | 0 |
| 1.75x | 12 | 3 | 2 | 6 | 1 |

## Verification and practical limits

The diagnostic planner has a neutral mode checked against the game's real strategic planner on an actual Standard six-faction board. Selected purchases use authoritative validation, merge affordability is checked, movement commits validate paths and expected units, and the harness checks that encounters do not introduce an unplayed faction. Every output includes failures and check counts; the summariser rejects failed or duplicate matches and verifies two factions of each style per match and complete win/elimination/unfinished accounting.

This is a free-for-all comparison against the other two styles with equal representation. It does not establish human multiplayer strength, diplomacy, alliance effects, two-player balance or the best strategy against every possible opponent. Existing tactical AI limitations affect all policies. Percentages and the definition of being rich are explicit experimental choices. Financial safety checks avoid knowingly unaffordable army purchases and merges; they do not prevent an enemy from bankrupting a kingdom by taking its land.

Raw results and progress logs are in `artifacts/approach-main-*`, with source hashes in `artifacts/approach-source-hashes.json`. Diagnostic code: `tools/approach_probe.gd`, `tools/approach_planner.gd`, `tools/summarize_approaches.py`.

## Reproduction

From the project root, set `$godotExe` to the Godot 4.6.3 console executable. Use writable diagnostic APPDATA as in the existing test runner.

```powershell
$env:APPDATA = Join-Path (Get-Location) 'artifacts/test-userdata'
& $godotExe --headless --path . --script tools/approach_probe.gd -- --seeds=6 --rounds=80 --output=res://artifacts/approach-main.json
python tools/summarize_approaches.py artifacts/approach-main.json --output artifacts/approach-summary.json --report docs/approach-report-2026-10-19.md
```

For threshold sensitivity, rerun the same probe with `--threshold=1.25` or `--threshold=1.75`, a distinct output path and the desired seed/rotation subset. The reported sensitivity files record their exact options. Pass them to the summariser with `--sensitivity`.

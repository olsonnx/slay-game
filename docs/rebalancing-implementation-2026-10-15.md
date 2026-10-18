# Knight rebalance implementation and gameplay comparison

15 October 2026. The comparison below records the initial implementation with 16 G Knight wages. Subsequent user-requested adjustments set current Modern wages to **3 / 9 / 27 G** for Scouts/Soldiers/Knights; the Knight purchase price remains 40 G and adjacent protection remains 2. The recorded comparison results below have not been rerun at the current wages.

## Implemented rules

| Rule | Before | Now |
|---|---|---|
| Knight recruitment | 30 G | **40 G** |
| Scout / Soldier recruitment | 10 / 20 G | 10 / 20 G |
| Scout → Knight upgrade | 20 G | **30 G** |
| Soldier → Knight upgrade | 10 G | **20 G** |
| Modern Scout / Soldier / Knight wages | 2 / 5 / 12 | **2 / 6 / 16** |
| Knight defence on its own hex | 3 | 3 |
| Knight protection of adjacent friendly hexes | 3 | **2** |

Knight prices and the protection cap apply in both rulesets. Classic retains its 1 / 2 / 4 wages. Other purchase prices, income, spells and movement rules are unchanged. Two Soldiers still merge into a Knight; their combined recruitment price is now the same 40 G as a direct purchase.

Recruitment and upgrades use a shared price table, and shop labels and tooltips read it. Both AI planners obtain purchase costs from the authoritative rules. The strategic planner's estimates of protection after moving a Knight also respect the adjacent cap. The tutorial teaches the new prices and protection; its small bankruptcy-practice kingdom now receives 40 G so the required purchase remains possible.

## Gameplay experiment

**48 new AI matches** compared three versions on the same 16 maps: seeds 0–7, Very Small and Small, four factions, Normal difficulty, 30-round limit. The original version used the saved pre-change source snapshot. The 30 G comparison uses the implemented protection/wage changes with only the Knight price restored to 30 G. The final version uses the actual 40 G price.

Every faction used the existing beam AI. Faction zero skipped its first settlement to match the solo opening. Encounters, spells, tree growth, kingdom splitting, bankruptcy and capital surrender remained enabled. A victory required only one faction to retain a kingdom/capital. Results are self-play outcomes, not human win rates.

| Metric | Original rules | Rebalance, Knight 30 G | **Implemented, Knight 40 G** |
|---|---:|---:|---:|
| Completed within 30 rounds | 12/16 | 16/16 | **16/16** |
| Mean observed rounds | 16.06 | 14.00 | **13.81** |
| Mean Knights on the board | 5.05 | 1.32 | **1.13** |
| Mean Soldiers on the board | 2.70 | 3.46 | **3.52** |
| Mean Scouts on the board | 7.71 | 6.11 | **6.03** |
| Deaths at settlement per match | 4.50 | 4.00 | **5.19** |
| Kingdom observations with negative net income | 3.54% | 1.08% | **2.88%** |
| Knight duels, total | 30 | 26 | **16** |

Unfinished games contribute 30 to observed-round averages. Army counts are round-end samples divided by total observed rounds, rather than units recruited. Deficit observations are sampled by kingdom at round-end. Settlement deaths are measured from the real `begin_turn` return value; they include both insolvency and unsupported troops. This is more precise than the earlier report's preparation-death counter, but still does not isolate bankruptcy alone.

The 40 G price produced **14.4% fewer Knights** than the same rebalance at 30 G, with almost the same Soldier and Scout populations. Knight duels became less common. All 16 games ended, including the four maps on which the original rules reached the limit with lengthy ownership stagnation.

There is **no consistent match-length penalty from the extra 10 G** in this sample: seven paired maps took longer, six took fewer rounds, and three were unchanged. The difference in averages is too small to infer a reliable speed improvement. Higher recruitment cost increased deficit observations and settlement deaths, which suggests tighter reserves under this AI rather than proving an ideal bankruptcy rate.

An initially surprising result: the first surviving Knight appeared after a faction's turn at mean round **6.19** with the 40 G price, versus **7.19** at 30 G. These matches allow merging, spell-funded units, encounter promotions and different investment decisions, so that statistic is not a direct-purchase timer. The isolated purchase test below confirms that raising the price really delays the same purchase policy. Do not interpret the self-play average as cheaper access to Knights; tracing the precise AI decisions behind it was outside this experiment.

## Controlled economy tests

Each version also ran 20 Small-map seeds for 20 player turns under four stationary policies: saving; rushing a Knight without investment; developing/building before recruitment; and buying a Knight once income can support it while otherwise investing. No opponents, movement, spells or tree spread occurred. These **240 simulations** measure financial consequences without claiming optimal play.

| Policy result | Original | Rebalance at 30 G | **Implementation at 40 G** |
|---|---:|---:|---:|
| Earliest Knight under no-investment rush | Turn 3 | Turn 3 | **Turn 4** |
| Rush simulations that later lost their army to settlement | 20/20 | 20/20 | **20/20** |
| First Knight under sustainable-investment policy | Turn 3 | Turn 4 | **Turn 7** |
| That policy's turn-20 gross income | 34 | 30 | **34** |
| That policy's turn-20 net income | +22 | +14 | **+18** |
| That policy's settlement deaths | 0 | 0 | **0** |

The 40 G sustainable-investment policy spends more time growing before buying its Knight and ends with a stronger economy. This is a consequence of that policy's order of purchases, not a general advantage of expensive units. The investment-first policy reaches its Knight on turn 8 in all versions; raising its price simply leaves 10 G less cash than the 30 G version. Knights remain viable when backed by investment.

The focused laboratory also repeated the breach/duel/capital-capture fixture and 108 settlement-threshold cases across the three versions. **147 focused assertions passed.** The new protection rule still blocks Soldiers and Scouts at the approach while allowing a Knight to breach it. Wages alone still cannot remove a sufficiently wealthy protected Knight under the original protection rule.

## Interpretation

The result matches the intended direction: Knights are a smaller share of the army, Soldiers remain useful, a protected Knight can be reached through its surrounding territory, and the higher purchase price consumes reserves without preventing games from finishing in this sample. The main recurring pressure comes from wages; the additional 10 G chiefly affects the timing and cash buffer of acquiring a Knight.

Keep the implemented values for the next human playtest. Watch whether losing a 40 G Knight feels appropriately consequential, whether players understand the breach followed by a duel, and whether they retain enough spare cash after upgrading. These tests cover two small map sizes and Normal AI. They do not establish multiplayer balance or large-map gameplay quality; the strategic planner receives a regression check for its updated defence estimates.

## Reproduction

```powershell
./tools/run_rebalance_implementation.ps1 -Godot 'PATH_TO_GODOT_CONSOLE'
./tools/summarize_rebalance_implementation.ps1
./tools/run_tests.ps1 -Godot 'PATH_TO_GODOT_CONSOLE'
```

The comparison runner creates isolated projects under `artifacts/rebalance-implementation-2026-10-15`. Each has its source, profile, log files and `results.json`; `summary.json` contains the aggregate and matched-map differences. The original source snapshot remains under `artifacts/rebalance-lab-2026-10-15/baseline/src/game`. A laboratory-only counter records actual settlement deaths; it does not alter rules or enter production code.

Production regressions additionally cover purchase rejection at insufficient funds, direct and upgraded Knight prices in both modes, the AI's cached breach targets, strategic protection estimates, and the full breach → duel → capital capture sequence. Existing shop, wage, bridge-support and tutorial expectations were updated to the new intended behaviour.

**Final validation: all 37 regression suites passed**, including 34 dedicated rebalance checks, the strategic AI, shop prices, bridge wages, multiplayer and completion of all tutorial objectives. The suites were resumed after updating obsolete price/protection expectations. The editor save test also passed after isolating test settings and save data under `artifacts/test-userdata`; the test runner now uses that location and restores its caller's environment afterward. `regression-audit.json` lists each suite's passing log and check count. The experiment's 48 matches and 147 focused assertions also completed without errors.

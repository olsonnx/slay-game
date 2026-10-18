# Knight protection and economy balance report

15 October 2026. This records the research before implementation. The subsequent [implementation and gameplay comparison](rebalancing-implementation-2026-10-15.md) applies the recommendation with the requested 40 G Knight price.

## Recommendation

Use **strength 2 as the maximum defence a unit lends to neighbouring friendly hexes**, while keeping a Knight's own defence at 3 and retaining Knight-versus-Knight mutual destruction. For Modern economy, keep recruitment at **10 / 20 / 30 G** and raise Scout / Soldier / Knight wages from **2 / 5 / 12 to 2 / 6 / 16 G per turn**.

This is the strongest default candidate from this screening: it breaks the protected-Knight lock, keeps territorial defence useful, makes Knights a continuing commitment, and finished **16/16** tested AI matches within 30 rounds. The more severe **2 / 6 / 18** model is a credible alternative for a slower, more restrictive economy, but finished **14/16** and exposed an early growth trap in a simple investment policy. These are candidate recommendations, not proof of an optimal balance or human preference.

## What is happening now

Movement permits unlimited travel through connected friendly territory followed by one capture at its border. Defence is the strongest defender on the destination or an adjacent same-owner hex. Equal-strength combat is prohibited except when a Knight attacks a hex actually occupied by another Knight; that trade kills both without changing ownership.

Consequently, a Knight inside six friendly hexes gives every possible approach strength 3. An enemy Knight cannot enter an approach hex, and cannot skip it to reach the defender. No amount of attacking Knights fixes that geometry under the current rules.

There is an economic distinction too: **the treasury cannot remain negative**. Settlement adds income minus wages; if the result is negative, the treasury becomes zero and all supported units in that kingdom die. Negative net income is the condition worth making strategically relevant, rather than aiming for a negative displayed balance.

Modern wages are already 2 / 5 / 12; Classic wages are 1 / 2 / 4. A seven-hex Modern opening has 10 gross income, four value-1 hexes and three value-2 hexes. Developing those four cheap hexes costs 8 G and raises income to 14. Houses cost 20 G and add 4 income without upkeep. These income tools explain why the current Knight wage soon becomes comfortable.

## Combat experiments

The deterministic fixture places a defending Knight on its capital, six friendly value-2 approach hexes, and an enemy kingdom around them. Two attacking Knights start in that outer kingdom.

| Test | Current protection | Adjacent protection capped at 2 |
|---|---|---|
| Legal enemy targets among the six approach hexes | 0 | 6 |
| Attack the centre directly before a breach | Prohibited | Prohibited |
| First Knight captures an approach hex | Impossible | Succeeds |
| Second ready Knight trades with the central defender | Inaccessible | Succeeds; both die |
| A third ready Soldier captures the exposed capital | Inaccessible | Succeeds through the breach |
| Soldier or Scout attacks the protected approach | Blocked | Blocked |
| Knight defence on its own hex | 3 | 3 |

Further checks confirm that towers retain adjacent defence 2, multiple supporters do not add their strength, an occupied border Knight still requires a duel, and a fortified structure still absorbs a valid attack and spends the attacker. The duel itself preserves ownership and the capital until the subsequent capture.

The attacker needs multiple ready units to execute the whole sequence in one turn. Otherwise, the defender has a turn to react. Territory still controls access, mobility, economic connections and protection against lower ranks. A Knight still protects up to six adjacent hexes from Scouts and Soldiers; it no longer makes those hexes completely impassable to the strongest attacker.

**Wages alone fail this test.** With the seven defending hexes developed to value 6, gross income is 42 without any houses. The central Knight survived 100 settlements at every tested wage, including 24. Once a pocket can pay its defender indefinitely, waiting cannot resolve the lock.

Other possible solutions, assessed conceptually rather than implemented in the simulations:

| Alternative | Assessment |
|---|---|
| Raise wages only | Adds economic pressure but leaves a sufficiently rich protected pocket invulnerable. |
| Raise recruitment prices only | Delays armies; does nothing to an existing protected Knight. |
| Add a fourth rank | Expands recruitment, art, AI and tutorial scope; a highest-rank protection lock can still recur. |
| Remove all adjacent unit protection | Solves the lock but substantially weakens positioning and territorial defence. |
| Allow attacking the supporting Knight through protected land | Can work, but introduces remote-target/path/animation rules and ambiguity with several supporters. |
| Siege or suppression counters | Can preserve full protection, but adds state, timing rules and UI. Worth considering only if siege gameplay is itself desired. |

## Economy experiments

Six isolated copies of the game rules were tested. Each copy also supplies its modified catalogue to the AI and its search snapshots, so affordability and forecasts inside simulations use the same wages as settlement. The protection cap is the only combat change.

### Active matches

The first screen used **48 matches**: six variants × seeds 0–3 × Very Small and Small, four factions, Normal AI, 30-round limit. Every faction used the existing beam planner. Rules for spells, encounters, tree growth, bankruptcy and capital surrender remained active. Faction zero skipped its first settlement, matching the solo opening; other factions settled at their first turn. A match ended when only one faction retained a kingdom/capital.

| Variant | Recruitment | Wages | Finished by round 30 | Mean observed rounds* | Mean Knights on board** | Turn-preparation deaths/game*** |
|---|---|---|---:|---:|---:|---:|
| Current rules | 10/20/30 | 2/5/12 | 6/8 | 15.38 | 4.82 | 4.00 |
| Protection cap only | 10/20/30 | 2/5/12 | 8/8 | 10.38 | 2.57 | 2.38 |
| Cap + moderate wages | 10/20/30 | **2/6/16** | **8/8** | 14.88 | 1.49 | 3.50 |
| Cap + steeper wages | 10/20/30 | 2/6/18 | 6/8 | 20.75 | 1.23 | 4.75 |
| Cap + severe wages | 10/20/30 | 2/8/24 | 6/8 | 24.13 | 0.66 | 8.25 |
| Cap + dearer recruitment | 15/30/45 | 2/5/12 | 8/8 | 14.63 | 2.08 | 3.13 |

\* Unfinished matches contribute 30. This is a capped observation average, not an estimate of their eventual completion time.

\** Knights counted at each round-end, divided by total observed rounds. It measures top-rank saturation across the board, not production or unit efficiency.

\*** Death records during AI preparation, including settlement and potentially destructive preparation actions. This counter is named `starvation_deaths` in the raw match output, but it does **not** isolate bankruptcy deaths and should not be interpreted as doing so.

The two baseline timeouts ended with **23 and 7 consecutive rounds of unchanged ownership**. The two 18-wage timeouts both changed ownership in their final round and had 178 and 181 recorded captures; these were ongoing wars, not evidence of the original unbreakable pocket.

A further **16 matches** compared wages 16 versus 18 on seeds 4–7 across both sizes. Combined results on the same 16 map/seed pairs:

| Wages with protection cap | Finished | Mean observed rounds | Mean Knights on board | Preparation deaths/game |
|---|---:|---:|---:|---:|
| **2/6/16** | **16/16** | **14.00** | 1.32 | 3.94 |
| 2/6/18 | 14/16 | 19.63 | 1.15 | 5.56 |

Wage 18 reduced Knight saturation a little further, but with longer conflicts and more preparation deaths. Wage 24 was substantially more restrictive. Raising recruitment prices slowed access without increasing the penalty for maintaining an already-built defensive army.

### Controlled economic policies

The final focused suite ran **480 stationary economic simulations**: six variants × 20 Small-map seeds × four policies, for 20 player turns. No movement, opponents, spells or tree spread occurred. These isolate finance and investment choices; they are not competitive opening recommendations.

The four policies were saving; upgrading the starting Scout to a Knight as soon as affordable; buying cheap development and houses before the Knight; and a growth policy that buys cheap development, upgrades once current income covers a Knight, then buys houses whenever affordable. The starting Scout remains the intended upgrade target; dead units are not replaced.

Results for the last policy, identical across the 20 seeds:

| Model | First Knight, player turn | Turn-20 gross income | Knight wage | Turn-20 net income |
|---|---:|---:|---:|---:|
| Current prices, wage 12 | 3 | 34 | 12 | +22 |
| Current prices, wage 16 | 4 | 30 | 16 | +14 |
| Current prices, wage 18 | 4 | 18 | 18 | 0 |
| Current prices, wage 24 | 6 | 34 | 24 | +10 |
| Recruitment 15/30/45, wage 12 | 7 | 34 | 12 | +22 |

At wage 18 this policy buys the Knight exactly when income reaches 18, leaving 2 G and no surplus to finance another house. This is a **policy trap**, not an unavoidable outcome: delaying the Knight allows further investment. It shows why raising wages should be accompanied by growth-aware AI rather than a simple `net >= 0` affordability test.

The reckless no-investment Knight rush went bankrupt in **20/20 seeds for every model, including current rules**. Current Knights are already punishable if bought before support exists. Conversely, the investment-first policy eventually supported a Knight without deaths in all models, reaching gross income 34. Treasury totals after a reckless policy are misleading: early unit death eliminates future wages and can leave more cash than prudent play.

### Does army size strain an established small kingdom?

A separate legal fixture has seven value-2 hexes, two Knights and five houses: **34 gross income**. After construction, its reserve is set to 30 G.

| Knight wage | Combined Knight wages | Net income | Bankruptcy settlement with 30 G reserve |
|---|---:|---:|---:|
| 12 | 24 | +10 | None within 100 turns |
| 16 | 32 | +2 | None within 100 turns |
| 18 | 36 | −2 | 16th |
| 24 | 48 | −14 | 3rd |

Wage 16 reduces the comfortable +10 surplus to +2. Losing one value-2 hex removes that surplus; losing more land or a house puts the army into deficit. This makes territory loss economically relevant while leaving room for two Knights in a heavily invested pocket. Wage 18 makes that same army unsustainable even before losses.

An additional **216 settlement fixtures** covered gross income 7/10/14/20/30/42, one Soldier or Knight, and reserves 0/10/30 across all six variants. Observed death timing matched `floor(reserve / deficit) + 1` whenever wages exceeded income; reaching exactly zero did not cause bankruptcy. For example, income 14 and reserve 30 support a wage-16 Knight for 15 settlements before death on the 16th; a wage-18 Knight dies on the 8th, and a wage-24 Knight on the 4th.

## Why this differs from original Slay

The [official Slay rules](https://www.windowsgames.co.uk/slayRules.html) specify wages **2 / 6 / 18 / 54**, a 10-credit basic recruit and one income per clear hex. They also describe strict superiority, adjacent protection and bankruptcy after territory is cut apart. The developer explicitly presents rising maintenance and cutting territories as central to the design on the [Slay game page](https://www.windowsgames.co.uk/slay.html).

Our three-rank game has province development, houses and mana-funded recruits. Copying an upkeep sequence does not copy the surrounding economic constraints. Cheap recruitment plus steep recurring wages is the useful design principle; 2/6/16 fitted this tested game better than copying 2/6/18 exactly.

## Implementation scope and remaining uncertainty

If adopted, apply the adjacent-protection cap in the shared defence calculation so both rulesets lose the lock, and change **Modern wages only** to 2/6/16. Retain Classic's economy unless a separate Classic rebalance is desired. Keep recruitment, house, tower, development and spell prices for the first iteration so the effect remains attributable.

The catalogue is shared by settlement, tooltips and AI costs. The combat change also needs a review of AI threat/protection assumptions, movement previews, tutorials and rule descriptions. All direct and cached destination queries should agree. The test laboratory exercised current AI self-play with the new shared defence rule; it did not retune the AI's strategic value of a defensive Knight.

For a subsequent AI iteration, consider requiring a positive growth margin for discretionary high-tier purchases, with emergency exceptions for threatened capitals. That proposal was not separately tested here. The current Normal AI accepts zero-net purchases; Hard can fund a short deficit. Do not deliberately make the AI buy suicidal armies just to increase bankruptcy statistics.

The 64 matches cover two small map sizes, Normal difficulty and one existing AI policy family. They do not establish human enjoyment, multiplayer balance, Hard/Easy behaviour, or Huge-map strategic-AI performance. The tested protection cap proves the specific pocket is breachable, not that every possible position necessarily ends. Human play should assess whether the breach/duel/capture sequence is clear and whether Knight wars feel costly enough.

## Reproduction and evidence

Use Godot 4.6.3. The runner creates isolated minimal projects under `artifacts/rebalance-lab-2026-10-15`, modifies only those copies, and runs their authoritative rules and AI. It does not launch the application or read/write saved gameplay preferences.

```powershell
./tools/run_rebalance_lab.ps1 -Godot 'PATH_TO_GODOT_CONSOLE'
./tools/run_rebalance_lab.ps1 -Godot 'PATH_TO_GODOT_CONSOLE' -Supplement
./tools/run_rebalance_lab.ps1 -Godot 'PATH_TO_GODOT_CONSOLE' -Extended
./tools/summarize_rebalance_lab.ps1
```

`tools/rebalance_lab.gd` contains the fixtures, policies and match loop. `results.json` in each variant contains the first eight matches; `supplement.json` contains the expanded focused probes; `extended.json` adds eight matches each for wages 16 and 18. `summary.json` combines them. Standard-output/error logs are retained beside the raw results. The original match run predates the expanded focused fixtures, so its assertion count is smaller; use the supplemental results for the final focused suite.

**Final focused validation: 297 assertions passed, zero failed; 64 active matches recorded.** Source hashes of all 25 game scripts match the baseline snapshot, confirming that production gameplay code was unchanged. The comparison is saved as `source-comparison.json`.

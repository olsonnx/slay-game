"""Summarise hoarding_probe.gd output without counting baseline matches four times."""
import argparse
import collections
import json
import statistics
from pathlib import Path


def mean(values):
    return round(statistics.mean(values), 2) if values else None


def write_report(path, summary):
    labels = {"baseline":"Ordinary Normal AI", "reserve40":"Keep 40 G from the opening",
              "reserve100":"Keep 100 G from the opening", "save5":"No paid purchases for 5 rounds",
              "save10":"No paid purchases for 10 rounds", "late100":"Play normally for 5 rounds, then keep 100 G"}
    groups = summary["policies"]
    expected = summary["maps"] * 4
    assert all(x["runs"] == expected for x in groups.values()), "Report requires all matched starting seats"
    table = "\n".join(f"| {labels[k]} | {groups[k]['wins']} | {groups[k]['eliminated']} | {groups[k]['alive_unresolved']} |"
                      for k in labels)
    economic = summary["economy"]
    econ_table = "\n".join(
        f"| {label} | {economic[k]['checkpoints']['11']['gold']:.2f} | {economic[k]['checkpoints']['11']['income']:.2f} | {economic[k]['checkpoints']['11']['income'] - economic[k]['checkpoints']['11']['upkeep']:.2f} |"
        for k, label in [("save","Save everything"),("invest","Invest available cash"),("reserve20","Invest above a 20 G reserve"),("reserve40","Invest above a 40 G reserve"),("save5","Save five collections, then invest"),("save10","Save ten collections, then invest")])
    reserve = groups["reserve100"]
    control = groups["baseline"]
    text = f"""# Hoarding strategy experiment — 19 October 2026

## Finding

These tests do not show hoarding to be a dominant strategy. Forcing savings from the opening usually sacrifices expansion and income, while cash still has real value for immediate recruitment and temporary military commitments. A bank cap would remove some of that tactical flexibility; these results do not establish a balance need for it.

This is a comparison of specified AI policies and controlled scenarios, not a solution for optimal human play. In particular, an intentionally timed cash-funded attack is different from maintaining a minimum bank balance indefinitely.

## Active matches

{summary['matches']} actual matches: {summary['maps']} ordinary-AI control matches plus five saving variants, each substituted into all four starting seats on the same maps. Maps use seeds 0–3 at generation sizes `small` and `medium` (currently labelled **Tiny** and **Small** in the menu), four initial factions, Modern rules, Normal AI and a 30-round limit. All factions receive their opening settlement. Events, spells, trees, capital surrender, treasury destruction, kingdom splitting and bridges remain active. The normal automatic AI backend is retained.

The ordinary controls supply {expected} starting-seat outcomes from {summary['maps']} actual matches; each variant supplies {expected} outcomes from {expected} actual matches. The control outcomes are reused for paired comparisons, not counted as extra simulations. All variants keep the existing tactical movement AI and free/mana actions. Normal play already saves when it has no attractive purchase; it is not an instruction to spend every coin.

| Policy | Won by round 30 | No capital at end | Still alive, unfinished |
| --- | ---: | ---: | ---: |
{table}

Each row has {expected} starting-seat outcomes. Unfinished games are not automatically losses. “No capital at end” is the game's elimination criterion even if an isolated province or unit remains. The four seats on one map are correlated, and eight maps are a small sample; differences of a few wins should not be treated as statistically established advantages.

**Reserve policies:** preserve the stated minimum after paid purchases. They can recruit or build a tower below that minimum when their supporting kingdom's capital is endangered. Settlement, events and enemy action can still reduce the bank below the target. The delayed-saving policy has exactly the same first five rounds as its matched ordinary control; this is asserted by the summariser.

**Five/ten-round saving policies:** prohibit paid purchases for those opening rounds, then resume ordinary purchasing. They still move their armies and use mana. These are deliberately strong tests of postponing spending, not passive players that skip all actions.

By the end of round five, the 100 G opening-reserve policy averages **{reserve['round5']['land']:.2f} provinces** and **{reserve['round5']['income']:.2f} gross income**, against **{reserve['round5']['land_baseline']:.2f} provinces** and **{reserve['round5']['income_baseline']:.2f} income** for the same seats under ordinary play. Its mean gold destroyed through captured capitals is **{reserve['mean_capital_gold_destroyed']:.2f} G**, compared with **{control['mean_capital_gold_destroyed']:.2f} G** across ordinary control seats. This measures capital capture losses, not event payments or every possible loss of gold.

## Safe economic opportunity cost

120 separate runs: 20 generated Tiny-map seeds × six investment policies. Starting land and the initial Scout remain unchanged. There are no enemy actions, movement, spells or tree growth. These assumptions intentionally isolate investment returns. Every run uses the actual current income, prices, development, building and settlement methods.

Investments select the cheapest cost per additional income point among legal development and houses, respecting the chosen reserve. These policies differ from the tactical AI policies above. Purchases happen after each collection, including the reported checkpoint, so invested cash is excluded from the displayed treasury. No resale value is assumed.

After **11 income collections**, mean values are:

| Policy | Bank (G) | Gross income | Income after Scout upkeep |
| --- | ---: | ---: | ---: |
{econ_table}

The pure saver can immediately upgrade its Scout to a Knight for 30 G. Its bank then falls from 87 to 57 G, with income 11 and wages 36: two upkeep payments leave it alive, and the third kills the army. This happened in all 20 runs.

The full investor cannot afford that upgrade immediately after its checkpoint purchases. If it stops investing and collects once more, it can buy the Knight in all 20 runs, and it survives all 30 subsequent tested settlements. This demonstrates a real one-turn liquidity disadvantage alongside a much stronger ability to sustain the unit. It does not model an enemy attacking during that waiting turn.

## Tactical value of a ready treasury

The separate `hoarding-tactics.json` fixture uses a defended seven-province pocket with a Knight on its capital, surrounded by attacking land. Recruitment and moves use ordinary authoritative rules. Five starting banks (20/40/60/80/100 G) are tested.

At **100 G**, the attacker recruits two Knights and a Soldier. The first Knight breaches an approach, the second trades with the defending Knight, and the Soldier captures the capital in the same turn. With **80 G**, both Knights can be bought and the defender killed, but the final Soldier is unaffordable, so the capital remains uncaptured that turn. Smaller tested banks also fail to complete the sequence.

This is a deliberately arranged tactical example, not a frequency estimate or evidence that saving 100 G from the opening pays off. It shows why cash cannot be valued only by passive income or sustainable army size: the initial attacking force would have huge wages, one attacking Knight dies in the trade, and the capture wins this two-sided fixture before wages fall due. If play continues against another opponent, the remaining Knight and Soldier both starve at their next settlement; the fixture verifies that cost too. Normal AI's purchasing policy rejects predictable deficits and does not exhaustively exploit attacks of this kind.

## Design interpretation and limits

- Avoid introducing bank capacity specifically to nerf a supposedly dominant hoarding strategy: that dominance was not demonstrated here.
- A ready reserve can fund an immediate response or a coordinated attack; it should not be treated as wasted money merely because it is unspent.
- Prolonged saving has opportunity costs without any explicit storage penalty: delayed income, fewer expanding troops, and stored gold destroyed on capital capture.
- These experiments do not establish an ideal reserve, an ideal bank cap, human multiplayer balance, or behaviour on Standard/Large/Huge maps. The later-saving variant starts after five rounds, not in a fully developed large-map endgame. A 30-round result includes unfinished games.
- A purposeful burst-spending strategy may outperform the tested reserve-floor policies. The tactical fixture verifies one such opportunity, while the match results use the existing AI's purchasing preferences and candidate limits.

No production rules or balance values were changed. Probe changes are confined to diagnostics. The unchanged-policy harness is checked against actual `ai_turn` execution on both map sizes, including board cells, kingdoms, mana, effects, AI revision and RNG state. Match runs also check purchase legality and movement termination; the delayed-policy comparison checks opening parity. Raw logs and JSON are in `artifacts/hoarding-*`; source hashes are in `artifacts/hoarding-source-hashes.json`.

## Reproduction

Run from the project root in PowerShell. Set `$godotExe` to your Godot 4.6.3 console executable, and point APPDATA at writable test storage as the existing test runner does:

```powershell
$env:APPDATA = Join-Path (Get-Location) 'artifacts/test-userdata'
& $godotExe --headless --path . --script tools/hoarding_probe.gd -- --mode=matches --seeds=4 --sizes=small --output=res://artifacts/hoarding-tiny.json
& $godotExe --headless --path . --script tools/hoarding_probe.gd -- --mode=matches --seeds=4 --sizes=medium --output=res://artifacts/hoarding-small.json
& $godotExe --headless --path . --script tools/hoarding_probe.gd -- --mode=matches --seeds=4 --sizes=small,medium --policies=late100 --output=res://artifacts/hoarding-late.json
& $godotExe --headless --path . --script tools/hoarding_probe.gd -- --mode=economy --output=res://artifacts/hoarding-economy.json
& $godotExe --headless --path . --script tools/hoarding_probe.gd -- --mode=tactics --output=res://artifacts/hoarding-tactics.json
python tools/summarize_hoarding.py artifacts/hoarding-tiny.json artifacts/hoarding-small.json artifacts/hoarding-late.json --economy artifacts/hoarding-economy.json --output artifacts/hoarding-summary.json --report docs/hoarding-report-2026-10-19.md
```
"""
    path.write_text(text, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--economy", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--output", type=Path, default=Path("artifacts/hoarding-summary.json"))
    args = parser.parse_args()
    datasets = [json.loads(path.read_text(encoding="utf-8")) for path in args.inputs]
    matches = [row for data in datasets for row in data["matches"]]
    baseline = {(m["size"], m["seed"]): m for m in matches if m["policy"] == "baseline"}
    assert len(baseline) == sum(m["policy"] == "baseline" for m in matches), "Duplicate baselines"
    groups = collections.defaultdict(list)
    for row in matches:
        if row["policy"] != "baseline":
            groups[row["policy"]].append(row)
    groups["baseline"] = [dict(row, seat=seat) for row in baseline.values() for seat in range(4)]
    summary = {"matches": len(matches), "maps": len(baseline), "policies": {}, "economy": {},
               "checks": sum(d["checks"] for d in datasets)}
    for policy, rows in groups.items():
        assert len({(r["size"], r["seed"], r["seat"]) for r in rows}) == len(rows)
        paired = [(r, baseline[r["size"], r["seed"]]) for r in rows]
        if policy == "late100":
            for row, control in paired:
                assert row["history"][:5] == control["history"][:5], "Late saving must share the control's first five rounds"
        entry = {"runs": len(rows), "wins": sum(r["winner"] == r["seat"] for r in rows),
                 "unresolved": sum(r["winner"] < 0 for r in rows),
                 "baseline_wins_in_same_seats": sum(b["winner"] == r["seat"] for r, b in paired),
                 "gained_wins": sum(r["winner"] == r["seat"] and b["winner"] != r["seat"] for r, b in paired),
                 "lost_wins": sum(r["winner"] != r["seat"] and b["winner"] == r["seat"] for r, b in paired),
                 "has_capital_at_end": sum(r["history"][-1][r["seat"]]["capitals"] > 0 for r in rows),
                 "eliminated": sum(r["history"][-1][r["seat"]]["capitals"] == 0 for r in rows),
                 "alive_unresolved": sum(r["winner"] < 0 and r["history"][-1][r["seat"]]["capitals"] > 0 for r in rows),
                 "mean_rounds": mean([r["rounds"] for r in rows]),
                 "mean_capital_gold_destroyed": mean([r["destroyed_treasury"][r["seat"]] for r in rows]),
                 "mean_settlement_deaths": mean([r["settlement_deaths"][r["seat"]] for r in rows]),
                 "round5": {}}
        for field in ("gold", "land", "income", "upkeep", "units", "houses"):
            entry["round5"][field] = mean([r["history"][min(4, len(r["history"])-1)][r["seat"]][field] for r in rows])
            entry["round5"][field + "_baseline"] = mean([b["history"][min(4, len(b["history"])-1)][r["seat"]][field] for r, b in paired])
        entry["by_size"] = {}
        for size in sorted({r["size"] for r in rows}):
            sub = [r for r in rows if r["size"] == size]
            entry["by_size"][size] = {"runs":len(sub), "wins":sum(r["winner"] == r["seat"] for r in sub),
                                      "unresolved":sum(r["winner"] < 0 for r in sub)}
        entry["by_seed"] = {str(seed):sum(r["winner"] == r["seat"] for r in rows if r["seed"] == seed)
                            for seed in sorted({r["seed"] for r in rows})}
        summary["policies"][policy] = entry
    economy = (json.loads(args.economy.read_text(encoding="utf-8"))["economy"] if args.economy
               else [row for data in datasets for row in data["economy"]])
    assert len({(r["seed"], r["policy"]) for r in economy}) == len(economy), "Duplicate economy samples"
    for policy in sorted({r["policy"] for r in economy}):
        selected = [r for r in economy if r["policy"] == policy]
        checkpoints = {}
        for turn in [1, 4, 6, 9, 11, 16, 21]:
            samples = [next(s for s in r["samples"] if s["turn"] == turn) for r in selected]
            checkpoints[str(turn)] = {field:mean([s[field] for s in samples])
                                      for field in ("gold", "income", "upkeep", "houses")}
            for key in ("knight_shock", "knight_after_one_collection"):
                if key not in samples[0]: continue
                checkpoints[str(turn)][key] = {
                    "purchased":sum(s[key]["purchased"] for s in samples),
                    "survived_30":sum(s[key]["survived_30"] for s in samples),
                    "death_settlements":dict(collections.Counter(str(s[key]["death_settlement"]) for s in samples if s[key]["purchased"]))}
        summary["economy"][policy] = {"runs":len(selected),"checkpoints":checkpoints}
    args.output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    if args.report:
        write_report(args.report, summary)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()

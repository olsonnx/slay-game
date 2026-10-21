"""Summarise balanced six-player approach_probe.gd tournaments."""
import argparse
import collections
import json
import random
import statistics
from pathlib import Path

STYLES = ("economic", "defensive", "aggressive")


def avg(values):
    return round(statistics.mean(values), 3) if values else None


def summarise(datasets):
    matches = [m for data in datasets for m in data["matches"]]
    assert all(data["failures"] == 0 for data in datasets), "A probe reported failures"
    assert len({(m["seed"], m["rotation"]) for m in matches}) == len(matches), "Duplicate matches"
    assert all(collections.Counter(m["policies"]) == {s: 2 for s in STYLES} for m in matches)
    result = {"matches":len(matches), "completed":sum(m["winner"] >= 0 for m in matches),
              "unfinished":sum(m["winner"] < 0 for m in matches),
              "mean_rounds":avg([m["rounds"] for m in matches]),
              "seeds":sorted({m["seed"] for m in matches}),
              "rotations":sorted({m["rotation"] for m in matches}),
              "thresholds":sorted({float(d["options"]["threshold"]) for d in datasets}),
              "round_limits":sorted({int(d["options"]["rounds"]) for d in datasets}),
              "board_cells":sorted({m["board_cells"] for m in matches}),"styles":{},
              "by_seed":{},"by_rotation":{},"checks":sum(d["checks"] for d in datasets)}
    for style in STYLES:
        entries = [(m, i) for m in matches for i, p in enumerate(m["policies"]) if p == style]
        final = [m["history"][-1][i] for m, i in entries]
        telemetry = [m["telemetry"][i] for m, i in entries]
        totals = {key:sum(t.get(key, 0) for t in telemetry) for key in
                  ("active_turns", "bankruptcies", "deaths", "unsupported_deaths", "deficit_at_end", "house", "tower", "develop", "entrench", "recruit", "attacks", "hostile_captures", "neutral_captures", "paid")}
        wins = sum(m["winner"] == i for m, i in entries)
        eliminated = sum(row["capitals"] == 0 for row in final)
        unresolved = sum(m["winner"] < 0 and m["history"][-1][i]["capitals"] > 0 for m, i in entries)
        assert wins + eliminated + unresolved == len(entries)
        item = {"participants":len(entries),"wins":wins,"eliminated":eliminated,
                "alive_unfinished":unresolved,"telemetry_totals":totals,
                "per_active_turn":{k:round(v/max(1,totals["active_turns"]),4) for k,v in totals.items() if k != "active_turns"},
                "ever_attacked":sum(t.get("attacks",0) > 0 for t in telemetry),
                "ever_bankrupt":sum(t.get("bankruptcies",0) > 0 for t in telemetry),
                "unlocked_war":sum(m["unlocked"][i] > 0 for m,i in entries),
                "mean_unlock_round":avg([m["unlocked"][i] for m,i in entries if m["unlocked"][i] > 0]),
                "mean_winning_round":avg([m["rounds"] for m,i in entries if m["winner"] == i]),
                "median_winning_round":statistics.median([m["rounds"] for m,i in entries if m["winner"] == i]) if wins else None,
                "seat_coverage":dict(collections.Counter(str(i) for m,i in entries)),
                "checkpoints":{}}
        for turn in (5,10,20,40,80):
            rows = [m["history"][min(turn-1,len(m["history"])-1)][i] for m,i in entries]
            checkpoint = {k:avg([r[k] for r in rows]) for k in rows[0]}
            checkpoint["entrenched_fraction_of_units"] = round(sum(r["entrenched"] for r in rows)/max(1,sum(r["units"] for r in rows)),4)
            checkpoint["games_already_finished"] = sum(len(m["history"]) < turn for m,i in entries)
            item["checkpoints"][str(turn)] = checkpoint
        result["styles"][style] = item
    for field in ("seed","rotation"):
        for value in sorted({m[field] for m in matches}):
            sub = [m for m in matches if m[field] == value]
            result["by_"+field][str(value)] = {"matches":len(sub),"wins":dict(collections.Counter(m["winning_style"] for m in sub))}
    deltas = [(v["wins"].get("economic",0)-v["wins"].get("aggressive",0))/v["matches"] for v in result["by_seed"].values()]
    rng = random.Random(20261019)
    bootstrap = sorted(statistics.mean(rng.choices(deltas,k=len(deltas))) for _ in range(10000))
    result["economic_minus_aggressive_win_share_map_bootstrap_95"] = [round(bootstrap[249],4),round(bootstrap[9749],4)]
    return result


def report(path, main, sensitivities):
    n = main["matches"]
    s = main["styles"]
    assert all(x["participants"] == n*2 for x in s.values())
    assert all(len(x["seat_coverage"]) == 6 and len(set(x["seat_coverage"].values())) == 1 for x in s.values()), "Unbalanced faction/turn-order seats"
    assert all(v["matches"] == len(main["rotations"]) for v in main["by_seed"].values()), "Incomplete seed rotations"
    most_wins = max(x["wins"] for x in s.values())
    leaders = ", ".join(p.title() for p in STYLES if s[p]["wins"] == most_wins)
    interval = main["economic_minus_aggressive_win_share_map_bootstrap_95"]
    close = "The map-level uncertainty interval does not separate Economic from Aggressive, so their observed ranking should be treated as provisional." if interval[0] <= 0 <= interval[1] else "The observed Economic/Aggressive difference is consistent across the sampled map clusters, but remains specific to these AI policies and maps."
    wins_table = "\n".join(f"| {p.title()} | {s[p]['wins']} | {s[p]['eliminated']} | {s[p]['alive_unfinished']} |" for p in STYLES)
    economy_table = "\n".join(f"| {p.title()} | {s[p]['checkpoints']['10']['income']:.1f} | {s[p]['checkpoints']['10']['land']:.1f} | {s[p]['checkpoints']['10']['houses']:.1f} | {s[p]['checkpoints']['10']['towers']:.1f} | {s[p]['checkpoints']['10']['entrenched_fraction_of_units']:.1%} |" for p in STYLES)
    safety_table = "\n".join(f"| {p.title()} | {s[p]['per_active_turn']['bankruptcies']*100:.1f} | {s[p]['per_active_turn']['attacks']:.2f} | {s[p]['mean_unlock_round']:.1f} |" for p in STYLES)
    by_seed = "\n".join(f"| {seed} | {v['wins'].get('economic',0)} | {v['wins'].get('defensive',0)} | {v['wins'].get('aggressive',0)} | {v['wins'].get('unfinished',0)} |" for seed,v in main["by_seed"].items())
    sensitivity_text = "No separate threshold sensitivity tournament was included."
    if sensitivities:
        rows = []
        for summary in sensitivities:
            rows.append(f"| {summary['thresholds'][0]:.2f}x | {summary['matches']} | {summary['styles']['economic']['wins']} | {summary['styles']['defensive']['wins']} | {summary['styles']['aggressive']['wins']} | {summary['unfinished']} |")
        sensitivity_text = f"Only the income threshold changes in these additional tournaments. The policies and rules are otherwise identical. These tests use seeds {sensitivities[0]['seeds']} and assignments {sensitivities[0]['rotations']}. The 1.50x row reuses the exact matching primary cases (same seeds and assignments), not extra simulations; compare threshold rows against that matched control rather than against a different map mix.\n\n| Income needed vs average rival | Matches | Economic wins | Defensive wins | Aggressive wins | Unfinished |\n| --- | ---: | ---: | ---: | ---: | ---: |\n" + "\n".join(rows)
    text = f"""# Standard-map approach comparison - 19 October 2026

## Finding

The most primary-match wins went to **{leaders}** ({most_wins} of {n}). Economic won {s['economic']['wins']}, Defensive {s['defensive']['wins']}, and Aggressive {s['aggressive']['wins']}; {main['unfinished']} games remained unfinished. {close}

Aggressive play's round-ten mean gross income was {s['aggressive']['checkpoints']['10']['income']:.1f}, versus {s['economic']['checkpoints']['10']['income']:.1f} for Economic and {s['defensive']['checkpoints']['10']['income']:.1f} for Defensive. Rapid expansion is itself an economic investment in these rules. Defensive positions had more towers and a higher entrenched share at the checkpoint; compare that protection with wins and survival rather than assuming fortification implies victory.

## Scope

{n} primary matches on the map labelled **Standard** in the game menu (`large`, approximately 250 tiles), with six independent factions: two Economic, two Defensive and two Aggressive. They are enemies, not teams. Modern rules, Normal shared tactical analysis, unchanged resources and prices, and an {main['round_limits'][0]}-round limit. The generated boards had {min(main['board_cells'])}-{max(main['board_cells'])} cells, including bridges added during play.

Seeds: {main['seeds']}. Six assignments per seed cover both cyclic orders of the three styles and all three offsets. Every style occupies every faction/turn-order seat twice on each map. This controls geography and first-player effects without claiming independent evidence from every seat. There are {n*2} faction outcomes per style, drawn from {n} actual matches, not {n*6} matches.

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

{main['completed']} matches finished and {main['unfinished']} remained unfinished at the limit. Mean observed length: {main['mean_rounds']:.1f} rounds, including unfinished matches at the limit.

| Style | Winning faction | Eliminated factions | Factions still alive in unfinished matches |
| --- | ---: | ---: | ---: |
{wins_table}

Each row sums to {n*2} faction outcomes. A match has one winner. Because there are two independent factions per style, a style's match wins equal its number of winning factions; do not interpret wins/{n*2} as the style's share of matches. No-capital positions count as eliminated even if isolated land remains. Unfinished games are not assigned to the richest or largest faction.

### Economy and position after ten rounds

Population means include eliminated positions. If a game finishes before a checkpoint, its terminal board is carried forward without inventing later income collections. Entrenchment is entrenched units divided by all surviving units at that checkpoint, avoiding the misleading comparison of raw entrench counts between differently sized armies.

| Style | Gross income | Provinces | Houses | Towers | Units entrenched |
| --- | ---: | ---: | ---: | ---: | ---: |
{economy_table}

### War and financial risk

| Style | Bankrupt kingdom settlements per 100 active faction turns | Hostile attacks per active turn | Mean war-unlock round among unlocked factions |
| --- | ---: | ---: | ---: |
{safety_table}

Bankruptcy counts a local bank whose gold plus income minus upkeep is negative immediately before settlement. It is separate from unsupported-unit deaths, which are recorded in the raw telemetry. Troop affordability at recruitment does not guarantee future safety: enemy captures, splits, tree growth and events can remove the supporting income before the next settlement. `deficit_at_end` separately records an already-insolvent bank when a faction finishes its own actions. No policy receives debt forgiveness or extra resources.

### Map-to-map variation

| Seed | Economic wins | Defensive wins | Aggressive wins | Unfinished |
| --- | ---: | ---: | ---: | ---: |
{by_seed}

There are only {len(main['seeds'])} distinct maps. Multiple assignments on one map are correlated. A small lead in aggregate wins is not enough to establish a universal best strategy, especially if the winning style changes by map.

Resampling whole maps with replacement 10,000 times (fixed RNG seed 20261019), the 95% percentile interval for Economic minus Aggressive match-win share is {main['economic_minus_aggressive_win_share_map_bootstrap_95']}. This exploratory interval preserves the six assignments belonging to a map as a cluster; it is not a guarantee about unseen maps or human play.

## Sensitivity to the economic lead requirement

{sensitivity_text}

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
"""
    path.write_text(text, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs",nargs="+",type=Path)
    parser.add_argument("--sensitivity",nargs="*",type=Path,default=[])
    parser.add_argument("--output",type=Path,default=Path("artifacts/approach-summary.json"))
    parser.add_argument("--report",type=Path)
    args = parser.parse_args()
    data = [json.loads(p.read_text(encoding="utf-8")) for p in args.inputs]
    summary = summarise(data)
    sensitivity_data = collections.defaultdict(list)
    for p in args.sensitivity:
        d = json.loads(p.read_text(encoding="utf-8"))
        sensitivity_data[float(d["options"]["threshold"])].append(d)
    sensitivity_results = [summarise(v) for k,v in sorted(sensitivity_data.items())]
    if sensitivity_data:
        common = set.intersection(*[{(m["seed"],m["rotation"]) for d in ds for m in d["matches"]} for ds in sensitivity_data.values()])
        baseline_subset = [m for d in data for m in d["matches"] if (m["seed"],m["rotation"]) in common]
        if baseline_subset:
            control = summarise([{"matches":baseline_subset,"options":data[0]["options"],"checks":0,"failures":0}])
            control["reused_primary_cases"] = True
            sensitivity_results.append(control)
            sensitivity_results.sort(key=lambda x:x["thresholds"][0])
    summary["sensitivity"] = sensitivity_results
    args.output.write_text(json.dumps(summary,indent=2)+"\n",encoding="utf-8")
    if args.report: report(args.report,summary,sensitivity_results)
    print(json.dumps({k:v for k,v in summary.items() if k not in ("styles",)},indent=2))
    for p,entry in summary["styles"].items():
        print(p, json.dumps({k:v for k,v in entry.items() if k not in ("checkpoints","telemetry_totals")},sort_keys=True))


if __name__ == "__main__":
    main()

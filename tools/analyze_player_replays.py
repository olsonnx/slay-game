"""Extract evidence and bounded counterfactual positions from actual player games."""
from collections import Counter
from copy import deepcopy
import base64
import gzip
import hashlib
import json
from pathlib import Path
import sys
import replay_report as replay

OUT = Path(__file__).parents[1] / "artifacts/player-replay-analysis"
DIRECTIONS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]


def faction_units(state, faction):
    return Counter(int(cell["unit"]) for cell in state["cells"].values()
                   if cell["unit"] and (cell["unit_owner"] if cell["building"] == "bridge" else cell["owner"]) == faction)


def bank_gold(state, faction):
    return sum(bank["gold"] for bank in state["kingdoms"].values() if bank["owner"] == faction)


def defense(state, coord):
    cell = state["cells"][coord]
    def local(value):
        return max(value["unit"], int(value["capital"] >= 0), 2 if value["building"] == "tower" else 0)
    strength = local(cell)
    q, r = map(int, coord[5:].split(","))
    for dq, dr in DIRECTIONS:
        adjacent = state["cells"].get(f"@hex:{q+dq},{r+dr}")
        if adjacent and adjacent["owner"] == cell["owner"]:
            strength = max(strength, min(2, local(adjacent)))
    return strength


def analyze(path):
    outer = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
    raw = gzip.decompress(base64.b64decode(outer[-1]["data"]))
    assert hashlib.sha256(raw).hexdigest() == outer[0]["sha256"]
    rows = [json.loads(line) for line in raw.decode().splitlines()]
    header, commands = rows[0], rows[1:]
    assert [replay.decision_line(row) for row in commands if row["action"] != "ai_decision"] == outer[1:-1]
    assert all(row["seq"] == index + 1 for index, row in enumerate(commands))
    state = deepcopy(header["initial"])
    count = int(header["factions"])
    stats = [{"faction":i, "purchases":Counter(), "new_units":Counter(), "spells":Counter(), "buildings":Counter(),
              "spending":Counter(), "captures":Counter(), "starved":0, "turns":[], "capital_losses":[],
              "first_knight":None, "peak_cash":0, "peak_knights":0} for i in range(count)]
    capital_attacks, bridge_examples, selected = [], [], []
    built_bridges, last_preparation, breached = {}, {}, set()
    thin_header = {key:header[key] for key in ("rules", "map_size", "seed", "factions", "metadata")}
    for row in commands:
        faction, action, args = int(row["faction"]), row["action"], row["args"]
        before_gold = bank_gold(state, faction) if faction >= 0 else 0
        before_banks = sum(bank["owner"] == faction for bank in state["kingdoms"].values())
        old_target = state["cells"].get(args.get("target", args.get("coord")), {})
        source_unit = state["cells"].get(args.get("coord"), {}).get("unit", 0)
        old_target = deepcopy(old_target)
        before_defense = defense(state, args["target"]) if action == "move" else None
        before_capitals = {key:bank for key,bank in state["kingdoms"].items() if key in row["delta"].get("kingdoms", {}).get("erase", [])}
        replay.apply_delta(state, row["delta"])
        if faction < 0:
            continue
        stat = stats[faction]
        if action == "recruit":
            rank = int(args["tier"])
            stat["purchases"][rank] += 1
            stat["new_units"][rank] += int(source_unit == 0)
            stat["spending"]["recruit"] += args["cost"]
            if rank == 3 and stat["first_knight"] is None: stat["first_knight"] = row["round"]
        if action == "spell": stat["spells"][args["spell"]] += 1
        if action == "build":
            stat["buildings"][args["building"]] += 1
            stat["spending"][args["building"]] += before_gold - bank_gold(state, faction)
            if args["building"] == "bridge":
                bridge = {"seq":row["seq"], "round":row["round"], "faction":faction, "coord":args["coord"], "used_by":Counter(),
                          "merged_banks":sum(bank["owner"] == faction for bank in state["kingdoms"].values()) < before_banks}
                bridge_examples.append(bridge)
                built_bridges[args["coord"]] = bridge
        if action == "develop": stat["spending"]["develop"] += before_gold - bank_gold(state, faction)
        if action == "turn_start": stat["starved"] += args.get("starved", 0)
        if action == "move" and old_target:
            for coord in args.get("path", []):
                if coord in built_bridges: built_bridges[coord]["used_by"][faction] += 1
            new_target = state["cells"].get(args["target"], {})
            if old_target["owner"] != faction and new_target.get("owner") == faction:
                stat["captures"]["neutral" if old_target["owner"] < 0 else "enemy"] += 1
                if old_target["capital"] >= 0:
                    victim = int(old_target["owner"])
                    lost_bank = before_capitals.get(args["target"], {})
                    event = {"seq":row["seq"], "round":row["round"], "faction":faction, "victim":victim,
                             "coord":args["target"], "attacker_rank":args["tier"], "defender_rank":old_target["unit"],
                             "defense":before_defense, "treasury_lost":lost_bank.get("gold",0)}
                    stats[victim]["capital_losses"].append(event)
                    capital_attacks.append(event)
                    if faction == 0 and victim not in breached and victim in last_preparation:
                        checkpoint = deepcopy(last_preparation[victim])
                        checkpoint["purpose"] = "last_preparation_before_first_capital_loss"
                        checkpoint["later_capital_loss"] = event
                        selected.append(checkpoint)
                        breached.add(victim)
        units_now = faction_units(state, faction)
        stat["peak_knights"] = max(stat["peak_knights"], units_now[3])
        if units_now[3] and stat["first_knight"] is None: stat["first_knight"] = row["round"]
        if action in ("turn_start", "turn_end"):
            units = faction_units(state, faction)
            stat["peak_knights"] = max(stat["peak_knights"], units[3])
            if units[3] and stat["first_knight"] is None: stat["first_knight"] = row["round"]
            banks = [bank for bank in row.get("economy", []) if bank["faction"] == faction]
            economy = {key:sum(bank[key] for bank in banks) for key in ("gold", "income", "wages")}
            stat["peak_cash"] = max(stat["peak_cash"], economy["gold"])
            turn = {"seq":row["seq"], "round":row["round"], "phase":action, "units":dict(units),
                    "land":sum(cell["owner"] == faction for cell in state["cells"].values()), **economy}
            stat["turns"].append(turn)
            if action == "turn_start" and faction > 0:
                last_preparation[faction] = {"id":f"{header['map_size']}-{int(row['seq'])}", "faction":faction, "round":row["round"],
                                             "seq":row["seq"], "header":thin_header, "position":deepcopy(state)}
            # Keep before-spending states from both healthy and pressured economies.
            if action == "turn_start" and faction > 0 and 2 <= row["round"] <= 9 and len(selected) < 24:
                if economy["gold"] >= 20 and economy["income"] - economy["wages"] >= 18:
                    selected.append({"id":f"{header['map_size']}-{int(row['seq'])}", "faction":faction, "round":row["round"],
                                     "seq":row["seq"], "header":thin_header, "position":deepcopy(state)})
    result = {"file":path.name, "map":header["map_size"], "tiles":len(header["initial"]["cells"]),
              "seed":header["seed"], "metadata":header["metadata"], "rounds":commands[-1]["round"],
              "commands":len(commands), "factions":stats, "capital_attacks":capital_attacks, "bridges":bridge_examples}
    for sample in selected:
        (OUT / f"position-{sample['id']}.json").write_text(json.dumps(sample, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    return result


def main():
    OUT.mkdir(exist_ok=True)
    results = [analyze(Path(path)) for path in sys.argv[1:]]
    (OUT / "summary.json").write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")
    for result in results:
        print(result["map"], result["tiles"], result["rounds"], result["metadata"])
        for faction in result["factions"]:
            print({key:value for key,value in faction.items() if key not in ("turns", "capital_losses")})


if __name__ == "__main__":
    main()

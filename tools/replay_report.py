"""Verify/reconstruct a replay and summarize decisions without running Godot."""
from __future__ import annotations

import argparse
import base64
from collections import Counter
from copy import deepcopy
import hashlib
import gzip
import io
import json
from pathlib import Path

MAX_FILE_BYTES = 64 * 1024 * 1024
MAX_DETAIL_BYTES = 256 * 1024 * 1024


def read_lines(path: Path) -> list[str]:
    with path.open("rb") as source:
        data = source.read(MAX_FILE_BYTES + 1)
    if len(data) > MAX_FILE_BYTES:
        raise ValueError("Replay file is too large")
    return data.decode("utf-8").splitlines()


def fingerprint(position: dict) -> str:
    def integers(value):
        if isinstance(value, float):
            return int(value)  # Godot parses JSON numbers as doubles; position fields are integers.
        if isinstance(value, list):
            return [integers(item) for item in value]
        if isinstance(value, dict):
            return {key: integers(item) for key, item in value.items()}
        return value
    return hashlib.sha256(json.dumps(integers(position), sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def brief(value):
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, str) and value.startswith("@hex:"):
        return value[5:]
    if isinstance(value, list):
        return [brief(item) for item in value]
    if isinstance(value, dict):
        return {key: brief(item) for key, item in value.items() if key != "path"}
    return value


def decision_line(command: dict) -> dict:
    return {command["action"]: [command["seq"], command["round"], command["faction"], brief(command["args"])]}


def validate_command(command) -> None:
    if (not isinstance(command, dict) or command.get("type") != "command"
            or not isinstance(command.get("action"), str)
            or not isinstance(command.get("args"), dict)
            or not isinstance(command.get("delta"), dict)
            or any(type(command.get(key)) is not int for key in ("seq", "round", "faction"))
            or command["seq"] < 1 or command["round"] < 1 or not -1 <= command["faction"] < 64):
        raise ValueError("Invalid command")


def expand_archive(lines: list[str]) -> list[str]:
    if not lines:
        raise ValueError("Invalid replay header")
    envelope = json.loads(lines[0])
    if not isinstance(envelope, dict):
        raise ValueError("Invalid replay header")
    if envelope.get("version") == 1:
        return lines
    if envelope.get("format") != "slay-replay" or envelope.get("version") != 2 or envelope.get("encoding") != "gzip-base64":
        raise ValueError("Unsupported replay format/version")
    try:
        compressed = base64.b64decode(json.loads(lines[-1])["data"], validate=True)
        with gzip.GzipFile(fileobj=io.BytesIO(compressed)) as details:
            raw = details.read(MAX_DETAIL_BYTES + 1)
    except (ValueError, KeyError, OSError, EOFError) as error:
        raise ValueError("Invalid compressed replay details") from error
    if len(raw) > MAX_DETAIL_BYTES:
        raise ValueError("Replay details are too large")
    if hashlib.sha256(raw).hexdigest() != envelope.get("sha256"):
        raise ValueError("Replay archive checksum mismatch")
    expanded = raw.decode("utf-8").splitlines()
    if envelope.get("derived_hashes", False):
        state = {}
        for index, line in enumerate(expanded):
            row = json.loads(line)
            if index == 0:
                if not isinstance(row, dict) or not isinstance(row.get("initial"), dict):
                    raise ValueError("Invalid initial position")
                state = deepcopy(row["initial"])
            else:
                validate_command(row)
                apply_delta(state, row["delta"])
            row["hash"] = fingerprint(state)
            expanded[index] = json.dumps(row, separators=(",", ":"), ensure_ascii=False)
    original_header = json.loads(expanded[0])
    if not isinstance(original_header, dict):
        raise ValueError("Invalid replay header")
    if any(original_header.get(key) != envelope.get(key) for key in ("seed", "rules", "names", "humans")):
        raise ValueError("Replay metadata mismatch")
    commands = list(map(json.loads, expanded[1:]))
    for command in commands:
        validate_command(command)
    expected = [decision_line(row) for row in commands if row["action"] != "ai_decision"]
    if list(map(json.loads, lines[1:-1])) != expected:
        raise ValueError("Readable decision timeline mismatch")
    return expanded


def archive(lines: list[str]) -> str:
    """Losslessly wrap complete v1 records in a readable, compact v2 file."""
    header = json.loads(lines[0])
    slim = []
    for line in lines:
        row = json.loads(line)
        row.pop("hash", None)
        slim.append(json.dumps(row, separators=(",", ":"), ensure_ascii=False))
    raw = ("\n".join(slim) + "\n").encode("utf-8")
    if len(raw) > MAX_DETAIL_BYTES:
        raise ValueError("Replay details are too large")
    envelope = {"format": "slay-replay", "version": 2, "seed": header["seed"], "rules": header["rules"],
                "names": header["names"], "humans": header["humans"],
                "encoding": "gzip-base64", "columns": ["sequence", "round", "faction", "arguments"],
                "derived_hashes": True, "sha256": hashlib.sha256(raw).hexdigest()}
    rows = [envelope]
    rows.extend(decision_line(row) for row in map(json.loads, lines[1:]) if row["action"] != "ai_decision")
    rows.append({"data": base64.b64encode(gzip.compress(raw, compresslevel=9, mtime=0)).decode("ascii")})
    result = "\n".join(json.dumps(row, separators=(",", ":"), ensure_ascii=False) for row in rows) + "\n"
    if len(result.encode("utf-8")) > MAX_FILE_BYTES:
        raise ValueError("Replay file is too large")
    return result


def apply_delta(position: dict, changes: dict) -> None:
    if not isinstance(position, dict) or not isinstance(changes, dict):
        raise ValueError("Invalid replay delta")
    # Check every section first so a rejected patch cannot partly change state.
    for section, delta in changes.items():
        if section not in position or not isinstance(delta, dict):
            raise ValueError("Invalid replay delta")
        if "value" in delta:
            if (set(delta) != {"value"} or isinstance(position[section], dict)
                    or type(delta["value"]) is not type(position[section])):
                raise ValueError("Invalid replay delta")
        elif (set(delta) != {"erase", "set"}
              or not isinstance(delta["erase"], list)
              or not all(isinstance(key, str) for key in delta["erase"])
              or not isinstance(delta["set"], dict)
              or not isinstance(position.get(section), dict)):
            raise ValueError("Invalid replay delta")
    for section, delta in changes.items():
        if "value" in delta:
            position[section] = delta["value"]
        else:
            for key in delta["erase"]:
                position[section].pop(key, None)
            position[section].update(delta["set"])


def load(path: Path, stop_at: int | None = None) -> tuple[dict, list[dict], dict, bool]:
    lines = expand_archive(read_lines(path))
    header = json.loads(lines[0])
    if header.get("format") != "slay-replay" or header.get("version") != 1:
        raise ValueError("Unsupported replay format/version")
    if not isinstance(header.get("initial"), dict):
        raise ValueError("Invalid initial position")
    position = deepcopy(header["initial"])
    if fingerprint(position) != header["hash"]:
        raise ValueError("Initial position hash mismatch")
    commands = []
    incomplete = False
    for index, line in enumerate(lines[1:], 2):
        if not line.strip():
            continue
        try:
            command = json.loads(line)
        except json.JSONDecodeError:
            if index == len(lines):
                incomplete = True
                break  # A crash can interrupt only the final append.
            raise
        validate_command(command)
        if command["seq"] != len(commands) + 1:
            raise ValueError(f"Invalid command at line {index}")
        if stop_at is not None and command["seq"] > stop_at:
            break
        apply_delta(position, command["delta"])
        if fingerprint(position) != command["hash"]:
            raise ValueError(f"Position hash mismatch at command {command['seq']}")
        commands.append(command)
    return header, commands, position, incomplete


def report(path: Path, header: dict, commands: list[dict], position: dict, incomplete: bool) -> str:
    lines = [f"Replay: {path.name}", f"Rules: {header['rules']}; seed: {header['seed']}; map: {header['map_size']}",
             f"Verified commands: {len(commands)}; rounds reached: {max((c['round'] for c in commands), default=1)}"]
    result = next((c["args"] for c in reversed(commands) if c["action"] == "result"), None)
    lines.append(f"Result: {result if result else 'unfinished recording'}")
    if incomplete:
        lines.append("The incomplete final line was ignored; all preceding positions were verified.")
    for faction in range(int(position.get("faction_count", header["factions"]))):
        actions = [c for c in commands if c["faction"] == faction]
        counts = Counter(c["action"] for c in actions if c["action"] != "ai_decision")
        houses = sum(c["action"] == "build" and c["args"].get("building") == "house" for c in actions)
        deaths = sum(c["args"].get("starved", 0) for c in actions if c["action"] == "turn_start")
        owned = [cell for cell in position["cells"].values() if cell["owner"] == faction]
        deployment = sum(cell["building"] == "" and not cell["mountain"] and cell["unit"] == 0 and cell["barrier_by"] < 0 for cell in owned)
        lines.extend(["", f"{faction}: {header['names'][faction]} ({'human' if faction in header['humans'] else 'AI'})",
                      f"Actions: {dict(counts)}", f"Houses built: {houses}; units starved: {deaths}; final land: {len(owned)}; open deployment sites: {deployment}",
                      "Turn finances (round: gold / income / wages):"])
        for command in actions:
            if command["action"] != "turn_start":
                continue
            banks = [b for b in command.get("economy", []) if b["faction"] == faction]
            totals = [sum(b[key] for b in banks) for key in ("gold", "income", "wages")]
            lines.append(f"  {command['round']}: {' / '.join(map(str, totals))} ({len(banks)} kingdoms)")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("replay", type=Path)
    parser.add_argument("--at", type=int, help="Reconstruct only through this command (0 = initial position)")
    parser.add_argument("--position", type=Path, help="Write the reconstructed position as JSON")
    parser.add_argument("--output", type=Path, help="Write the report instead of printing it")
    parser.add_argument("--compact", type=Path, help="Losslessly convert a completed legacy replay to version 2")
    parser.add_argument("--expand", type=Path, help="Write every original detail record as ordinary JSON Lines")
    args = parser.parse_args()
    try:
        header, commands, position, incomplete = load(args.replay, args.at)
        if args.expand:
            lines = expand_archive(read_lines(args.replay))
            args.expand.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        if args.compact:
            if args.at is not None or incomplete or not commands or commands[-1]["action"] != "result" or commands[-1]["args"].get("outcome") not in ("completed", "victory", "defeat", "draw"):
                raise ValueError("Only completed games can be compacted")
            lines = expand_archive(read_lines(args.replay))
            args.compact.write_text(archive(lines), encoding="utf-8", newline="\n")
    except (ValueError, KeyError, OSError, IndexError, TypeError) as error:
        parser.exit(1, f"Replay error: {error}\n")
    text = report(args.replay, header, commands, position, incomplete)
    if args.output:
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    if args.position:
        args.position.write_text(json.dumps(position, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()

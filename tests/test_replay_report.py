"""Independent reader checks; no Godot installation required."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("replay_report", Path(__file__).parents[1] / "tools/replay_report.py")
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)


class ReplayReportTests(unittest.TestCase):
    def setUp(self):
        directory = Path(__file__).parents[1] / "artifacts"
        directory.mkdir(exist_ok=True)
        self.path = directory / f"replay-report-{self._testMethodName}.jsonl"
        self.addCleanup(self.path.unlink, missing_ok=True)
        initial = {"cells": {}, "rng": "9223372036854775800"}
        self.header = {"format": "slay-replay", "version": 1, "initial": initial, "hash": replay.fingerprint(initial),
                       "seed": 42, "rules": "modern", "names": ["Fern", "Ember"], "humans": [0]}
        position = deepcopy(initial)
        position["cells"]["@hex:1,2"] = {"unit": 3, "owner": 0}
        self.command = {"type": "command", "seq": 1, "round": 1, "faction": 0, "action": "move",
                        "args": {"source": "@hex:1,1", "target": "@hex:1,2", "path": ["@hex:1,1", "@hex:1,2"]},
                        "delta": {"cells": {"set": position["cells"], "erase": []}}, "hash": replay.fingerprint(position)}
        self.contents = json.dumps(self.header) + "\n" + json.dumps(self.command) + "\n"
        self.path.write_text(self.contents, encoding="utf-8")

    def test_authored_kingdom_command(self):
        command = deepcopy(self.command)
        command["faction"] = 11
        replay.validate_command(command)
        command["faction"] = 64
        with self.assertRaises(ValueError):
            replay.validate_command(command)

    def test_reconstructs_without_mutating_header(self):
        header, commands, position, partial = replay.load(self.path)
        self.assertEqual(position["rng"], "9223372036854775800")
        self.assertEqual(position["cells"]["@hex:1,2"]["unit"], 3)
        self.assertEqual(header["initial"]["cells"], {})
        self.assertEqual(len(commands), 1)
        self.assertFalse(partial)

    def test_selects_initial_position(self):
        _, commands, position, _ = replay.load(self.path, 0)
        self.assertEqual(commands, [])
        self.assertEqual(position, self.header["initial"])

    def test_rejects_broken_sequence(self):
        self.path.write_text(self.contents.replace('"seq": 1', '"seq": 9'), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Invalid command"):
            replay.load(self.path)

    def test_rejects_wrong_position(self):
        self.path.write_text(self.contents.replace('"unit": 3', '"unit": 2'), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            replay.load(self.path)

    def test_recovers_complete_prefix(self):
        self.path.write_text(self.contents + '{"type":', encoding="utf-8")
        _, commands, _, partial = replay.load(self.path)
        self.assertTrue(partial)
        self.assertEqual(len(commands), 1)

    def test_compact_format_preserves_every_record(self):
        original = self.contents.splitlines()
        compact = replay.archive(original)
        # Every field is preserved; JSON whitespace is deliberately removed.
        self.assertEqual(list(map(json.loads, replay.expand_archive(compact.splitlines()))), list(map(json.loads, original)))
        self.path.write_text(compact, encoding="utf-8")
        header, commands, position, _ = replay.load(self.path)
        self.assertEqual(commands[0], self.command)
        self.assertEqual(header, self.header)
        self.assertEqual(position["cells"]["@hex:1,2"]["unit"], 3)
        self.assertNotIn("path", json.loads(compact.splitlines()[1])["move"][3])
        self.assertIn("path", commands[0]["args"])

    def test_rejects_changed_readable_timeline(self):
        compact = replay.archive(self.contents.splitlines())
        self.path.write_text(compact.replace('"move":[', '"attack":['), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "timeline mismatch"):
            replay.load(self.path)

    def test_rejects_changed_archive_checksum(self):
        lines = replay.archive(self.contents.splitlines()).splitlines()
        envelope = json.loads(lines[0])
        envelope["sha256"] = "0" * 64
        lines[0] = json.dumps(envelope)
        self.path.write_text("\n".join(lines), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            replay.load(self.path)

    def test_rejects_missing_archive_details(self):
        lines = replay.archive(self.contents.splitlines()).splitlines()[:-1]
        self.path.write_text("\n".join(lines), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Invalid compressed"):
            replay.load(self.path)

    def test_bounds_decompression_before_checksum_verification(self):
        self.path.write_text(replay.archive(self.contents.splitlines()), encoding="utf-8")
        with patch.object(replay, "MAX_DETAIL_BYTES", 32):
            with self.assertRaisesRegex(ValueError, "details are too large"):
                replay.load(self.path)

    def test_bounds_file_reads(self):
        with patch.object(replay, "MAX_FILE_BYTES", 16):
            with self.assertRaisesRegex(ValueError, "file is too large"):
                replay.load(self.path)

    def test_rejects_malformed_deltas_atomically(self):
        for delta in ({"cells": {}}, {"cells": None}, {"cells": {"value": []}}, {"cells": {"set": {}, "erase": False}},
                      {"missing": {"set": {}, "erase": []}}):
            position = deepcopy(self.header["initial"])
            with self.assertRaisesRegex(ValueError, "Invalid replay delta"):
                replay.apply_delta(position, delta)
            self.assertEqual(position, self.header["initial"])
        position = deepcopy(self.header["initial"])
        with self.assertRaises(ValueError):
            replay.apply_delta(position, {"cells": {"set": {"a": 1}, "erase": []}, "bad": {}})
        self.assertEqual(position, self.header["initial"])

    def test_rejects_malformed_compressed_patch(self):
        command = deepcopy(self.command)
        command["delta"] = {"cells": {}}
        contents = [json.dumps(self.header), json.dumps(command)]
        self.path.write_text(replay.archive(contents), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Invalid replay delta"):
            replay.load(self.path)

    def test_archive_respects_reader_limits(self):
        with patch.object(replay, "MAX_DETAIL_BYTES", 32):
            with self.assertRaisesRegex(ValueError, "details are too large"):
                replay.archive(self.contents.splitlines())
        with patch.object(replay, "MAX_FILE_BYTES", 32):
            with self.assertRaisesRegex(ValueError, "file is too large"):
                replay.archive(self.contents.splitlines())


if __name__ == "__main__":
    unittest.main()

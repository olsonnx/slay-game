"""Version labels retain the playtest marker without invalid Windows metadata."""
import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("game_version", Path(__file__).resolve().parents[1] / "tools/version.py")
version = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version)


class VersionTests(unittest.TestCase):
    def test_playtest_and_release_roundtrip(self):
        artifacts = Path(__file__).resolve().parents[1] / "artifacts"
        artifacts.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="version-test-", dir=artifacts) as folder:
            root = Path(folder)
            project = root / "project.godot"
            exports = root / "export_presets.cfg"
            project.write_text('config/version="0.2.0"\n', encoding="utf-8")
            exports.write_text('application/file_version="0.2.0.0"\napplication/product_version="0.2.0.0"\n', encoding="utf-8")
            for label in ["0.2.0P", "0.2.1"]:
                with patch.object(version, "ROOT", root), patch.object(sys, "argv", ["version.py", label]), contextlib.redirect_stdout(io.StringIO()):
                    version.main()
                self.assertEqual(version.setting(project.read_text(), "config/version"), label)
                self.assertEqual(version.setting(exports.read_text(), "application/file_version"), label.removesuffix("P") + ".0")
                with patch.object(version, "ROOT", root), patch.object(sys, "argv", ["version.py", "--check"]), contextlib.redirect_stdout(io.StringIO()):
                    version.main()

    def test_only_numeric_version_and_optional_uppercase_p(self):
        for label in ["0.2.0", "0.2.0P", "1.0.0P"]:
            self.assertIsNotNone(version.VERSION.fullmatch(label))
        for label in ["0.2.0p", "0.2.0PP", "0.2P", "0.2.0-beta", "01.2.0P"]:
            self.assertIsNone(version.VERSION.fullmatch(label))


if __name__ == "__main__":
    unittest.main()

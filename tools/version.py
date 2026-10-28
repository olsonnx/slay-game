"""Show, check or set the game version and matching Windows build metadata.

python tools/version.py
python tools/version.py --check
python tools/version.py 0.1.1
"""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")


def setting(text: str, key: str) -> str:
    matches = re.findall(r'^' + re.escape(key) + r'="([^"]*)"$', text, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one {key} setting")
    return matches[0]


def replace(text: str, key: str, value: str) -> str:
    setting(text, key)  # Reject missing or ambiguous settings before writing.
    return re.sub(r'^' + re.escape(key) + r'="[^"]*"$',
                  lambda _: f'{key}="{value}"', text, flags=re.MULTILINE)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", nargs="?", help="New MAJOR.MINOR.PATCH version")
    parser.add_argument("--check", action="store_true", help="Verify build versions match")
    args = parser.parse_args()
    if args.check and args.version:
        parser.error("Use --check without a new version")
    project_path = ROOT / "project.godot"
    export_path = ROOT / "export_presets.cfg"
    try:
        project = project_path.read_text(encoding="utf-8")
        exports = export_path.read_text(encoding="utf-8")
        version = args.version or setting(project, "config/version")
        if not VERSION.fullmatch(version) or any(int(part) > 65535 for part in version.split(".")):
            raise ValueError("Use MAJOR.MINOR.PATCH with each number between 0 and 65535")
        windows_version = version + ".0"
        keys = ("application/file_version", "application/product_version")
        if args.version:
            project = replace(project, "config/version", version)
            for key in keys:
                exports = replace(exports, key, windows_version)
            project_path.write_text(project, encoding="utf-8", newline="\n")
            export_path.write_text(exports, encoding="utf-8", newline="\n")
        elif args.check:
            for key in keys:
                if setting(exports, key) != windows_version:
                    raise ValueError(f"{key} must be {windows_version}")
        print(f"Game version: {version} (Windows: {windows_version})")
    except (OSError, ValueError) as error:
        parser.exit(1, f"Version error: {error}\n")


if __name__ == "__main__":
    main()

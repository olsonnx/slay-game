"""Maintain the English catalogue and blank translator template; never translate text.

Usage: python tools/localization_catalog.py [--check]
"""
import argparse
import ast
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXTRA = {
    "src/game/replay_summary.gd",
    "src/game/wildlife.gd",
    "src/game/game.gd", "src/game/game_catalog.gd", "src/game/spell_catalog.gd",
    "src/game/event_catalog.gd", "src/game/encounter_rules.gd", "src/game/tutorial.gd", "src/game/tutorial_lessons.gd",
    "src/game/player_actions.gd", "src/game/opponent_turns.gd", "src/game/kingdom_magic.gd",
    "src/game/match_setup.gd", "src/game/map_sizes.gd", "src/game/game_input.gd",
    "src/settings/key_settings.gd", "src/app/app.gd",
    "src/editor/level_document.gd", "src/editor/level_editor.gd", "src/editor/editor_view.gd",
    "src/editor/discard_dialog.gd",
    "src/localization/native_messages.gd",
}
# Engine classes, node names, enum/paint IDs and proper names are not message keys.
EXCLUDE = {
    "English", "Fern", "Ember", "Tide", "Ochre", "Aster", "Cove", "Master", "UI", "SFX",
    "Ruby", "Dawn", "Moss", "Frost", "Slate", "Iris",
    "Label", "Button", "OptionButton", "CheckButton", "LineEdit", "RichTextLabel",
    "Control", "Panel", "PopupMenu", "TooltipPanel", "TooltipLabel", "Tree", "ItemList",
    "HSlider", "HScrollBar", "VScrollBar", "TabBar", "PopupPanel", "AcceptDialog",
    "Theme", "Selection", "Shortcut", "TextureRect", "Node3D", "CapitalBanner",
}

def files():
    return sorted(p for p in (ROOT / "src").rglob("*.gd")
                  if p.relative_to(ROOT).as_posix() in EXTRA
                  or p.relative_to(ROOT).as_posix().startswith("src/ui/"))

def tokens(source):
    """GDScript strings with offsets, skipping comments and shader/multiline blocks."""
    pattern = re.compile(r'#[^\n]*|"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')
    for match in pattern.finditer(source):
        raw = match.group()
        if raw.startswith("#") or raw.startswith(('"""', "'''")):
            continue
        try:
            value = ast.literal_eval(raw)
        except (SyntaxError, ValueError):
            continue
        yield match.start(), match.end(), raw, value

def readable(value):
    if not value or value in EXCLUDE or not re.search(r"[A-Za-z]", value):
        return False
    if any(x in value for x in ("res://", "user://", "<svg", "<path", "<circle", "<rect", "[color=", "[font_size=", "</", "\\d", "\\s", "\\b")):
        return False
    if "_" in value and not re.search(r"\s", value):
        return False
    if re.fullmatch(r"[A-Za-z0-9_./:@#&]+", value):
        return value[0].isupper() and "_" not in value and "." not in value and not re.search(r"[a-z][A-Z]", value)
    return True

def catalogue():
    messages = {}
    for path in files():
        source = path.read_text(encoding="utf-8-sig")
        relative = path.relative_to(ROOT).as_posix()
        for start, end, raw, value in tokens(source):
            if not readable(value):
                continue
            prefix = source[source.rfind("\n", 0, start) + 1:start]
            # Never expose engine identifiers, node paths, style names or regex code.
            if re.search(r'\.name\s*=\s*$|get_node\(\s*$|set_meta\(\s*$|\.compile\(\s*$|add_theme_\w+\(\s*$', prefix):
                continue
            line = source.count("\n", 0, start) + 1
            messages.setdefault(value, []).append(f"{relative}:{line}")
    return {key: messages[key] for key in sorted(messages)}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if the source catalogue needs updating")
    parser.add_argument("--sync", type=Path, help="Add new empty entries to an existing language pack, preserving your translations")
    args = parser.parse_args()
    entries = catalogue()
    outputs = {
        "localization/languages/en.json": {"locale": "en", "name": "English", "messages": {key: key for key in entries}},
        "localization/template.json": {"locale": "", "name": "", "font": "", "messages": {key: "" for key in entries}},
        "localization/references.json": entries,
    }
    stale = []
    for relative, content in outputs.items():
        path = ROOT / relative
        serialized = json.dumps(content, ensure_ascii=False, indent=2) + "\n"
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != serialized:
                stale.append(relative)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(serialized, encoding="utf-8")
    if stale:
        raise SystemExit("Catalogue is out of date: " + ", ".join(stale))
    if args.sync:
        path = args.sync.resolve()
        if path in {(ROOT / relative).resolve() for relative in outputs}:
            raise SystemExit("Sync your own language pack, not the generated source/template files.")
        pack = json.loads(path.read_text(encoding="utf-8-sig"))
        existing = pack.get("messages", {})
        if not isinstance(existing, dict):
            raise SystemExit("The pack's messages field must be an object.")
        obsolete = pack.get("obsolete_messages", {})
        obsolete.update({key: value for key, value in existing.items() if key not in entries})
        pack["messages"] = {key: existing.get(key, "") for key in entries}
        if obsolete:
            pack["obsolete_messages"] = obsolete
        path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Updated {path.name}; existing translations preserved, removed source text retained in obsolete_messages.")
    print(f"Localization catalogue: {len(entries)} English messages; {'verified' if args.check else 'updated'}.")

if __name__ == "__main__":
    main()

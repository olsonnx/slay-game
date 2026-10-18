"""Launch the local Godot tutorial authoring tool; Python standard library only."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]

def find_godot(explicit=None):
    requested = explicit or os.environ.get('GODOT_EXE')
    if requested:
        candidate = Path(requested).expanduser()
        if candidate.is_file(): return candidate.resolve()
        raise FileNotFoundError('Godot executable not found: ' + str(candidate))
    for name in ('godot', 'godot4', 'godot_console'):
        found = shutil.which(name)
        if found: return Path(found)
    downloads = Path.home() / 'Downloads'
    candidates = list(downloads.glob('Godot*/*console.exe')) + list(downloads.glob('Godot*console.exe'))
    candidates += [p for p in downloads.glob('Godot*.exe') if p.is_file()]
    if candidates: return sorted(candidates, key=lambda p: p.stat().st_mtime, reverse=True)[0]
    raise FileNotFoundError('Godot 4 was not found. Run with --godot "C:\\path\\to\\Godot.exe" or set GODOT_EXE.')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', help='Path to the Godot 4 executable')
    parser.add_argument('--file', type=Path, help='Open a saved tutorial')
    parser.add_argument('--check', action='store_true', help='Check the launcher without opening a window')
    parser.add_argument('--wait', action='store_true', help='Wait until the tool exits')
    args = parser.parse_args()
    try:
        engine = find_godot(args.godot)
        if args.file and not args.file.is_file(): raise FileNotFoundError('Tutorial file not found: ' + str(args.file))
        if args.check:
            print('Godot:', engine)
            print('Project:', ROOT)
            return 0
        command = [str(engine), '--path', str(ROOT), '--script', 'tools/tutorial_editor.gd']
        if args.file: command += ['--', '--tutorial=' + str(args.file.resolve())]
        options = {'cwd': str(ROOT)}
        if os.name == 'nt': options['creationflags'] = subprocess.CREATE_NO_WINDOW
        process = subprocess.Popen(command, **options)
        return process.wait() if args.wait else 0
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())

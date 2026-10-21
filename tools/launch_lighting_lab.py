"""Open the lighting sandbox using the project's existing Godot discovery."""
from pathlib import Path
import importlib.util
import os
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('tutorial_launcher', root / 'tools/tutorial-editor/launch.py')
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)
try:
    engine = launcher.find_godot(sys.argv[1] if len(sys.argv) > 1 else None)
    options = {'cwd': str(root)}
    if os.name == 'nt': options['creationflags'] = subprocess.CREATE_NO_WINDOW
    subprocess.Popen([str(engine), '--path', str(root), 'res://scenes/lighting_lab.tscn'], **options)
except OSError as error:
    print(error, file=sys.stderr)
    sys.exit(1)

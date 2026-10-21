# Editor pointer responsiveness

A native Huge-map probe found that empty-space pointer motion called update_status(), which checked document.dirty() by sorting every coordinate, rebuilding every cell record and JSON-serializing the entire document. High-frequency mouse input repeated this work several times before the next frame.

The editor now caches its document summary when document state changes. Pointer motion only changes the displayed province detail or restores that summary. During a changed brush stroke, the unsaved marker is known to be set; the exact comparison runs when the stroke ends, preserving save/undo behavior.

## Large-map native verification

Godot 4.6.3 Compatibility renderer, RTX 2060, 1200 x 800, VSync off, 120 FPS test limit. Each probe generates a new Huge island (roughly 1,000 tiles), so these are representative runs rather than an exact seeded A/B comparison.

| Scenario | Before FPS | After FPS | Before input time/frame | After input time/frame |
| --- | ---: | ---: | ---: | ---: |
| Idle | 120 | 120 | 0.004 ms | 0.003 ms |
| Pointer hover | 65 | 119 | 8.07 ms | 0.40 ms |
| Eight mouse events/frame | 15 | 120 | 61.77 ms | 1.41 ms |
| Camera pan | 120 | 120 | 0.054 ms | 0.053 ms |
| Brush drag | 75 | 111 | 6.75 ms | 1.55 ms |

Logs: artifacts/editor-interaction-before.log and artifacts/editor-interaction-verified.log.

## Blank-map water preview

Water placement previews now retain one EditorBrushPreview mesh and two materials. Moving over empty hexes updates only the transform and colour selection, without creating/freeing gameplay overlay nodes. The editor caps itself at 120 FPS while attached, preserves lower limits, and restores the preceding limit when detached for playtest or closed.

Native full-application input (main menu, editor, blank Huge map) holds approximately 120 FPS under rapid water-hover events. Input handling costs about 1.29 ms per frame with eight events per frame. Reproduce with tools/editor_interaction_probe.gd using --blank --app --native-input after the Godot argument separator. Log: artifacts/editor-water-hover-application.log.

## Regression checks

- tests/test_editor_interaction.gd instruments document snapshots and verifies hover/brush samples avoid full-document serialization while metadata edits, dirty markers and undo remain correct.
- tests/test_editor_water_hover.gd exercises 2,000 water cursor updates with stable scene-node counts, first-tile placement/undo, UI occlusion and FPS-limit restoration.
- tests/test_editor_loading.gd verifies asynchronous map replacement and reusable bird textures.
- The broader editor suite retains its existing event-preview text-formatting failure (413 passed, 1 failed).

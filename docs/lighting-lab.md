# Lighting Lab

Double-click **Lighting Lab.cmd** in the project folder. Alternatively open `scenes/lighting_lab.tscn` in Godot and press **F6** (Run Current Scene).

The lab uses the real board renderer and a fixed, generated Modern map (seed 71). It runs separately from gameplay and does not change game lighting defaults or your match.

- Start with Atmospheric, Daylight, or Simple, then adjust sun strength, elevation, direction and color; ambient fill and color; shadows and softness; character lighting; brightness, contrast, saturation, grading and ambient occlusion.
- Drag the map to pan, right-drag to orbit, and use the wheel to zoom. Scroll the right panel to reach more controls, close/whole-map views, and saving.
- **Remember A**, make changes, then **Swap A / current** to compare two looks from the same camera.
- **Save experiment** stores one experiment across sessions. **Load experiment** restores it. This is separate from the session-only A slot.
- **Copy settings** copies the current values as JSON so you can share a preferred look for integration into the game.

## Diorama depth of field

Click **Depth of field controls** to jump to the new section. Lower zoom numbers mean a closer view. Use **Preview zoom** or the wheel over the map, and watch the live zoom/blur readout.

- **Blur starts below zoom** controls when zooming in begins to introduce blur. At this number and above, the scene is completely sharp.
- **Full blur below zoom** sets the close-up point where blur reaches its maximum. The effect fades smoothly between the two limits.
- **Maximum blur**, **Sharp focus band** and **Blur falloff** tune the strength and depth range. The center stays focused on the board, independently of the cursor.
- **Enable depth of field** allows a direct comparison with a sharp scene.

The current gameplay defaults start blur below zoom **16** and reach full strength at **9**. Lab changes affect only the preview. They are included in **Remember A**, **Save experiment**, **Load experiment**, and **Copy settings**. Use **Copy DOF settings** and paste the result in chat to share just the depth-of-field settings and preview zoom.

The save is `user://lighting_lab.cfg` in the project's Godot user-data folder. The launcher discovers Godot from GODOT_EXE, PATH, or Downloads; an explicit executable path can be passed as its first argument. Uses the current project renderer; ambient occlusion requires Forward+.

Validation: headless and native Forward+ smoke checks cover preset switching, live sun changes, A/B restoration, and disk save/load. Native screenshot: `artifacts/lighting-lab.png`.

## Scout normal map experiment

`assets/units/scout_normal2.png` is now sampled by Atmospheric sprite lighting in gameplay, editor, replay, and the lab. Scout frames retain matching normal regions across all animations and faction recolorings. Both live sprites and army batches update the map with the animation; other ranks, wildlife and birds keep their previous shading. Simple lighting remains unlit.

In the lab, enable **Light pixel characters**, click **Inspect scout**, and compare **Scout normal strength** at 0 (previous curved shading), 0.65 (current default), and 1 (full supplied normals). Use **Invert scout normal Y** if vertical details appear recessed under a light above them. The original normal PNG is preserved. Lab strength and Y settings save with experiments; gameplay currently uses 0.65 without Y inversion.

`tools/scout_normal_probe.gd` verifies all scout animation regions, texture assignment and unaffected other ranks. With a native renderer it captures `artifacts/scout-normal-off.png` and `artifacts/scout-normal-on.png`, checks visible map-pixel differences and unchanged army uploads. Forward+ verification: 61 checks passed; existing sprite-lighting suite: 31 checks passed.

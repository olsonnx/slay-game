# Building preview stalls and brighter atmospheric lighting

Valid building previews previously constructed fresh meshes and duplicated every transparent material on each hover. Native Forward+ first-use rendering also compiled new transparent surface variants during interaction. The focused probe reproduced roughly 1.35-second tower/house first-preview frames and a 361 ms bridge frame.

The board now prepares and retains one ghost per building kind during loading, with shared retained preview materials. Cached surfaces use zero visibility layers so Forward+ can prepare them without displaying them. Hover reparents the retained ghost and restores its layers; cancellation and invalid destinations return it to storage. Runtime layer changes use the existing Forward+ light-pairing workaround. Window/contact materials remain registered for lighting-style changes. The cache holds exactly three building ghosts per board and dies with that board.

In the matching native probe, first-preview frames were 2.8 ms for the tower, 3.2 ms for the house and 2.3 ms for the bridge. No additional surface pipelines were compiled during hovering. CPU hover construction fell to approximately 0.4–0.6 ms. These are individual focused captures rather than a universal performance guarantee. Raw data and screenshots are `artifacts/building-preview-before.*` and `artifacts/building-preview-after.*`; reproduce with `tools/building_preview_probe.gd -- --label=recheck`.

Atmospheric ambient energy increases from 0.26 to 0.32, ambient occlusion intensity decreases from 0.55 to 0.46, and colour grading gently lifts low/mid tones. Sun energy and the brightest grading endpoint are unchanged. Simple mode retains its original lighting values. The matching screenshots were visually checked.

Checks passed: input/preview behavior and retained object/material identity 51, movement indicators 364, lighting 30. Input/preview and lighting checks also pass natively in Forward+.

# Low-spec rendering review and kingdom-edge correction

## What is currently culled

Opaque procedural materials use back-face culling. Bottom faces normally do not shade screen pixels when viewed from above, but their vertices still exist, and back faces can participate in the menu's reverse-cull shadow pass. The current closed cylinder geometry also includes earth top faces covered by the coloured cap, buried cap bottoms, and internal walls between neighbouring tiles.

Frustum culling works at the spatial MultiMesh batch bounds. Individual offscreen tiles within a visible batch are not independently culled. Hidden overscan and source-render duplicates are already suppressed; that is separate from removing invisible faces. Shadow passes also have their own visibility requirements. Ordinary software occlusion culling is unlikely to help much on this largely open, overhead island and can add CPU work.

## Experiments

Disposable native tests in `tools/geometry_budget_probe.gd` compared existing terrain cylinders, zero intermediate height rings, omitted cylinder bottoms and disabled cap casting. In the sampled RTX 2060 menu trace, baseline was ~248 FPS, zero rings ~246, omitted bottoms ~239 and disabled cap casting ~218. The moving/generated scene changes between samples, so those are directional observations rather than reliable comparative percentages. Fewer triangles did **not** produce a clear FPS gain on this CPU-bound PC. These are not measurements on an integrated GPU.

The safe geometry simplification is applied in shared `BoardAssets.cylinder_mesh`: `rings = 0`. Cylinder/cone side surfaces are straight, so the extra intermediate height ring was redundant. A closed six-sided cylinder drops from 36 to 24 triangles while retaining its height, radius, silhouette and material. Shared menu/game assets remain consistent. Bottom removal and shadow changes were not made defaults.

## Recommended next rendering architecture

1. **Merged terrain chunks with exposed cliff walls.** Build actual raised 3D terrain into one vertex-coloured mesh per spatial chunk: top surfaces, visible soil rims and exposed walls. Omit buried tops, cap bottoms and walls between equal-height solid neighbours. Keep colour variation in vertex data. Update dirty chunks on terrain/ownership changes. Temporarily detach a full tile mesh for menu edge animation and reconstruct exposed walls/rims behind it. This preserves the current diorama rather than substituting a flat map, and is the most promising next step for reducing both draw submissions and redundant geometry.
2. **Separate, cheaper shadow geometry.** Closed simplified terrain/prop proxies can preserve correct shadows even if the visible mesh omits bottoms. Disable insignificant grass/pebble casting at distance, and simplify trees/buildings in the shadow pass. Quality presets should control shadow resolution/filtering consistently in gameplay/menu. Verify silhouettes, water, bridge holes and low camera angles before making it default.
3. **Screen-size LOD for small props.** Tiny grass/pebbles contribute little when subpixel. Use a distance/screen-size threshold with hysteresis or a fade; distant trees can use simplified cones or camera-facing impostors in a low-quality preset. Keep full models close up. Whole-island impostors/2D layers are cheaper but trade away flexible camera orbit and raised-land parallax, so they should be an optional low-end mode rather than the default.
4. **GPU-focused quality settings.** A menu-specific 3D render scale, 2× MSAA and cheaper shadows could help integrated GPUs while retaining native-resolution UI. Today's high FPS on RTX 2060 does not prove performance on low-end hardware. Test frame-time tails and scene generation on representative lower-spec hardware; retain a minimum quality target rather than choosing options solely from high-end average FPS.

Avoid GPU compute-driven culling or a renderer migration as the first step: the project uses Compatibility for broad hardware support, and the simpler chunk/LOD/shadow architecture addresses the measured workload with less risk.

## Reported jitter during kingdom-tile departure

The user clarified that a coloured kingdom tile leaving the menu island causes border instability on the tiles behind it. A concrete topology issue was found: their cap meshes retained joined-edge masks from the logical landscape even after the neighbouring tile entered departure.

The menu has a tested **opt-in diagnostic prototype** keeping both logical and visible join masks. Visible joins require both tiles to be settled and present. A departing tile gets an outer rim; newly exposed neighbours regain their outer rim. Returning settled neighbours restore shared edges. Only changed tiles and their six neighbours need checking, and cached cap records update without rescanning unrelated props. Live border preferences and streamed generation continue to use the shared terrain helper. This prototype is **off by default**: it added streaming work and did not conclusively isolate the reported flicker, so the established menu path is retained pending a clip of the exact artifact.

Regression checks confirm prototype exposed-rim restoration, rejoining and 232.5 simulated seconds of scrolling/recycling. Native Water/Sky previews were inspected. Generic per-pixel edge metrics did not establish that the reported jitter is gone: moving subpixel edges and shadows change those metrics naturally. Disabling cap casting, removing covered earth tops or changing the near plane did not isolate the specific artifact in the sampled trace. The reported visual bug remains unconfirmed/unresolved; a short clip is needed rather than claiming a shadow/depth fix.

All 23 affected suites from animation onward passed with shared geometry simplification and the visible-edge logic, including menu rendering **55,002**, static batching **1,311**, heatmap **38**, presentation **5,080** and menu-background ~**4,296** checks (random fixture counts vary). Final incremental-join/cache reruns also passed. No AI/general rules-only rerun was needed for this rendering revision.

References: [Godot spatial culling modes](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html), [MultiMesh batch-culling limits](https://docs.godotengine.org/en/4.6/tutorials/performance/using_multimesh.html), [occlusion-culling tradeoffs](https://docs.godotengine.org/en/4.6/tutorials/3d/occlusion_culling.html).

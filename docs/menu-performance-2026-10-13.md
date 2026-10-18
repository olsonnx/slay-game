# Main-menu streaming optimization — 13 October 2026

**17 October scenery update:** complete generated islands now occupy bands based
on their actual height, separated by short water gaps. The neutral filler belt
has been removed. Compact orientations and bounded seed retries keep new kingdom
groups arriving before earlier ones leave, preserving full coastlines and varied
terrain. The existing fixed tile pool, cached shared geometry and border-only
animations remain in use. Four affected regression suites pass, including 150
simulated seconds of recycling, bounded caches and repeated multi-group views.
Native captures: `artifacts/menu-stream-*.png`. Measurements below predate this
scenery change.

The main menu now batches settled scenery across rows and avoids renderer updates for hidden sources. Scrolling, camera motion, independent tile arrival/departure, water, lighting, shadows, MSAA and the full-rate background are retained. No lower-detail mode or artificial frame-rate cap was introduced.

## Findings

Native RTX 2060, windowed 1280×820, unlocked FPS and saved 8× MSAA reproduced approximately **149–152 FPS** before this revision. Freezing scenery updates raised it to about **350 FPS** with the earlier row batches. Disabling shadows only reached ~169 FPS, lowering resolution ~151, hiding water ~144 and hiding the vignette ~149. The main viewport's render CPU/GPU times were small; streaming/transform work and duplicated row draw groups dominated.

The previous batching suppressed source render layers but still allowed thousands of MeshInstance3D transform notifications as their row parents moved. Hidden overscan and water slots also incurred movement/notification work. Separate batches for every row kept many duplicate render submissions. An early cross-row prototype exposed another issue: exact transform comparisons chased tiny floating-point differences, and rescanning the entire scenery on each membership change caused stalls. These were fixed before delivery.

## Current implementation

- `DecorativeMap` owns one shared spatial `StaticBatches` manager for settled scenery, rather than a manager per row. The batch root scrolls by a common translation; entering/leaving tiles use their original source animation path.
- Menu-only source caching retains immutable part records for each tile. Tile recycling invalidates its part cache; live internal-border preference changes clear/rebuild it. Incremental membership changes reuse unchanged records and rebuild affected chunks. Source signatures compare transforms with a floating-point tolerance.
- Only land crossing into/out of the settled state changes batch membership. Water slots do not run invisible arrival/departure animation. Hidden far overscan rows skip transform propagation until needed.
- Suppressed opaque sources disable renderer transform notifications, while their logical transforms remain valid. Sources restore their original notification setting and current renderer transform before reappearing. Hidden tiles park notifications for all mesh parts and wake before visible entry/recycling. Scene disposal checks tree membership before reading global transforms.
- Scroll coordinates are bounded: the batch origin periodically rebases after 120 row advances. A long-scroll test crosses this boundary and verifies rendered-instance positions against logical source transforms. This avoids accumulating large coordinates over long menu sessions.
- `StaticBatches`' incremental/cached paths are opt-in; ordinary gameplay retains full visible-change source validation. Units, wards, filter restoration and island transitions keep their existing semantics.

The fixed pool remains 41×17 slots. Source asset generation and border geometry remain shared with gameplay. The decorative viewport still stops when gameplay starts and renders at the application's full frame rate while active.

## Evidence and verification

Final normal-streaming native samples (three five-second windows) measured **307.7 / 326.7 / 313.8 FPS**, versus the earlier ~150 FPS. Median wall frames were **2.85–2.95 ms** rather than **6.4–6.5 ms**, and p99 was **7.88–8.56 ms** rather than the earlier approximately **9.6–10.0 ms**. Renderer CPU dropped from ~2.4 to **1.15–1.21 ms**. Final measurements are in `artifacts/menu_final_performance.json`. Scrolling scene composition varies with randomly generated terrain, so figures are sample measurements, not a promised constant frame rate. Profiling was disabled in final samples; debug scan/update fields from earlier profiling are not used as current timings.

`test_menu_rendering.gd` passed **54,998 checks** with a fixed seed: 232.5 simulated seconds of scrolling/recycling, batch-instance/source position equality, notification suppression, animation handoffs, fixed pool size, bounded-origin rebasing, retained chunks and live border preferences. Existing menu-background tests cover another 150 simulated seconds, shared geometry, depth safety, recycling, independence of falling tiles, background choices and inactive viewport behavior. Gameplay batching/filter/interaction suites are rerun because the helper is shared.

Native evolving Water menu scenery was visually inspected. The menu's island silhouettes, raised tiles, props, lighting and independently falling edges are preserved.

All **23 affected suites from animation onward passed**, including menu background **4,322**, new long-scroll rendering **54,998**, static batching **1,311**, menus **46**, presentation **5,080**, heatmap **38** and performance **284** checks. AI/general rules-only suites were not repeated for this menu/rendering change. The runner contains **25 suites**. Final editor import scan was clean.

Tools: `tools/menu_performance_probe.gd` performs update/render ablations, and `-- --final` samples normal streaming in three five-second windows. It never saves settings. `tools/menu_batch_probe.gd` compares source drawing with the current shared batches. Both require a native graphics window; headless timing is not an FPS measurement. Raw data is written under `artifacts/`.

Remaining profiling targets are rare tile-generation/origin-rebase work and streaming tails. The current menu is still a full-rate, live 3D scene; no rendering features were removed to achieve the gain.

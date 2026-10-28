# AI performance implementation — 28 October 2026

Implemented the performance and scheduling changes identified in the [AI review](ai-review-2026-10-28.md). Existing planner selection, scoring, difficulty budgets and within-turn objective lifetime are retained. This pass does not introduce a new difficulty policy or cross-round strategic state. Version remains 0.2.0; no export or ZIP rebuild.

## Changes

- Preparation keeps a narrow, faction-phase cache of enemy army threats, weighted movement reach and adjacency. Each purchase still creates fresh immutable Queries for economy, defense, wildlife, projected capital breaches and recruitment opportunities. Recruitment, towers, cities, development and entrenchment on ordinary friendly land preserve only the reusable facts. Roads, bridge changes/occupation, spells and unknown action types discard them. The phase cache is never shared across factions or turns.
- Enemy threat generation builds a conservative multi-source distance field through every existing cell, including impassable terrain. Enemies beyond even their best possible road-assisted attack range are rejected before weighted route finding. Actual reachable threats, strengths and source order are preserved.
- Integer bucket frontiers replace repeated minimum scans and membership searches in movement and infrastructure travel. Decrease-key preserves first-discovery order, including equal-cost parents; road costs and paths retain their original semantics.
- Tower price/affordability is computed once per candidate pass/bank. A full tower legality check runs only for useful cover candidates. Unaffordable bridges are rejected before enumerating construction sites.
- Strategic movement shares base objective values, geometric frontier distances and merge-enabling defense ranks within an immutable plan. The shortlist retains exactly enough sorted options to reproduce the existing tactical candidate budget after skipping reserved targets and the departure tile. No extra heuristic pruning was introduced.
- The next movement transaction starts privately while preparation or the current movement batch animates. Authoritative state, presentation patches and replay rows publish only after the playback boundary. Pause delays publication; closing cancels and acknowledges the pool task. Non-worker execution retains its existing serial behavior. Different factions are not simulated concurrently.
- Profiling emits one purchase/movement planning sample per invocation, rather than treating every annotated order as another complete search. The existing input/worker/publish timings remain available.
- `tools/ai_performance_probe.gd` now follows the active backend by default, reports the actual algorithm/unit count and measures worker preparation. Explicit `--algorithm=legacy` and `--algorithm=strategic` remain available for diagnostics.

## Paired baseline comparison

The original game scripts were captured under ignored `artifacts/ai_baseline/` before edits. Baseline and optimized rules were restored from the same deterministic fixture and run consecutively. Three samples for each case, seed 71, synthetic developed territory with 300 gold per bank. Times are headless elapsed milliseconds on this machine; sample counts are small and timing variation is substantial. They are not release-build guarantees or full round timings.

| Display size / difficulty | Troops on map | Preparation before → after | Preparation speedup | One movement plan before → after |
| --- | ---: | ---: | ---: | ---: |
| Tiny / Easy | 30 | 83 → 74 ms | 1.1× | 95 → 43 ms |
| Standard / Normal | 60 | 713 → 365 ms | 2.0× | 79 → 49 ms |
| Standard / Hard | 60 | 1,183 → 466 ms | 2.5× | 82 → 49 ms |
| Huge / Normal | 120 | 4,397 → 1,865 ms | 2.4× | 332 → 230 ms |

Each row reports the median of its three measurements. Every one of the 12 comparisons retained the same ordered purchase decisions, preparation animation records, authoritative preparation state (including treasury/mana/encounters/RNG), movement sequence and movement score. These checks establish equivalence on the sampled positions, not universal correctness. Planning/playback overlap was tested separately and is not included as an additional speedup in this table.

Raw data and diagnostic comparison script: `artifacts/ai-optimization-comparison.json`, `artifacts/ai_optimization_compare.gd`, `artifacts/ai-optimization-comparison-final.log`.

Example ongoing benchmark:

```text
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script tools/ai_performance_probe.gd -- --label=local --samples=3
```

Use an absolute `--log-file` path when supplying one on Windows. The benchmark writes ignored artifacts and does not export the game.

## Verification and existing failures

The new optimization suite passes 374 checks: reference route distances/parents/order on randomized roads, obstacles and occupied bridges; threat equivalence without the distance rejection; cached versus fresh purchases for all difficulties; animal-defense refresh; projected capital breaches after recruitment; conservative invalidation; and bounded versus full-sort strategic assignment.

The simulation-worker suite passes 1,114 checks, including private completed prefetch, ordered replay equivalence, scoped presentation reconstruction, cancellation/draining, pause/resume and the serial fallback. Strategic AI passes 878, logistics 373, core AI 107, animation 47, replay 131, architecture 78, playback speed 33 and hotseat 40 checks.

Existing suites report the same failures on the captured pre-change implementation and the optimized implementation:

| Suite | Failing checks on both |
| --- | ---: |
| `test_ai_tactics` | 5 |
| `test_ai_followup` | 7 |
| `test_ai_bridge_campaign` | 4 |
| `test_ai_housing` | 1 |
| `test_turn_feedback` | 3 |
| `test_entrench` | 31, plus the same missing `landing` fixture error |
| `test_wildlife` | 3 |

These are existing policy/fixture expectations, including old recruitment and replay positions; they were not weakened or marked skipped. Their cause is not fully resolved by this performance pass. Baseline logs are `artifacts/<suite>_baseline.log`; optimized logs are `artifacts/<suite>_optimization.log`.

The broader `test_game` run also reached 12 existing recruitment, movement and house-building expectation failures. Its five-game, 200-turn stress section was stopped; a bounded copy of the preceding checks reproduced the same 12 failures against the captured baseline (42,207 checks passed). This is not a completed full-suite run. Log: `artifacts/test_game_prefix_baseline.log`.

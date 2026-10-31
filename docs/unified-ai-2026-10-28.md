# One enemy AI for every map size — 28 October 2026

New games explicitly select the strategic AI. Its assignment planner now handles Tiny, Small, Standard, Large and Huge maps, along with editor maps and the retired Very Small profile. The old 200-cell switching threshold has been removed. Older configurations containing `auto` select the same strategic policy.

Easy, Normal and Hard retain their existing purchase limits (4/8/12), tactical alternatives per unit (16/40/64), variation and risk handling. Normal and Hard evaluate local retaliation, with Hard applying a larger penalty to unsafe captures. The change unifies gameplay behavior across map sizes; it does not promise a universal difficulty ranking or identical decisions to the previous small-map beam search.

The legacy beam planner remains available only through an explicit internal `legacy` override for diagnostics and reference tests. No player-facing selector exposes it. Keeping that implementation avoids rewriting older tactical fixtures or losing the ability to compare policies. Recorded replay playback applies stored commands/deltas and does not rerun AI planning, so existing recordings retain their recorded decisions. Snapshot/network configuration still accepts the historical algorithm strings.

## Verification

- `test_unified_ai`: 229 checks passed across all five current map sizes and all three difficulties. Checks exercise both new defaults and older `auto` metadata, worker/serial plan equivalence, immutable search/RNG, legal assignments, unique destinations, bounded tactical budgets and complete faction turns through the live simulation worker.
- `test_strategic_ai`: 879 checks passed, including deterministic planning, capital protection, unsupported-capture rejection, hidden encounters, legal movement, pause/cancellation, and both sides of the former size threshold.
- `test_ai`: 107 checks passed. The worker comparison now uses the gameplay strategic planner; explicit beam-search tactical reference checks remain intact.
- `test_simulation_worker`: 1,114 passed; `test_ai_optimization`: 374 passed; `test_replay`: 131 passed. These retain worker ownership, ordered replay, playback-boundary publication and cache/pathfinding guarantees.
- Branch smoke checks: logistics 373, logistics tutorial 87, settings 22, music 21, video display 13 and results 75 passed. Settings/file tests run with writable, isolated `APPDATA` under ignored artifacts.

At rollout, the broader pre-existing failures listed in the [performance implementation report](ai-performance-2026-10-28.md) remained unresolved. They were subsequently addressed in the [30 October test reconciliation](playtest/test-reconciliation-2026-10-30.md). Existing difficulty policies still benefit from human playtesting, especially on small maps where the default backend has changed.

Version remains 0.2.0. No executable, export or ZIP was rebuilt for this rollout.

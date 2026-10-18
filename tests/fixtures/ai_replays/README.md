# AI replay regression positions

These are required, versioned inputs for `test_ai_tactics.gd` and
`test_ai_followup.gd` and `test_ai_bridge_campaign.gd`. Missing files fail their suites instead of silently
reducing coverage. They are excluded from release exports with the other tests.

- `position-small-127.json` and `position-small-174.json`: preserve useful
  Soldier recruitment in the original small-map replay positions.
- `position-large-371.json` and `position-large-409.json`: preserve useful
  Soldier candidates in the original large-map replay positions.
- `followup-557.json`: Tide's round-six preparation against a visible Knight.
- `ember-bridge-preparation.json`: Ember's round-six purchase position.
- `ember-short-turn.json`: its round-six movement position after the original
  overspending, preserving the safe capture that Hard previously discarded.
- `ember-bridge-demolition.json`: round-eleven offensive bridge preservation.
- `ember-before-turn.json`: before round-six settlement, for authoritative full
  turns and exact replay reconstruction with both planners.

Copied without changing their recorded state from the local diagnostic outputs
`artifacts/player-replay-analysis/` and `artifacts/ai-followup-positions/557.json`.
The tests no longer depend on those generated directories.

The Ember snapshots preserve generation-v8 cells and RNG from the 16 October
Medium/Hard recording (seed 3706201514). Their source diagnostics are in
`artifacts/ember-bridge-analysis/`; the suite only needs these versioned fixtures.

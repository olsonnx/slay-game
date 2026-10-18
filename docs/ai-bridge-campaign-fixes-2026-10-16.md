# Ember replay: recruitment, short plans and bridges

The Medium/Hard replay `2026-10-16T21-27-57-3706201514-1231310471.jsonl`
showed Ember repeatedly buying Scouts without moving, building its useful bridge
late, then destroying it. The failure involved shared purchase policy as well as
the legacy Hard movement search.

## Changes

- Hard retains a separate, bounded shortlist of useful stopping positions from
  every movement depth. It compares those prefixes, the final beam and holding
  against the same sampled replies. A profitable single capture can survive
  even when appending merges makes a five-action plan worse. Movement depth,
  beam width and candidate budgets stay unchanged; reply positions increase from
  at most `width + 1` to at most `2 * width + 1` (seven on Hard).
- Shared recruitment matches ready units to distinct reachable frontier jobs,
  hardest defenses first, before crediting another purchase. Necessary capital
  guards are reserved. Stronger breach units, defensive purchases and a combat
  reserve against a visible rival still receive value. Summon also requires a
  useful expansion or defensive role.
- Bridges gain a bounded campaign premium when they open new shore, existing
  frontier jobs are covered, and an available or affordable force can hold a
  landing against visible retaliation. This is an analytical estimate using
  current finances and terrain, without extra simulated purchase branches.
  Existing affordability and wage guards remain in force.
- Shatter weighs actual threat reduction against losing usable frontier access,
  friendly land connections and a friendly bridge garrison. Surviving alternative
  routes receive no imaginary defensive benefit. Emergency cuts can still save
  a capital.
- The legacy movement shortlist represents distinct destinations and ranks before
  adding interchangeable departures. A second source for the same job remains
  possible within the existing budget, since leaving different guards can have
  different consequences.

## Recorded-position verification

Four required snapshots from the original replay are stored under
`tests/fixtures/ai_replays/ember-*.json`; generation v8 geometry is preserved,
so the tests do not depend on regenerating an older seed with today's generator.
The full-turn snapshot precedes settlement, avoiding double income/upkeep.
Planning uses masked encounters; authoritative full-turn execution restores the
recorded cells and RNG and validates exact replay reconstruction.

From Ember's original start of round six, both backends now build and use the
crossing at `(5,8)`, upgrade a Scout to Soldier for 10 G, and attack enemy land.
Neither buys another Scout. Both also build another useful crossing at `(7,1)`;
the backends choose different campaigns afterward. In the final diagnostic run,
legacy finished with 2 G and +55 net income; strategic finished with 1 G and +47.
The legacy full turn took about 5.46 seconds; strategic took about 214 ms on this
host. These are synchronous whole-turn observations, not frame-time guarantees.
Live play retains private worker searches and cancellation.

The isolated movement fixture also accepts the safe `(8,4)` capture as a
one-action plan. The recorded round-eleven position rejects destroying its
useful offensive bridge. Synthetic cases retain emergency demolition and reject
false threat relief when an alternative crossing remains.

Ten focused Godot suites pass, totaling 6,518 checks: bridge campaign (26), army
optimization (2,041), AI tactics (44), AI follow-up (23), housing (10), AI (186),
strategic AI (2,477), performance correctness (422), capture updates (1,171),
and replay (118). The army optimization comparison now permits intentional
destination diversity only where the historical shortlist repeated jobs, while
checking legality, priority ordering and source/job repetition limits.
The registered test runner also passes the new suite and all 14 Python replay
reader tests.

The reproduced offensive turn demonstrates that the specific inactivity is
fixed. It does not establish a forced win against the player's possible replies
or an overall AI strength rating. Campaign valuation remains heuristic, and
legacy Hard's extra reply positions can increase thinking time.

Diagnostic action trace: `artifacts/ember-fixed-turn-final.log`.

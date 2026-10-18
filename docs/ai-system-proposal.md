# Enemy AI proposal — 12 October 2026

Status: approved for implementation; an initial shared planner and all three difficulty levels are implemented. See `ai-system.md` for the actual budgets, verification and remaining forecasting/tuning limits. This document preserves the original design direction.

## Direction

Replace the shuffled spending checklist and isolated move scores with one shared planner. Easy, Normal and Hard use the same rules and resources; their differences come from evaluation detail, coordination and planning budget. Normal is the default.

The aim is readable opposition: kingdoms expand where they can support expansion, defend important positions, assemble the strength needed for an attack and invest when they can afford the delay. Difficulty should change how well they do these things, rather than making every enemy aggressively target the player.

## A turn has a purpose

At the start of each faction turn, build a summary of every kingdom: income, wages, reserves, ready troops, reachable enemy attacks, vulnerable structures, expansion opportunities and useful connections to other friendly kingdoms. Assign a current posture: recover, defend, expand or attack. Reassess after captures, deaths and changes in connectivity; posture is guidance rather than an order to ignore better opportunities.

Threats must use legal routes through the enemy's connected land and bridges, not just neighboring units. Distinguish enemies that can act later in this round from those that act after our next turn. Longer-term forecasts may include affordable recruitment, merging and spells, with uncertainty. An exhausted enemy is not an immediate attacker, but becomes a threat when its turn resets it.

Multiple enemy factions remain independent rivals. A valuable player target can attract attacks, but there is no shared knowledge of planned actions, alliance between opponents or special bonus for attacking faction 0.

## Evaluate the resulting position

For each candidate action, compare its consequences with holding position. Use a shared position evaluation so purchases, spells and movements can be compared on the same basis:

- Survival: protect a kingdom's capital, treasury and viable routes. Score actual elimination and victory separately from capture of a capital that can be replaced.
- Economy: consider net income, expected wages, retained reserves, tree clearing and investment payback. Discount income on provinces likely to be lost.
- Military usefulness: reward troops that can defend or perform a useful attack. Stronger units are not automatically better; merging loses one unit's coverage and action.
- Territory: value income, sources, defensive coverage, route access and capital annexation. Cutting a kingdom can be worth more than claiming an isolated high-value tile.
- Risk: penalize exposed attackers, lost defensive coverage, unfavorable Knight sacrifices and costly attacks absorbed by Fortify.
- Mobility: favor bridges and positions that open useful routes, repair disconnected holdings or deny valuable access.

Use a limited uncertainty margin rather than claiming exact predictions. Do not count the same benefit repeatedly as income, territory value and acquisition reward. Tune weights through tactical fixtures and matches, not only arithmetic.

## Purchases and investment

Generate competing candidates: recruit a Scout/Soldier/Knight, upgrade, merge later, build a tower or house, develop, build a bridge, cast a spell or save funds. Rank useful candidates and simulate their economic and tactical effects before committing.

For army additions, use the actual wage difference. Summon costs mana but still adds Scout wages; merging two Scouts into a Soldier also increases net wages in Modern. Forecast the next income tick and keep a reserve appropriate to exposure. Normal should reject routine purchases that lead to foreseeable bankruptcy; Hard may accept a temporary deficit when existing reserves cover it or a convincing tactical payoff outweighs it. Easy still avoids obvious unaffordable commitments.

Choose troop strength for a job: capture neutral land efficiently, break a defended border or hold a threatened capital. Choose towers for their coverage, not merely adjacency to any Soldier. Prefer safe, useful investments and compare cheap development with houses; replace the current fixed 30/40-gold triggers. Saving is a valid choice.

Mana is shared across the faction, so rank spell opportunities across all its kingdoms before spending it. A low-value Summon should not consume mana needed to save a capital elsewhere.

## Troop coordination

Plan across units instead of committing them in random order. Candidate sequences include clearing a ward then attacking, merging then attacking, moving a replacement defender before releasing the current one, and using a Knight duel to create a useful follow-up attack. Recalculate after each committed action and after encounters resolve.

Holding position must be an explicit candidate. Limit candidate destinations using strategic features and keep diverse alternatives; this avoids exploring hundreds of equivalent friendly repositioning moves. Every committed action still goes through existing public rule validation.

Initially retain the current purchase/spell preparation phase followed by movement. Preparation must evaluate how purchases enable planned movement; it must not pretend it can purchase after a capture in that same turn. Spending event rewards or casting spells between movement batches would require a separate turn-flow change and should be considered later, not silently assumed by the planner.

## Spells and encounters

All difficulties can use all available spells, with increasing quality of timing:

- Summon: expansion, defence or a useful merge, subject to wages.
- Fortify: protect a genuinely threatened structure or bridge garrison.
- Shatter: remove a hostile bridge garrison, sever useful enemy connectivity or consume a ward as part of a worthwhile sequence; account for friendly losses and routes.
- Trailblaze: buy an extra useful action when neutral land can be captured first.
- Grove: reduce valuable enemy income or change source capacity when the benefit exceeds the cost and the opponent's clearing reward.
- Barrier: delay a credible attack or channel movement without trapping friendly units; conserve each tile's one-use opportunity.

Event markers are unknown encounters to the AI, as they are to the player. Do not inspect their hidden event IDs when choosing movement. Once revealed, choose using the displayed probabilities and consequences: risking a disposable Scout may be worthwhile while risking the only capital defender is not. Planning must not read future random rolls or select a move because a cloned random generator reveals a favorable outcome.

## Difficulty levels

| Aspect | Easy | Normal — default | Hard |
| --- | --- | --- | --- |
| Tactical assessment | Basic threats, useful captures and economy safety | Resulting defence, exposure, splitting and useful trades | Normal plus plausible replies and recovery options |
| Coordination | One useful action at a time; obvious merges | Short sequences of 2–3 actions | Broader sequences of up to 4–6 actions |
| Opponent forecast | Obvious direct danger | Lightweight forecast of the strongest threats | Bounded response simulation through the next relevant turn cycle |
| Investment | Simple safe purchases | Compare investment, recruitment and reserves | Compare delayed returns with forecast pressure |
| Choice variation | Occasionally pick a slightly weaker reasonable action | Small seeded tie-breaking variation | Usually strongest evaluated choice; variation only among close alternatives |
| Resources/rules | Standard | Standard | Standard |

These depths are initial limits to tune, not promises of exhaustive search. Even Hard must choose quickly on Large maps. Easy should feel forgiving, not broken: do not manufacture bankruptcy, illegal moves or pointless suicides to reduce its strength. Gate its simpler choices through basic safety checks.

## Implementation and responsiveness

Keep `kingdom_rules.gd` authoritative and existing playback action records intact. Split AI responsibilities into profiles, board analysis, candidate generation, position evaluation and a planner, with `kingdom_ai.gd` remaining the integration point. Separate policy randomness from gameplay randomness so additional search work cannot alter tree spread or encounter outcomes.

Use lightweight independent state snapshots for search. Simulated branches must never mutate live cells, treasuries, effects, event queues or random state. Resolve uncertain encounters by probabilities/expected risk, not by peeking at the live random stream. Start with cached route and threat summaries; invalidate them after relevant board changes.

Bound work by candidate/expansion counts for reproducibility and process it in small resumable batches. Yield between batches so the turn spinner, Pause and rendering remain responsive; stopping or leaving a game must cancel pending planning. Hard can search more while all difficulties share this mechanism. Measure worst-case Large turns before selecting final budgets; retain a best validated plan if the budget ends.

Add concise diagnostic reasons to development logs, such as “protect capital,” “capture source,” “merge to break tower” or “save wages.” Keep these out of the normal game UI unless an optional debug view is requested.

## Difficulty selection

Add Easy / Normal / Hard to New Game, beside map size, with Normal initially selected. Remember the last selection as the preference for future games. Existing settings files lacking the field default to Normal.

Store the chosen difficulty in the match independently of the saved preference. Restart preserves the seed, rules, size and difficulty. A rules change preserves match difficulty when generating the replacement island. All opponents use the selected profile; mid-match changes and mixed difficulty opponents are outside the initial scope.

## Delivery and validation

1. Build the shared analysis/evaluation foundation and Normal planner. Fix holding, threat reach, wage accounting and capital defence first. Cover purchases that enable movement and coordinated merges/attacks.
2. Add the six-spell policies and event decision evaluation. Preserve current turn phases and animation behavior.
3. Add Easy/Hard profiles and the New Game selector. Add deeper bounded response search for Hard after measuring the shared planner.
4. Tune with tactical fixtures, matched tournament simulations and human playthroughs. Adjust scores and budgets based on observed reasons for mistakes.

Regression fixtures should test remote reachable threats, leaving a capital defended, affordable upgrades, useful versus harmful merges, Knight trades, ward-breaking sequences, shared mana allocation, one-use barriers, bridge splitting and holding instead of a bad move. Include a fixture where losing a capital creates a replacement rather than eliminating the faction. Test private simulation state, deterministic decisions, search cancellation and difficulty persistence/restart.

Run tournaments across Classic/Modern and all map sizes using the new generator. Rotate policy assignments through every starting location on each seed, and compare matched results to the old AI. Record survival, capital losses, bankruptcy, net income, capture efficiency, unresolved matches and planning time. Do not treat stock-AI self-play or one fixed player slot as a human difficulty rating. Hard should outperform Normal, and Normal Easy over broad samples, but cannot be expected to win every uneven map. Human testing should confirm that plans are understandable, Easy is forgiving, Normal requires decisions and Hard punishes mistakes without unfair advantages.

## Recommended agreement

Adopt this shared planner with Normal as default and equal resources at all difficulties. Build competent Normal behavior before tuning Easy or adding Hard's deeper search. Leave personalities, diplomacy, adaptive difficulty, economic handicaps and purchases between movement batches for separate future decisions.

# Guided tutorial matches

To author your own scenarios, launch **Tutorial Editor.cmd**. The [tutorial editor guide](tutorial-editor.md) covers custom map import, text, action/board conditions, enemy orders, playtesting and replacing a category without code edits.

Choose **Tutorial** from the main menu, then pick **Basics**, **Intermediate**, or **Advanced**. All categories are available immediately. Each is a separate, continuous scenario with a green player and one opponent. Each ends by taking the enemy capital and defeating the opponent; no board resets occur between objectives.

| Category | Scenario | Objectives |
| --- | --- | --- |
| Basics | Spend the normal 10 G starting treasury on a Scout, expand, collect income, upgrade to meet an advancing enemy, and capture its capital. | 8 |
| Intermediate | Invest in a House, stop a border raid with a Tower, fund a Knight, and counterattack the enemy's fortifications. | 12 |
| Advanced | Build a crossing, use Trailblaze to keep momentum, break entrenchment, summon reinforcements, and win across the water. | 12 |

## Teaching approach

One short prompt and one immediate task accompany each action. English prompts are at most 24 words. Gold rings mark targets; cyan rings mark source units; the relevant HUD action is highlighted. The compact card leaves most of the board visible at 960 x 620. Camera controls, inspection, the heatmap, and Stats remain optional tools rather than compulsory exercises.

The opponent follows authored decisions through the ordinary move, construction and entrenchment APIs. Both sides pay ordinary costs and settle income/upkeep on their turns. Enemy moves are animated, and construction/entrenchment remain visible briefly before returning control. The scenarios introduce mechanics in context without trying to cover every possible rule. Random tree spread remains disabled so the guided objectives stay reproducible; this is not an unrestricted AI match.

Basics begins with 10 G. Intermediate and Advanced begin in prepared mid-match positions with 20 G and 50 G respectively. Tutorial matches use Modern rules without changing saved gameplay preferences.

## Navigation and recovery

**Retry step** restores the current checkpoint: board, banks, mana, effects, pending events, RNG, turn, active province and view modes. A cancelled move does not advance the objective. Wrong purchases and premature turns cannot consume resources or skip progress. **Pause > Restart** restarts only the selected category.

A victory card offers **Next match** after Basics and Intermediate, or **Main menu**. Advanced offers Main menu. Finishing requires an actual defeated opponent, not a progress counter or a synthetic action report.

## Code and validation

- `src/game/tutorial_lessons.gd`: category metadata, short objectives and opponent orders.
- `src/game/tutorial_scenarios.gd`: authored starting positions.
- `src/game/tutorial.gd`: action gating, checkpoints, opponent turn playback and coach card.
- `src/ui/tutorial_selection.gd`: category selection.
- `src/app/app.gd`: selected-course startup and next-match navigation.

`tests/test_tutorial.gd` completes all three matches using real game commands. It covers selector access, direct Advanced entry, rules isolation, wrong-action gating, optional view tools, pause, cancelled moves, retry, restart, legal movement, Tower defense, Trailblaze, entrenchment, continuous state, real victories and next-course navigation. Add `-- --preview` when running with a graphical renderer to capture the selector, key objectives and each victory at the minimum window size.

The previous implementation is archived in `artifacts/tutorial-before-rework.zip`.

Validation on Godot 4.6.3: tutorial checks 240 passed in both headless and native OpenGL Compatibility runs. Related suites passed: menus (52), UI layout (183), localization (32), architecture (79), startup (5), and presentation (9,886). Native captures were inspected at 960 x 620.

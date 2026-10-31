# Learn by playing

The tutorial offers eight independently accessible topics. Guided chapters use prepared positions and waiting opponents; **Your first match** uses a normal small map and active Easy AI. Only completing a whole topic records its completion. Progress survives restarting the game; editor playtests do not change it.

| Topic | What the player actually does |
| --- | --- |
| Armies and expansion | Capture with a Scout, recruit at a capital, move a fresh recruit, merge two Scouts, upgrade the resulting spent Soldier, end turn, and march the Knight three hexes. |
| Cutting off armies | Inspect a supported enemy Knight, capture its last land connection, and end turn to remove it through isolation. Extra reading pages explain the difference between a single stranded tile and a larger detached kingdom. |
| Kingdoms and money | Read the gold forecast, develop a value-2 province for 8 G, clear a forest for 1 G and restored income, then spend from a separate friendly kingdom's treasury. |
| Defences and upkeep | Build towers for 15 G and 20 G, build two bridge segments for 15 G each, remove an empty sponsored bridge, and read the remaining upkeep. |
| Cities and supply lines | Build and name a forward city, recruit a Knight beside the capital, preview and build an eight-tile road for 8 G, march six road steps, recruit and move at the city, and connect a tower to existing pavement. |
| Mana and spells | Gain mana and Summon a ready Scout; use Trailblaze for two neutral captures in one turn; use Shatter to remove an adjacent neutral bridge. Each spell has a separate prepared exercise. |
| Exploration and rewards | Collect a 15 G treasure chest and distinguish it from recurring income; start a new position, choose either Comet reward, and inspect the result. |
| Your first match | Choose purchases, routes and timing against an active Easy opponent. Remove enemy capitals to win. Retry is available after defeat. |

## Instructions and rules

Blue rings identify the source of a move or road; gold rings identify its destination. Instructions name the normal controls: Recruit, Build, Spells, province details, the inline settlement title, and the road icon. No tutorial-only purchase or movement rules bypass the game.

Scouts, Soldiers and Knights move 5, 4 and 3 hexes. Normal movement or capture spends the action, even when some range remains. Fresh recruits and summoned units can move immediately. Merging preserves the destination unit's spent or ready state; buying an upgrade never refreshes it. Both purchases and upgrades require a capital or city recruitment area, including adjacent owned tiles connected to a treasury.

Cities cost 25 G and provide deployment sites rather than income bonuses. Roads start at a friendly structure and end at another friendly structure or existing pavement. They cost 1 G per newly paved tile, including endpoints. Connected friendly road steps cost half a movement point. Captures and bridge steps still cost a full point. Roads and towers cannot be dismantled.

Tower construction costs rise by 5 G for each tower controlled across the faction; their upkeep remains 2 G each. Bridges have flat 15 G construction and 2 G upkeep per segment, paid by their sponsor. Only Shatter can remove a bridge; it costs 2 mana and gives no construction refund. Neutral crossings can be used by opponents.

Each connected kingdom has a separate treasury. Selecting its land changes the budget used for purchases and the gold forecast. The money exercises demonstrate the exact changes: development adds 1 G income, clearing a value-2 forest restores 2 G income and pays 1 G immediately, and a chest pays 15 G once while its captured tile adds 1 G recurring income. Shared faction mana is taught separately from local gold.

## Reading, checklists and retry

Reading objectives wait for the actual province panel or gold tooltip to open, then require **Continue**. The explanation stays visible until acknowledged. Each exercise keeps its whole checklist, including completed objectives. **Next exercise** pauses before loading another prepared board. Resources are never silently replenished between objectives in the same exercise.

**Retry exercise** restores the starting board, resources, random state and pending interactions. **Pause > Restart** restarts the selected topic. After completing a chapter, the player can choose another topic. Long text and checklists scroll; the coach fits the minimum 960 × 620 window and hides while Stats is open.

## Authoring and verification

The Tutorial Editor supports all eight categories, with portable examples under `tools/tutorial-editor/examples`. Installed `tutorials/<category>.json` files override individual chapters. See [the authoring guide](tutorial-editor.md).

`tests/test_logistics_tutorial.gd` plays every guided objective using real game commands. `tests/test_tutorial.gd` additionally uses the actual shop cards and province buttons, checks reading acknowledgements, exact resource consequences, both Comet choices, menu completion, retry, cancellation, saved progress, and practice AI and victory/defeat handling. Practice terminal-state fixtures check the UI; they do not claim an automated strategy beats the opponent.

With `-- --preview`, native rendering checks mouse hover objectives and the minimum window layout, and saves screenshots under `artifacts/tutorial-new-*.png`. Editor tests validate templates, simulation, imports, saving and real playtests. `tools/export_tutorial_examples.gd` verifies that shipped examples match the live chapters; `-- --update-examples` refreshes them.

# Learn by playing

Tutorial offers seven immediately accessible topics, with 84 checkbox objectives across 23 exercises. Its compact selector shows only titles and read-only completion checkboxes. Finishing a whole topic saves its completion across launches; individual exercises and editor playtests do not mark a topic complete. Every prepared exercise demonstrates a consequence; the final practice uses a normal small match and Easy AI.

| Topic | What the exercises demonstrate |
| --- | --- |
| Armies and expansion | Capture plain neutral land; read finances by hovering gold; recruit and move a second Scout; explicitly end turns to ready armies; upgrade and defeat Scouts, Soldiers and a Tower; merge and survive a real Knight attack with entrenchment; see equal Knights die without capture. |
| Kingdoms and money | Read treasury, income, wages and net forecast in the normal gold tooltip; clear a forest and compare the forecast; spend from separate banks and reconnect them; use a Scout's ordinary neutral capture to pay for an expensive army. |
| Buildings and development | Develop cheap value-1 land; build a House; inspect a Tower's actual coverage; watch a Soldier take a route outside it; cross a Bridge directly onto shore; compare an 8-gold development with a 20-gold House when all land is already value 2. |
| Taking enemy territory | Approach a defended capital, upgrade only when required, and take its neighboring Tower intact through surrender; cut off one Scout; bankrupt a three-Soldier pocket; relocate a capital that is actually threatened, then see the old capital tile attacked. |
| Mana and spells | Learn shared mana, source capacity and regeneration; use Trailblaze for an extra capture, Summon for useful reinforcements and Shatter to remove a public crossing. |
| Exploration and rewards | Collect immediate treasure; choose either encounter reward; discover a stainless steel landmark and read its status effect; watch a Bear emerge and raid a House, kill it, destroy its cave before respawn, and check the lasting income status. |
| Your first match | Choose purchases, routes and timing against an active Easy opponent. Remove enemy capitals to win. Retry is available after defeat. |

## Teaching through normal controls

Gold-hover objectives advance when the normal treasury tooltip opens. They teach where to read the game's finances rather than adding a second green economy readout to the coach. Status objectives likewise wait for the specified real status tooltip. The stainless steel tooltip states the wage reduction and its dependence on controlling the landmark.

Required End turn actions are separate objectives. Buying a rank does not restore a spent action. Newly recruited armies are ready immediately. Bridges can be traversed as part of a direct move onto reachable shore; the tutorial does not instruct a needless bridge stop.

Inspection is used when the panel or coverage overlay provides relevant information: Tower coverage, development cost, a wildlife threat or a neutral structure. It is not used merely to acknowledge an ordinary province or choose a treasury. Selecting a kingdom's land switches its budget.

The deficit position has income 39, wages 40 and no savings. An existing Scout captures ordinary value-1 neutral land to make it sustainable while a Knight guards the border. It does not use an artificial value-4 neutral reward. The lesson explains that armies cannot be dismissed and that purchases need a sustainable local treasury.

The player sees entrenchment absorb an actual stronger attack. The Tower exercise contains a genuine uncovered approach and two enemy moves. Capturing a capital surrenders its adjacent provinces with their Tower intact; directly attacking a Tower with a Knight destroys it. Both forms of capture use normal rules. Protection spreads only over land with the same owner.

Scripted settlement plays real starvation deaths and leaves graves, including all three Soldiers in the separated pocket. Wildlife demonstrations use the normal predator decisions, raids and respawn timing. They run only on the specified End turn objectives so the teaching position stays reproducible.

## Checklists, retry and presentation

Each exercise starts an explicit prepared position and displays its whole checklist. Completed objectives remain checked. Long checklists scroll with the active objective visible; the card and buttons fit the minimum 960 x 620 window. The coach hides while Stats is open. Bird ambience is synchronized before the player's first action, and old action notices are cleared when a new exercise starts.

**Next exercise** pauses between prepared positions so the result can be read. Resources are not granted between objectives. **Retry exercise** restores the complete starting board, resources, RNG, pending events and relocation history. **Pause > Restart** restarts the selected topic. Completion offers **Choose topic** and, where applicable, **Next topic**.

## Authoring and verification

Use **Tutorial Editor.cmd**, the seven templates or the examples under `tools/tutorial-editor/examples`. Override filenames are `armies`, `economy`, `construction`, `conquest`, `magic`, `exploration` and `practice`. See [the authoring guide](tutorial-editor.md).

`tests/test_tutorial.gd` performs the real UI actions and asserts consequences: forecast values, pooled treasuries, same-turn shore landing, absorbed attacks, destroyed and surrendered Towers, mass starvation with death playback, saved capitals, predator raids and actual status bonuses. Both comet choices are exercised. Practice AI and its terminal-state UI are checked separately; this does not claim an automated strategy beats the opponent.

With `-- --preview`, native rendering also checks real mouse hovers and saves screenshots under `artifacts/tutorial-new-*.png`. Editor tests cover portable templates, validation, manual-choice boundaries, authoring, import, autosave and real playtests.

# Wildlife

Modern generated maps contain bear caves, wolf dens and boar burrows on neutral land. Placement keeps at least four hex steps from every starting owned province and eight steps between lairs. Lairs are rare objectives, with map-size budgets rather than a count proportional to every land tile:

| Map size | Maximum lairs |
| --- | --- |
| Tiny | 1 |
| Small | 1 |
| Standard | 2 |
| Large | 3 |
| Huge | 4 |

Maps with insufficient safe space receive fewer. The retired Very Small profile and Classic maps have no wildlife. Across twelve six-kingdom seeds per size, Huge maps fell from 12 lairs to 4, Large from 6–7 to 3, and Standard from 3 to 2. Smaller maps often have too little remote land to place every budgeted lair.

Caves remain fully visible. Animals use the same centered sprite placement, pixel scale and frame crop as infantry, and occupy separate provinces from their lairs.

An animal emerges on a free neutral tile neighboring its lair on the first World turn. Spawning waits if every exit is blocked, and retries on later World turns. Animals never roam onto lair tiles. Each surviving lair supports one animal. Killing it starts a three-World-turn countdown before its replacement emerges beside the lair. Destroying the lair stops replacements permanently; an animal already roaming survives its lair's destruction.

Animals take two consecutive actions per World turn, each an adjacent step or attack. A blocked attack spends one action, so the second can break through entrenchment or fortification in the same World turn. They roam within two hexes of home, notice eligible targets within three hexes, and can pursue within six hexes of home. They stay on land, avoiding mountains, barriers and bridges. Emerging animals wait until the next World turn to move.

All three species trample trees on tiles they enter, including neutral forests. Successful raids on owned forests both clear the tree and neutralize the province. Protected forests survive a blocked raid. Clear spawn exits are preferred; if every otherwise available exit is forested, an emerging animal clears its chosen exit. Tree destruction never pays gold to a player.

Acquiring a target plays the bear's standing display or the wolf's roar before movement; boars receive the same warning marker and a short alert pause. The supplied pixel-art **!** stays above a pursuing animal between turns. The hover tooltip identifies its target. Continuing pursuit does not repeat the display every turn; losing or defeating the target returns the animal to roaming. Ordinary neutral-forest trampling does not trigger aggression. Alert state is saved in snapshots and replays.

| Animal | Targets | Required hunter | Lair reward |
| --- | --- | --- | --- |
| Bear | Units, buildings, provinces | Knight | Permanent +5 gold each faction turn |
| Wolf | Units, provinces | Soldier or Knight | Permanent +1 mana regeneration |
| Boar | Buildings, provinces | Soldier or Knight | 20 gold and 2 mana |

Lairs require the same hunter rank as their animals. Rewards are granted once, on destruction of the lair, rather than killing the animal. Gold rewards enter the hunter's supporting treasury. Permanent income is faction-wide and paid through the existing income-bonus system without multiplying across split kingdoms. Mana rewards and regeneration respect normal storage capacity.

Successful raids turn the attacked province neutral, destroy its building and kill any vulnerable unit. Wolves leave building sites alone, including their occupants. Boars leave occupied unit tiles alone. Normal province defense protects against raids: wolves cannot beat Soldiers, and bears and boars cannot beat Knights. Towers and neighboring defenders therefore help contain wildlife. Entrenchment or fortification absorbs one otherwise successful raid.

Wildlife participates in AI planning, visible turn playback, map snapshots, restart and replay seeking. Animals and lairs block construction and recruitment until cleared. Saved editor maps preserve generated lairs.

The initial reward values match the proposed design. Their long-term balance remains a playtesting question, particularly stacking bear income and wolf regeneration.

## Audit, 19 October 2026

The forest audit corrected tree clearing during neutral wandering, pursuit, owned-province raids, and emergence through a forested exit. Fortified forests remain intact when a raid is blocked. It also corrected the wolf's attack clip to use five nonempty frames, preserved the full standing bear artwork, synchronized animation with playback speed, and stopped World tweens when playback is cancelled. Birds avoid occupied wildlife provinces and scatter from moving animals.

Verification covers the species/rank/target matrix; kingdom splits and treasury preservation; one-time rewards; blocked exits and three-turn respawns; pursuit acquisition, persistence and loss; snapshots and AI copies; replay reconstruction; every animation frame's bounds; actual tree geometry removal; warning visibility; and cancellation during both alerts and movement. Six Standard/Huge maps also ran forty World turns each, including forced replacement cycles and faction settlement, checking terrain, ownership, forest, population and home-tether invariants throughout. Native bear/wolf/boar alert and pursuit previews were inspected.

Clicking a tower shows its actual friendly defensive coverage in gold. Clicking a lair shows the two-hex home range in purple. Clicking an animal shows its three-hex vision in cyan and its current prey in red. Recurring reward status tooltips use Gold per turn / Mana per turn headings and list source names with their signed contributions, grouping repeated sources. Event and lair provenance and amounts are preserved with faction effects in snapshots and replays.

## Editor placement

Under **Build**, Modern maps offer **Bear cave**, **Wolf den**, and **Boar burrow**. Paint them on existing neutral land; they replace decorations while preserving land value. Water, mountains, bridges and owned provinces are excluded. Right drag removes lairs, and the eyedropper selects the corresponding brush. Placement supports undo/redo and save/load. Playtests use a private copy and spawn the animal beside its authored lair on the first World turn.

The editor's unsaved-level confirmation uses the shared panel and button styling, with **Keep editing** as the initial keyboard choice. Escape cancels; Tab stays within the dialog. Discard consumes the pending navigation once.

# Cities and logistics experiment — 0.2.0

This branch experiments with territorial commitment and reinforcement routes.

| Item | Construction | Upkeep | Role |
| --- | --- | --- | --- |
| City | 25 G | 0 | Recruit and upgrade units; no extra income |
| Tower | 15 G + 5 G for each tower currently controlled | 2 G/turn | Existing strength-2 defense |
| Bridge | 15 G per segment | 2 G/turn per segment | Public neutral crossing; normal movement cost |
| Road connection | 1 G per newly paved tile | 0 | Half-cost movement along connected friendly road segments |

Tower prices count the entire faction, including separate treasuries. Losing a
tower reduces the former owner's current construction price. Watchtower encounter
landmarks retain their separate defense-aura rules and are not ordinary towers.

Scouts move 5 hexes, Soldiers 4, and Knights 3. Each army gets one move order per
turn. Friendly land and bridge steps cost one movement point; travel between two
adjacent friendly road provinces costs half a point. Attacking or capturing costs
one point and ends the move. Roads on the captured province survive, but cannot
discount that attack. Mountains remain impassable. Weighted pathfinding chooses
the cheapest traversable route, including road detours. A move spends the action
even when it does not use the entire movement allowance. Trailblaze keeps its
explicit bonus move after neutral capture.

Recruitment and paid upgrades are allowed on a friendly capital or city and all
adjacent owned land connected to a treasury. Fresh recruits, including Summon and
encounter rewards, can move immediately. Upgrading a unit preserves whether its
action was already spent. Equal-tier Scouts and Soldiers can merge in the field
within movement range to create the next tier. The result keeps the target unit's
spent/ready state; Knights and mismatched ranks cannot merge. Units can occupy city
tiles. Cities survive capture and become recruitment hubs for their new owner.
Development supplies income; cities have no replacement for the old house bonus.

Selecting a recruit shows a green area boundary and subtle fill across its legal
deployment and upgrade tiles. The boundary follows cities, capitals and adjacent
owned land, preserving holes and separate patches. It updates with the selected
rank and treasury, also applies to Summon, and disappears when targeting ends.

Forest spread and grave aging use the same empty-ground check. Trees cannot grow
over cities, capitals, other structures, units, chests, roads, mana sources,
encounters, wildlife, mountains or barriers. Graves on occupied tiles clear when
they age without creating a tree; graves on empty ground still become trees.

Owners can rename a city or capital in province details, using up to 40 characters.
Click the title and type; Enter or leaving the field saves the name, and an empty
name restores the default label. Names are
free, stay with the location on capture, and appear in details and hover tooltips.
Level documents, snapshots, online commands and replay patches preserve names.

Roads are built from province details, outside the Build menu. Select an owned
capital, city, tower or landmark, press the road icon, and point to another owned
structure or any friendly tile with an existing road. Highlighted structures and existing road tiles are affordable destinations;
hovering shows the actual paved road shape, resulting junctions and price. A connection follows clear friendly land and accessible
existing bridges. Unpaved empty provinces are valid intermediate tiles but cannot be endpoints.
Construction always starts from a structure. Each newly paved land tile costs 1 G, including the endpoints; existing
pavement is reused free and bridge decks are not charged. No partial work is done
if the route cannot be afforded.

Exact route edges are stored, so nearby roads do not automatically sprout extra
branches. The rendering uses the earlier clean, flat road strokes with no isolated
crossbars. Road movement discounts apply only along connected friendly segments;
captured land interrupts the owner's fast route. Existing bridges keep normal
movement costs. Saved early experimental maps without edge records remain readable.

Bridges retain neutral terrain ownership, separate from a recorded builder and
paying capital. The builder pays even if an opponent occupies the crossing.
Capital relocation moves the bill; merged treasuries inherit it. If that capital
is lost, a surviving treasury of the builder takes over, shown in bridge details.
If the builder has no surviving kingdom, the bridge is unsponsored. Neutral
bridges authored in the level editor have no builder and no automatic bill.
Neither bridge sponsorship nor roads contribute terrain income.

Roads, towers and bridges cannot be dismantled. Bridges can only be removed
with Shatter, which costs mana, gives no construction refund and destroys any
unit on the crossing. Bankruptcy still kills
unsupported armies and clears negative treasury balances; infrastructure remains
until removed, so its upkeep continues.

AI movement targets and direct threats use individual movement ranges. Both AI
backends march troops toward a front and build cities to cover distant fronts,
reserving gold for a useful city before routine purchases. Roads connect rear
recruitment hubs to forward hubs only when they improve current travel costs by
at least one movement point. Roads are limited by income and retain a city-sized
cash reserve; existing faster routes prevent redundant links. Urgent defence
can take precedence over city saving. Infrastructure counts in affordability and
upkeep. New tutorial exercises teach the
experimental rules. Authored maps migrate old houses to cities and preserve road
flags; snapshots, multiplayer positions, and replay patches retain infrastructure.

Focused checks: `test_logistics.gd` and `test_logistics_tutorial.gd`. These cover
weighted movement, recruitment readiness, captured cities, upkeep, bridge sponsorship,
demolition, snapshots, replays, level editing, both AI backends at every difficulty,
the production build menu, road rendering, and playable tutorial objectives.

Road surfaces and their preview borders share cached geometry and one retained
material across boards. Startup preloads all six-direction junction shapes for
the default palette and submits the actual road material during its concealed
render passes. Previewed meshes are reused when placed; unchanged permanent road
pieces are retained when another connection is built.

Live mouse hover and full interface refresh use the same preview-path update.
Hovering a valid road destination immediately shows the proposed surface and a
compact total-price tooltip, with no normal province-tooltip delay. Moving to an
invalid destination clears both the path and price. Regression checks exercise
hover changes without a full interface refresh.

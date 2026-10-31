# Nation limits

New matches support up to ten nations, including human and computer players.
The default remains four. Generated maps use the following caps; authored
multiplayer maps can contain up to ten active nations regardless of size metadata.

| Map | Nominal tiles | Maximum nations | Nominal tiles per nation |
| --- | ---: | ---: | ---: |
| Tiny | 80 | 4 | 20 |
| Small | 150 | 6 | 25 |
| Standard | 250 | 8 | 31.25 |
| Large | 500 | 10 | 50 |
| Huge | 1,000 | 10 | 100 |

These are balance recommendations, not a mathematical optimum. Start with a
budget of roughly 28 nominal tiles per nation (about three maximum-size starting
territories), round to the nearest even roster, then clamp between four and ten:
`clamp(2 * round(nominal_tiles / 56), 4, 10)`. Tiny is the intentional dense-map
exception. Its previous six-nation cap allowed only about 13 nominal tiles per
nation, despite each starting territory occupying 6–9 provinces. Its cap is now four.
The retired Very Small profile remains readable with a four-nation cap.

The generator normally spends 5–8.5% of land on mountains. Existing safeguards
reserve starting home rings, at least two passable first captures, and five hexes
between capitals. Extra nations must preserve all of those protections rather
than weakening them to squeeze in more seats. A ten-site fallback lattice covers
crowded packing failures; existing layouts remain unchanged for six or fewer.

Six seeds (0, 1, 7, 42, 71, 123) were generated at each new cap:

| Map | Mean land | Mean passable land | Mean unowned land | Minimum capital gap |
| --- | ---: | ---: | ---: | ---: |
| Tiny | 79.2 | 73.5 | 50.0 | 5 |
| Small | 151.5 | 142.5 | 104.8 | 5 |
| Standard | 249.2 | 231.0 | 187.2 | 5 |
| Large | 509.7 | 473.8 | 434.7 | 5 |
| Huge | 1,020.0 | 945.5 | 944.5 | 5 |

All thirty maps retained every requested capital, equal starting gold/income,
one Scout per nation, and two passable expansion options per nation. Repeat
generation checks preserve cells and RNG state. Unowned land in the table
includes mountains. Match length and diplomacy pressure still need playtesting;
these checks validate starting space and generation correctness.

Quick Play, local multiplayer, and Steam enforce the same generated-map limits.
Local and online rosters scroll within their existing panels. Online map choices
that cannot fit the human roster are disabled, and the host validates the cap
before distributing a start. Steam lobbies allow ten members. Wire protocol 3
rejects peers using the older six-seat assumptions; replay format and product
version are unchanged. No export or ZIP is regenerated.

Coverage: `test_nation_limits`, `test_nation_lobbies`, `test_ten_nation_match`, existing multiplayer setup,
authored-map and Steam suites, plus seeded generation fixtures at the new caps.
The live-match check verifies that all nine AI opponents take their turn and
return control to the human, and statistics include all ten nations.

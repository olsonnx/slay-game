# Encounters

Encounter markers are generated on neutral Modern land or painted with the editor's Events tool. Entering a marked province evaluates the event's requirements against the arriving faction and its connected kingdom, after capture and terrain clearing. Every entered marker is consumed immediately and produces an encounter. Event types use relative weights in `event_catalog.gd`. If a marker's requirements are unmet, a weighted draw selects an eligible event before the dialog is revealed; the replacement has its own matching title, story and effects. It cannot be revisited or saved for later. Choice tooltips retain decision-relevant percentages, reward amounts, costs, losses and permanent effects. They omit treasury-routing details, general eligibility explanations and other secondary rules; brief jokes can accompany the effects. Unaffordable purchases and mana gains at capacity remain disabled. AI factions use the same conditions and effects.

| Event | Requirements | Outcomes |
| --- | --- | --- |
| Comet sighted! | Connected kingdom | Permanent +1 or +2 income, randomly; or a free, ready Scout with normal upkeep. Only recruitment is disabled when no clear, empty province is available. |
| Innkeeper's Offer | Army in a connected kingdom | Both named drinks independently offer 50% death / 50% +4G |
| Lumberjack's Offer | This connected kingdom has trees | One event with a story and choice selected by current forest coverage. Clear local trees; +1G per tree when at most half of potential income is blocked, otherwise no gold. |
| Regroup! | Faction has at least two units | Disband only your faction's armies and refund full purchase prices to their home treasuries, including bridge units; stranded units refund the encounter kingdom. Or reject. |
| Cartographer's blunder | Connected kingdom | Event province and adjacent player-owned land become neutral; their units, capitals and buildings are lost. Enemy land is unchanged. |
| A noble ransom | Another faction is alive | +20G locally, or +1 mana if below capacity |
| A crisis of confidence | Connected kingdom with income to sell or at least 10G to invest; no deficit required | Permanent −1 income / +10G locally, or −10G locally / permanent +1 income. Selling is disabled when the income treasury earns zero; investing is disabled below 10G. |
| The Pitchfork Parliament | Spare nonhuman kingdom identity and adjacent passable land | Independent AI kingdom seizes event province and adjacent passable land, with garrisons; or pay the entire local treasury |
| Invention of stainless steel | Faction owns a Knight and lacks this discovery | Permanent −2G upkeep per Knight, faction-wide; does not stack |

Forest coverage is measured by income, not province count: blocked land values divided by all potential land income, including house income. Exactly half uses the paid lumberjack outcome. The catalog, weighted lottery and editor expose one `lumberjack` event. Its title and painting stay the same; story, choice caption and reward adapt to current coverage. Older authored `lumberjack_overgrown` markers migrate to `lumberjack` on load. A treeless kingdom draws a different eligible event instead of spending its encounter on an empty forest-clearance joke. Other connected kingdoms of the same faction are unaffected by either lumberjack. Mana sources remain, but clearing source-bearing trees can reduce mana capacity under the normal rules.

Replacements happen only before reveal. A valid Comet keeps its identity and effects; forest coverage changes the story and reward within the single lumberjack event. Generated encounters exclude bridges as well as mountains. AI choices are checked against the same availability shown to players and fall back to an enabled choice when their preferred option is unavailable.

Permanent income is a faction benefit applied to one treasury, anchored to the capital where it was first awarded. If that capital is lost or relocated, a deterministic surviving treasury receives it. Splits never duplicate it and a captor never inherits it. Additional income events add to the same faction total; income cannot fall below zero. Permanent means for this match: restarting restores the authored or generated starting position.

Modifiers use the existing authoritative effects state, so AI simulations, tutorial checkpoints and replays retain them. Replays also record changes to faction count. Newly spawned rebels use an available identity with its own palette and join the normal AI turn order. Mountains and bridges are excluded from rebellion and cartographer regions.

The catalog contains presentation text and reusable requirement tags; `encounter_rules.gd` owns eligibility, dynamic choice availability and the new effects. Invalid choices do not consume the encounter, advance RNG or change state. The editor lists all catalog entries and the requirements for their main outcomes, explaining that unmet conditions draw a useful weighted replacement.

## Relative frequency

Weights are tuning values, not fixed percentages: an eligible event's chance is its weight divided by the total weight of the eligible pool. Generated markers use these weights, and unavailable events are replaced using the same weights with unmet requirements excluded. Eligibility is checked after arrival, capture and terrain clearing. Every nonempty draw consumes one seeded RNG roll; empty pools consume none. Restart, cancellation, snapshots and replay retain deterministic results.

| Event | Weight |
| --- | ---: |
| Forgotten fortune | 12 |
| Lumberjack (light or heavy forest) | 8 |
| Innkeeper, ransom, crisis of confidence | 6 each |
| Duel, wizard | 5 each |
| Altar, comet | 4 each |
| Goose, regroup | 3 each |
| Revolt, stainless steel | 2 each |
| Pit, cartographer | 1 each |

Lumberjack has one lottery entry and weight 8 regardless of forest coverage. Zero-weight entries remain available to the level editor. Heavy clearance remains a real terrain effect even without a gold reward.

The goose now collects 2G from spectators. A wizard is ineligible while a free spell is already stored; an altar is ineligible on an existing mana source. Fortune and goose need a treasury, and a Knight's duel needs somewhere to pay its reward. These checks prevent encounters whose promised benefit cannot apply. Players can still deliberately decline a risky duel or altar, or reject regrouping; those are explicit decisions with working alternatives, not replacement no-op dialogs.

## Further event ideas

- **The Royal Census:** the same village has been counted twice. Require a large kingdom; take a one-time tax windfall or pay to improve permanent income.
- **A Bridge Too Taxing:** require a bridge garrison. Accept a toll windfall and lose the bridge, or repair it at a cost.
- **The Goose Returns:** require a previous goose encounter. The claimant now has a cabinet; pay it off or recruit an absurdly expensive honorary Scout.
- **An Extremely Local Plague:** require several graves. Fund sanitation to clear graves, or receive emergency gold while trees inherit the problem next turn.
- **An Accountant of Unusual Courage:** require impending bankruptcy. Sell a house for immediate gold or dismiss one Knight with a partial refund.

## Shared text formatting

Events can set a `painting` resource path in their catalog entry. Events without dedicated art use `DEFAULT_PAINTING` from the catalog: Józef Chełmoński’s Landscape – Forest. The fallback shares the same sepia treatment, rounded corners, aspect-ratio preservation and title/artist tooltip; it does not apply to capital-relocation confirmations. Its Lossy import quality is 0.65 (approximately 112 KiB). The lumberjack event uses the woodcutters painting in `assets/paintings/`. Optional `painting_title` and `painting_artist` metadata provide the hover tooltip, using the same compact tooltip presentation as the rest of the UI. The shared event dialog displays only title, optional painting, story and choices. It omits the encounter category heading, requirements subtext and hover instructions; brief effects or jokes remain on choice tooltips. It places the painting between the title and story, preserves its aspect ratio, and applies a sepia shader with antialiased 8-pixel rounded corners. The treatment applies automatically to future event paintings and leaves source images unchanged. The woodcutters texture uses Lossy import compression at quality 0.65; its imported texture is approximately 200 KB.

All event text stays plain in the catalog and translations. `src/ui/event_text.gd` applies the shared presentation rules when rendering dialogs, outcome tooltips and editor previews. Future catalog events use the same system automatically, including replacement events and runtime-generated amounts.

- Benefits use the existing green, losses and payments use red, mana uses blue, neutral monetary amounts use gold, and zero amounts are muted.
- Numbers are interpreted within their clause and nearest action, so a payment followed by an income gain receives two different colours. A reduction in wages is a benefit; a reduction in mana capacity is a loss.
- Scout, Soldier and Knight names, their plurals, and generic unit, army and garrison references are bold. Translated unit terms are recognized too.
- Button captions keep their normal hover, pressed and disabled colours while bolding unit references. Their outcome tooltips carry the full effect colours.
- Formatting preserves the original wording and punctuation. Literal brackets are escaped, and labels/tooltips account for bold text when measuring wrapping and height.

Event option tooltips put separate effects on separate lines, including semicolon-separated text from older language packs. Their widths are measured from the actual normal and bold text runs, with wrapping fixed before fitting the box; short effects do not inherit a minimum text width. The native tooltip frame supplies matching left/right padding (12 px) and top/bottom padding (8 px).

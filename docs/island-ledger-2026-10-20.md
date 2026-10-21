# Island ledger

The upper-right icon opens a faction table: hexes, gold, income, costs, profit, units, and an icon to focus the faction's largest capital. It contains no individual kingdom cards or explanatory footer. A single income graph compares faction totals using the table's faction colors. Hovering the graph shows values at a round; hovering unit totals shows the tier breakdown.

`src/ui/ledger_model.gd` aggregates all territories belonging to each faction, including wages for supported bridge units. Historical samples use the recorder's existing economy observations, retaining the final observation per completed round and adding current income as the live point. Faction history continues across capital relocation, splits, and mergers. Eliminated factions have zero income in subsequent samples. There is no extra simulation or work added to turn processing.

Validation:
- Ledger checks: 50 passed headless and in Forward+; covers aggregation across disconnected territories, history after capital changes, zero income for eliminated factions, table alignment, graph hover, capital icons, and supported bridge units.
- UI layout checks: 499 passed headless.
- Forward+ screenshots reviewed at 1100×760 and 960×640: `artifacts/ledger-preview.png`, `artifacts/ledger-small-preview.png`.

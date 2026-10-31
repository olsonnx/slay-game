# Event artwork

All nineteen current events now have distinct artwork. Sixteen images were downloaded for the previously unillustrated events; the existing Tax Collectors image was assigned to the economist. Lumberjack and Comet retain their existing paintings.

Event dialogs use the existing **2:1 frame** (424 × 212 logical pixels), rounded corners, and sepia treatment. Prebuilt 1024 × 512 WebP banners provide the normal event image, cropped without stretching. The shader provides the colour treatment and also handles unbuilt custom artwork. `painting_focus: [x, y]` supplies an optional focal point as integer percentages from 0 to 100; the default is `[50, 50]`. Portraits and action scenes use individual focal points to retain faces and important details. Source files remain uncropped, and Collection displays the complete original in colour. The application preloads and renders the small banners behind its startup cover; event reveals and Collection discovery reuse them without decoding the originals. Rebuild banners after changing an image or its focal point with `tools/build_event_previews.gd`, then run a Godot asset import. `resources/art/event_previews.json` maps source/focus pairs to generated previews. See [event artwork loading](event-art-loading.md) for measurements and lifecycle details.

The source records below identify versions explicitly marked public domain or CC0. `PDM-owner` is the source’s Public Domain Mark label. The machine-readable manifest records the exact image URL, original dimensions, local file, license metadata, and SHA-256 checksum for every new assignment. Sources are preserved for attribution and future replacement.

| Event | Painting | Artist | Source reuse label |
| --- | --- | --- | --- |
| `gold` | [The Parable of the Rich Fool](https://commons.wikimedia.org/wiki/File:Rembrandt_-_The_Parable_of_the_Rich_Fool.jpg) | Rembrandt | Public domain |
| `altar` | [Cairn in Snow](https://commons.wikimedia.org/wiki/File:Caspar_David_Friedrich_-_Cairn_in_Snow_-_Google_Art_Project.jpg) | Caspar David Friedrich | Public domain |
| `pit` | [Alpine Landscape with Beck](https://commons.wikimedia.org/wiki/File:Alpine_Landscape_with_Beck_(SM_1553).png) | Gustave Doré | PDM-owner |
| `duel` | [Combat of the Giaour and Hassan](https://commons.wikimedia.org/wiki/File:Eug%C3%A8ne_Delacroix_-_Combat_du_Giaour_et_Hassan_(1826).jpg) | Eugène Delacroix | Public domain |
| `wizard` | [The Alchemist](https://commons.wikimedia.org/wiki/File:David_Teniers_de_Jonge_-_The_Alchemist_-_261_-_Mauritshuis.jpg) | David Teniers the Younger | Public domain |
| `goose` | [Geese and Ducks](https://commons.wikimedia.org/wiki/File:Melchior_d%27_Hondecoeter_-_Geese_and_Ducks_-_61_-_Mauritshuis.jpg) | Melchior d’Hondecoeter | Public domain |
| `innkeeper` | [Tavern Scene](https://commons.wikimedia.org/wiki/File:David_Teniers_the_Younger,_Tavern_Scene,_1658,_NGA_55505.jpg) | David Teniers the Younger | CC0 |
| `regroup` | [Army Camp](https://commons.wikimedia.org/wiki/File:Philips_Wouwerman_-_Army_Camp_-_220_-_Mauritshuis.jpg) | Philips Wouwerman | Public domain |
| `cartographer` | [The Geographer](https://commons.wikimedia.org/wiki/File:Johannes_Vermeer_-_The_Geographer_-_Google_Art_Project.jpg) | Johannes Vermeer | Public domain |
| `ransom` | [The Laughing Cavalier](https://commons.wikimedia.org/wiki/File:Frans_Hals_%E2%80%93_The_Laughing_Cavalier.jpg) | Frans Hals | Public domain |
| `revolt` | [Peasant Brawl](https://commons.wikimedia.org/wiki/File:Peasant_Brawl_by_Adriaen_Brouwer_Mauritshuis_919.jpg) | Adriaen Brouwer | CC0 |
| `stainless_steel` | [The Blacksmith’s Shop](https://commons.wikimedia.org/wiki/File:Joseph_Wright_of_Derby_-_The_Blacksmith%27s_Shop_-_Google_Art_Project.jpg) | Joseph Wright of Derby | Public domain |
| `builders_guild` | [The Stonemason’s Yard](https://commons.wikimedia.org/wiki/File:Canaletto_-_The_Stonemason%27s_Yard.jpg) | Canaletto | Public domain |
| `barracks` | [Guardroom](https://commons.wikimedia.org/wiki/File:Soldatenwacht,_SK-A-398.jpg) | David Teniers the Younger and anonymous | CC0 |
| `scout_lodge` | [Landscape with a Cottage and Trees](https://commons.wikimedia.org/wiki/File:Jacob_van_Ruisdael_-_Landscape_with_a_Cottage_and_Trees.jpg) | Jacob van Ruisdael | Public domain |
| `watchtower` | [The Castle of Bentheim](https://commons.wikimedia.org/wiki/File:Il_castello_di_Bentheim_(Jacob_Van_Ruisdael).jpg) | Jacob van Ruisdael | Public domain |
| `economist` | [The Tax Collectors](https://commons.wikimedia.org/wiki/File:Quentin_Massys,_The_Tax_Collectors,_Kunstmuseum_Liechtenstein.webp) | Quentin Massys | Public domain |

Source details: [event_painting_sources.json](../resources/art/event_painting_sources.json).

Run `tools/event_art_preview.gd` with a real renderer to produce `artifacts/event-art-contact-sheet.png`, showing all nineteen event crops together. `tests/test_event_art.gd` checks assignment coverage, source hashes, reusable-source records, image resolution, fixed framing, and authored focus validation. Collection, event-editor and UI-layout tests cover discovery, full-image viewing and dialog layout.

No game rules, event outcomes, frequencies, export ZIP, or application version changed.

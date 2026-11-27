extends RefCounted
## Concise choice tooltips retain chances, amounts, costs and lasting consequences.
const DEFAULT_PAINTING := {
	"painting": "res://assets/paintings/Jozef_Chełmoński_-_Landscape_-_Forest.png",
	"painting_title": "Landscape – Forest",
	"painting_artist": "Józef Chełmoński"
}
# Relative frequency, not a percentage. Each event has one lottery entry.
# A zero weight keeps an event available to the editor, but out of random draws.
const BUILTIN_WEIGHTS := {
	"gold": 12, "altar": 4, "pit": 1, "duel": 5, "wizard": 5,
	"goose": 3, "comet": 4, "innkeeper": 6, "lumberjack": 8,
	"regroup": 3, "cartographer": 1,
	"ransom": 6, "economist": 6, "revolt": 2, "stainless_steel": 2,
	"builders_guild": 2, "barracks": 2, "scout_lodge": 2, "watchtower": 2
}
const BUILTIN_EVENTS := {
	"gold": {"painting": "res://assets/paintings/events/gold.jpg", "painting_title": "The Parable of the Rich Fool", "painting_artist": "Rembrandt", "painting_focus": [50, 47], "title": "A forgotten fortune", "text": "Beneath a crumbling milestone, your army discovers a chest of coins. Nobody remains to claim it.", "choices": [["Great!", "Gain 10–25 gold."]]},
	"altar": {"painting": "res://assets/paintings/events/altar.jpg", "painting_title": "Cairn in Snow", "painting_artist": "Caspar David Friedrich", "painting_focus": [50, 58], "title": "The sleeping altar", "text": "An ancient altar hums beneath the moss. Its runes promise power, but the last inscription is a warning.", "choices": [["Awaken it", "60%: gain a mana source.\n40%: this army dies."], ["Leave it alone", "Nothing happens."]]},
	"pit": {"painting": "res://assets/paintings/events/pit.png", "painting_title": "Alpine Landscape with Beck", "painting_artist": "Gustave Doré", "painting_focus": [50, 62], "title": "One step too far", "text": "The ground gives way. A hidden pit swallows your army before anyone can throw down a rope.", "choices": [["A tragic loss", "Your army is lost."]]},
	"duel": {"painting": "res://assets/paintings/events/duel.jpg", "painting_title": "Combat of the Giaour and Hassan", "painting_artist": "Eugène Delacroix", "painting_focus": [50, 42], "title": "The warlord's challenge", "text": "A local warlord bars the road and challenges your champion. Victory would make your soldiers legends.", "choices": [["Accept the challenge", "60%: gain 1 tier (Knights gain 20 gold).\n40%: this army dies."], ["Decline politely", "Nothing happens."]]},
	"wizard": {"painting": "res://assets/paintings/events/wizard.jpg", "painting_title": "The Alchemist", "painting_artist": "David Teniers the Younger", "painting_focus": [50, 48], "title": "A friend in a pointed hat", "text": "A wandering wizard shares tea with your soldiers and offers a little magic for the journey ahead.", "choices": [["Thank you, kind wizard", "Your next successful spell costs 0 mana."]]},
	"goose": {"painting": "res://assets/paintings/events/goose.jpg", "painting_title": "Geese and Ducks", "painting_artist": "Melchior d’Hondecoeter", "painting_focus": [50, 60], "title": "A very important goose", "text": "A goose claims to be the rightful ruler of this island. After a lengthy honk, it waddles away. Your army collects 2 gold from spectators as the first royal tax.", "requires": ["kingdom"], "choices": [["Long live the goose", "Gain 2 gold.\nThe goose remains extremely pleased."]]},
	"comet": {"title": "Comet sighted!", "text": "The priests predict disaster. The treasurer predicts revenue. The recruiting sergeant proposes recruiting volunteers inspired by the omen.", "requires": ["kingdom"], "requirements": "A connected kingdom. Recruiting volunteers also requires a clear, empty province.", "choices": [["Clearly a tax loophole.", "Build a landmark: +1–2 gold per turn to its kingdom while controlled.\n50% chance of each."], ["Recruit the volunteers.", "Gain a Scout on or beside an available castle or capital. Ready immediately.\nNormal upkeep applies."]]},
	"innkeeper": {"painting": "res://assets/paintings/events/innkeeper.jpg", "painting_title": "Tavern Scene", "painting_artist": "David Teniers the Younger", "painting_focus": [50, 50], "requires": ["kingdom"], "title": "Innkeeper's Offer", "text": "The innkeeper insists your army try the local spirits. Declining would insult his hospitality, his ancestors, and the large man blocking the door.", "requirements": "Any army entering this province.", "choices": [["Try Headman's Last Breath.", "50%: gain 4 gold.\n50%: this army dies."], ["Try Father's Final Request.", "50%: gain 4 gold.\n50%: this army dies."]]},
	"lumberjack": {"painting": "res://assets/paintings/Franz_Steinfeld_-_Landscape_with_Group_of_Trees_and_Woodcutters.png", "painting_title": "Landscape with Group of Trees and Woodcutters", "painting_artist": "Franz Steinfeld", "overgrown_text": "Our kingdom is mostly forest, with a small administrative inconvenience attached. A lumberjack offers to find the roads. Payment, he says, would be optimistic.", "overgrown_choices": [["At least we will have a kingdom again.", "Clear your kingdom's trees.\nNo gold reward."]], "title": "Lumberjack's Offer", "text": "The royal forester has spent three months counting trees. A man with an axe offers to conclude the investigation before lunch.", "requires": ["kingdom", "forest"], "requirements": "This connected kingdom has trees. Rewards depend on how much potential income they block.", "choices": [["A promising branch of government.", "Clear your kingdom's trees.\nGain 1 gold per tree."]]},
	"regroup": {"painting": "res://assets/paintings/events/regroup.jpg", "painting_title": "Army Camp", "painting_artist": "Philips Wouwerman", "painting_focus": [50, 62], "title": "Regroup!", "text": "The marshal reports that our army is perfectly balanced, provided one ignores its composition, deployment, and continued existence. He proposes a fresh start.", "requires": ["kingdom", "multiple_units"], "requirements": "Your faction has at least two units on the board.", "choices": [["Return everyone to the recruitment office.", "Disband all your armies.\nRefund 100% of their recruitment cost."], ["The imbalance is traditional.", "Tradition wins another decisive victory."]]},
	"cartographer": {"painting": "res://assets/paintings/events/cartographer.jpg", "painting_title": "The Geographer", "painting_artist": "Johannes Vermeer", "painting_focus": [50, 48], "title": "Cartographer's blunder", "text": "Our court cartographer admits the border was drawn with a wine stain as reference. The neighbouring villages have accepted his correction with suspicious enthusiasm.", "requires": ["kingdom"], "requirements": "The army belongs to a connected kingdom.", "choices": [["Revise the map. Quietly.", "This province and your neighbouring land become neutral.\nUnits and buildings there are lost."]]},
	"ransom": {"painting": "res://assets/paintings/events/ransom.jpg", "painting_title": "The Laughing Cavalier", "painting_artist": "Frans Hals", "painting_focus": [50, 31], "title": "A noble ransom", "text": "Your army finds a foreign royal travelling incognito, accompanied by twelve servants carrying his portrait. His family may pay handsomely for his continued discretion.", "requires": ["kingdom", "other_faction"], "requirements": "At least one other living faction remains.", "choices": [["Royalty is a liquid asset.", "Gain 20 gold."], ["Let his death demonstrate our power.", "Gain 1 mana."]]},
	"economist": {"painting": "res://assets/paintings/Quentin_Massys,_The_Tax_Collectors,_Kunstmuseum_Liechtenstein.webp", "painting_title": "The Tax Collectors", "painting_artist": "Quentin Massys", "painting_focus": [50, 38], "title": "A crisis of confidence", "text": "Our court economist has lost confidence in the accounts. He proposes selling future revenue for cash, or investing cash in future revenue. The treasurer insists we choose before he changes his forecast again.", "requires": ["kingdom", "income_trade"], "requirements": "A connected kingdom with income to sell or at least 10 gold to invest. A deficit is not required.", "choices": [["Tomorrow is an accounting problem.", "Gain 10 gold.\nBuild a landmark: -1 gold per turn to its kingdom while controlled."], ["Perhaps tomorrow should have an income.", "Pay 10 gold.\nBuild a landmark: +1 gold per turn to its kingdom while controlled."]]},
	"revolt": {"painting": "res://assets/paintings/events/revolt.jpg", "painting_title": "Peasant Brawl", "painting_artist": "Adriaen Brouwer", "painting_focus": [50, 56], "title": "The Pitchfork Parliament", "text": "The peasants have formed a representative assembly. Every representative carries a pitchfork, and their first motion is that we should leave immediately.", "requires": ["kingdom", "rebel_slot"], "requirements": "An unused kingdom identity is available, and this province has neighbouring passable land.", "choices": [["Recognise their independence. From a distance.", "Rebels seize this province and neighbouring land.\nUnits there join the rebels."], ["Surely this calls for a modest subsidy.", "Pay 100% of this kingdom's gold."]]},
	"stainless_steel": {"painting": "res://assets/paintings/events/stainless_steel.jpg", "painting_title": "The Blacksmith’s Shop", "painting_artist": "Joseph Wright of Derby", "painting_focus": [50, 56], "title": "Invention of stainless steel", "text": "A smith has invented armour that refuses to rust. Our knights demand the savings be passed on to them. The treasurer has understood this request rather differently.", "requires": ["kingdom", "knights", "no_stainless_steel"], "requirements": "Your faction has a Knight and does not control a stainless steel landmark.", "choices": [["A triumph of military economy.", "Build a landmark: its owner's Knight wages are 25% lower. Does not stack."]]},
	"builders_guild": {"painting": "res://assets/paintings/events/builders_guild.jpg", "painting_title": "The Stonemason’s Yard", "painting_artist": "Canaletto", "painting_focus": [50, 62], "title":"Measure twice, tax once", "text":"The builders have formed a guild. Their first discovery is that neighboring villages can share tools. Their second is that nobody has been keeping the receipts.", "requires":["kingdom"], "choices":[["Let them build on this idea.","Build a Builders' Guild: development costs 50% less here and on adjacent friendly provinces. Does not stack."]]},
	"barracks": {"painting": "res://assets/paintings/events/barracks.jpg", "painting_title": "Guardroom", "painting_artist": "David Teniers the Younger and anonymous", "painting_focus": [50, 56], "title":"The quartermaster's ledger", "text":"A retired quartermaster offers to house the soldiers together. Apparently, buying twelve identical dinners is cheaper than reimbursing twelve heroic banquets.", "requires":["kingdom"], "choices":[["Put it in writing.","Build Soldiers' Barracks: its owner's Soldier wages are 50% lower. Does not stack."]]},
	"scout_lodge": {"painting": "res://assets/paintings/events/scout_lodge.jpg", "painting_title": "Landscape with a Cottage and Trees", "painting_artist": "Jacob van Ruisdael", "painting_focus": [50, 56], "title":"Room at the rangers' lodge", "text":"The scouts have found a lodge with dry boots, warm beds, and a remarkably inexpensive kitchen. They would like to register it as a military innovation.", "requires":["kingdom"], "choices":[["Approve the boot budget.","Build a Scout Lodge: its owner's Scout wages are 50% lower. Does not stack."]]},
	"watchtower": {"painting": "res://assets/paintings/events/watchtower.jpg", "painting_title": "The Castle of Bentheim", "painting_artist": "Jacob van Ruisdael", "painting_focus": [50, 40], "title":"A light on the hill", "text":"An old watchtower still commands the surrounding roads. Its keeper proposes a warning beacon. The army proposes somebody else take the night shift.", "requires":["kingdom"], "choices":[["Light the beacon.","Restore a Watchtower: +1 defense here and to adjacent friendly units. No attack bonus. Does not stack."]]}

}
const EFFECTS := {
	"trailblaze": ["↠", "Trailblaze", "The next unit you move can move again if it captures neutral land. Any valid move consumes this effect. Persists until used."],
	"free_spell": ["✦", "Wizard's gift", "Your next successfully cast spell costs no mana. Persists until used."]
}

static func canonical_id(id: String) -> String:
	# Older authored maps keep working, but the editor exposes only one lumberjack.
	return "lumberjack" if id == "lumberjack_overgrown" else id

const AuthoredSchema = preload("res://src/game/authored_event_schema.gd")
static var EVENTS: Dictionary = loaded_events()
static var WEIGHTS: Dictionary = loaded_weights(EVENTS)
static var EVENT_PREVIEWS: Dictionary = load_event_previews()
static var EVENT_TEXTURES: Dictionary = {}

static func load_event_previews() -> Dictionary:
	var path := "res://resources/art/event_previews.json"
	if not FileAccess.file_exists(path): return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value.get("paintings",{}) if value is Dictionary else {}

static func event_texture_key(artwork: Dictionary) -> String:
	var focus := painting_focus(artwork)
	return String(artwork.get("painting",""))+"|"+str(roundi(focus.x*100))+","+str(roundi(focus.y*100))

static func event_texture_path(artwork: Dictionary) -> String:
	var record: Dictionary = EVENT_PREVIEWS.get(event_texture_key(artwork),{})
	var path := String(record.get("preview",""))
	if path != "" and (ResourceLoader.exists(path) or FileAccess.file_exists(path)): return path
	return String(artwork.get("painting",""))

static func event_texture(artwork: Dictionary) -> Texture2D:
	var path := event_texture_path(artwork)
	if EVENT_TEXTURES.has(path): return EVENT_TEXTURES[path]
	var texture := painting_texture(path)
	if texture != null: EVENT_TEXTURES[path] = texture
	return texture

static func event_texture_focus(artwork: Dictionary) -> Vector2:
	return Vector2(0.5,0.5) if event_texture_path(artwork) != String(artwork.get("painting","")) else painting_focus(artwork)

static func gallery_thumbnail_path(source_path: String) -> String:
	for record in EVENT_PREVIEWS.values():
		if record.get("source","") != source_path: continue
		var path := String(record.get("thumbnail",""))
		if path != "" and (ResourceLoader.exists(path) or FileAccess.file_exists(path)): return path
	return ""

static func public_definition(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	result["authored"] = data.duplicate(true)
	result["requires"] = []
	result["choices"] = []
	for choice in data.choices: result.choices.append([choice.label,choice.get("hint","")])
	return result

static func loaded_events() -> Dictionary:
	var result: Dictionary = BUILTIN_EVENTS.duplicate(true)
	var pack := AuthoredSchema.load_pack()
	if pack.error != "": push_warning("Custom events were not loaded: "+pack.error)
	for data in pack.events: result[data.id] = public_definition(data)
	return result

static func loaded_weights(events: Dictionary) -> Dictionary:
	var result: Dictionary = BUILTIN_WEIGHTS.duplicate()
	for id in events:
		if events[id].has("authored"):
			var data: Dictionary = events[id].authored
			result[id] = int(data.get("weight",4)) if data.get("enabled",true) else 0
	return result

static func reload() -> void:
	EVENTS.assign(loaded_events())
	WEIGHTS.assign(loaded_weights(EVENTS))

static func painting_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path): return null
	if FileAccess.file_exists(path+".import") or OS.has_feature("template"):
		return load(path) as Texture2D
	# Artwork copied by the running editor is immediately previewable, before import.
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null

static func artwork(definition: Dictionary) -> Dictionary:
	if not String(definition.get("painting", "")).is_empty(): return definition
	return {} if definition.get("focus_cancel", false) else DEFAULT_PAINTING

static func painting_focus(definition: Dictionary) -> Vector2:
	# Percent coordinates survive the authored pack's integer normalization.
	var value = definition.get("painting_focus",[50,50])
	if not value is Array or value.size() != 2: return Vector2(0.5,0.5)
	for coordinate in value:
		if not (coordinate is int or coordinate is float) or not is_finite(coordinate): return Vector2(0.5,0.5)
	return (Vector2(value[0],value[1])/100.0).clamp(Vector2.ZERO,Vector2.ONE)

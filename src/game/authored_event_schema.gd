extends RefCounted
## Shared data contract for the form editor, imported packs and game runtime.
const VERSION := 1
const PACK_PATH := "res://resources/events/custom_events.json"
const MAX_PACK_BYTES := 5000000
const CONDITIONS := {
	"kingdom":"Connected kingdom", "recruit_space":"Free recruitment province", "forest":"Kingdom has trees",
	"multiple_units":"At least two friendly armies", "knights":"Faction has a Knight", "other_faction":"Another faction is alive",
	"rebel_slot":"An unused rebel faction is available", "no_stainless_steel":"No steel landmark controlled",
	"income_trade":"Local income to sell or 10 gold to invest", "duel_reward":"Arriving army can receive a duel prize", "gold_at_least":"Local gold at least",
	"income_at_least":"Local income at least", "mana_at_least":"Mana at least", "mana_space":"Unfilled mana storage",
	"unit_tier_at_least":"Arriving unit rank at least", "unit_tier_at_most":"Arriving unit rank at most",
	"forest_overgrown":"Trees block more than half of income", "has_effect":"Has temporary effect",
	"no_effect":"Does not have temporary effect", "mana_source":"Encounter tile is a mana source"
}
const ACTIONS := {
	"gold":"Give / take local gold", "gold_percent":"Change local treasury by percent", "mana":"Give / take mana",
	"kill_unit":"Kill the arriving army", "promote":"Promote army / pay max-rank reward", "recruit":"Recruit a free army",
	"clear_trees":"Clear this kingdom's trees", "disband":"Disband faction armies and refund",
	"neutralize":"Neutralize nearby friendly land", "revolt":"Create a rebel kingdom",
	"landmark":"Construct a permanent reward landmark", "mana_source":"Create / remove mana source",
	"temporary_effect":"Grant / remove a temporary effect", "building":"Construct ordinary building",
	"tile_value":"Change this province's value", "clear_terrain":"Clear trees and graves on this province"
}
const TEMPORARY := ["free_spell","trailblaze"]
const TERMINAL := ["kill_unit","disband","neutralize","revolt"]

static func action(kind := "gold") -> Dictionary:
	var result := {"kind":kind}
	match kind:
		"gold", "mana": result.merge({"min":1,"max":1,"use_reveal_roll":false})
		"gold_percent": result["percent"] = -100
		"promote": result.merge({"steps":1,"max_rank_gold":20})
		"recruit": result.merge({"tier":1,"ready":true})
		"clear_trees": result.merge({"gold_per_tree":1,"adaptive":true})
		"disband": result["refund_percent"] = 100
		"neutralize", "revolt": result["radius"] = 1
		"landmark": result.merge({"income_min":1,"income_max":1,"mana_min":0,"mana_max":0,"steel":false,"development_discount":false,"soldier_discount":false,"scout_discount":false,"defense_aura":false})
		"mana_source": result["enabled"] = true
		"temporary_effect": result.merge({"effect":"free_spell","enabled":true})
		"building": result["building"] = "city"
		"tile_value": result["amount"] = 1
	return result

static func outcome() -> Dictionary:
	return {"weight":100,"text":"The journey continues.","requires":[],"effects":[]}

static func choice() -> Dictionary:
	return {"label":"Continue", "hint":"", "ai_score":0,"cost_gold":0,"cost_mana":0,"requires":[],"outcomes":[outcome()]}

static func fresh(id := "new_event") -> Dictionary:
	return {"id":id,"title":"A new encounter","text":"What does your army discover?","weight":4,"enabled":true,
		"modern_only":true,"painting":"","painting_title":"","painting_artist":"","requirements":"",
		"gold_roll_min":0,"gold_roll_max":0,"requires":[],"choices":[choice()],"variants":[]}

static func condition_errors(items, path: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not items is Array: return PackedStringArray([path+" must be a list."])
	if items.size() > 32: errors.append(path+": use at most 32 requirements.")
	for item in items:
		if not item is Dictionary or not CONDITIONS.has(item.get("kind","")):
			errors.append(path+": unknown requirement.")
			continue
		if not typeof(item.get("not",false)) == TYPE_BOOL: errors.append(path+": Not must be a checkbox.")
		if not numeric(item.get("value",1),-100000,100000): errors.append(path+": invalid threshold.")
		if item.kind in ["has_effect","no_effect"] and item.get("effect","") not in TEMPORARY: errors.append(path+": unknown temporary effect.")
	return errors

static func numeric(value, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum

static func validate(data) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data is Dictionary: return PackedStringArray(["An event must be an object."])
	var id = data.get("id","")
	var pattern := RegEx.new()
	pattern.compile("^[a-z][a-z0-9_]{0,63}$")
	if not id is String or pattern.search(id) == null: errors.append("ID: use lowercase letters, digits and underscores; start with a letter.")
	if id == "lumberjack_overgrown": errors.append("That ID is reserved for compatibility; use a different ID.")
	for field in ["title","text"]:
		if not data.get(field) is String or String(data.get(field,"")).strip_edges().is_empty(): errors.append(field.capitalize()+" is required.")
	for field in ["title","text","painting","painting_title","painting_artist","requirements"]:
		if not data.get(field,"") is String or String(data.get(field,"")).length() > 12000: errors.append(field+": invalid or excessively long text.")
	for field in ["enabled","modern_only"]:
		if not data.get(field,true) is bool: errors.append(field+" must be a checkbox.")
	if not numeric(data.get("weight",4),0,10000): errors.append("Frequency must be between 0 and 10000.")
	for field in ["gold_roll_min","gold_roll_max"]:
		if not numeric(data.get(field,0),0,100000): errors.append("Reveal gold roll must be between 0 and 100000.")
	if numeric(data.get("gold_roll_min",0),0,100000) and numeric(data.get("gold_roll_max",0),0,100000) and data.get("gold_roll_min",0) > data.get("gold_roll_max",0): errors.append("Reveal gold minimum exceeds its maximum.")
	var painting: String = data.get("painting","") if data.get("painting","") is String else ""
	if painting != "" and (not painting.begins_with("res://assets/") or painting.contains("..") or painting.get_extension().to_lower() not in ["png","jpg","jpeg","webp","svg"]): errors.append("Painting must be an image under res://assets/.")
	if data.has("painting_focus"):
		var focus = data.painting_focus
		if not focus is Array or focus.size() != 2:
			errors.append("Painting focus must contain two percentages from 0 to 100.")
		elif not numeric(focus[0],0,100) or not numeric(focus[1],0,100):
			errors.append("Painting focus must contain two percentages from 0 to 100.")
	errors.append_array(condition_errors(data.get("requires",[]),"Event requirements"))
	errors.append_array(choice_errors(data.get("choices"),"Default story"))
	var variants = data.get("variants",[])
	if not variants is Array: errors.append("Story variants must be a list."); return errors
	if variants.size() > 16: errors.append("Use at most 16 story variants.")
	for i in range(variants.size()):
		var variant = variants[i]
		if not variant is Dictionary: errors.append("Invalid story variant."); continue
		if not variant.get("text","") is String: errors.append("Variant story must be text.")
		errors.append_array(condition_errors(variant.get("requires",[]),"Variant %d" % (i+1)))
		errors.append_array(choice_errors(variant.get("choices"),"Variant %d" % (i+1)))
	var stories: Array = [data]+variants
	for entry in stories:
		if not entry is Dictionary or not entry.get("choices") is Array: continue
		for choice in entry.choices:
			if not choice is Dictionary or not choice.get("outcomes") is Array: continue
			for result in choice.outcomes:
				if not result is Dictionary or not result.get("effects",[]) is Array: continue
				for effect in result.get("effects",[]):
					if effect is Dictionary and effect.get("use_reveal_roll",false) == true and data.get("gold_roll_max",0) == 0: errors.append("Using a reveal gold roll requires a nonzero reveal-roll maximum.")
	return errors

static func choice_errors(items, path: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not items is Array or items.is_empty() or items.size() > 4: return PackedStringArray([path+": use 1–4 choices."])
	for i in range(items.size()):
		var item = items[i]
		var label := path+", choice %d" % (i+1)
		if not item is Dictionary: errors.append(label+": invalid choice."); continue
		if not item.get("label","") is String or String(item.get("label","")).strip_edges() == "": errors.append(label+": a caption is required.")
		if not item.get("hint","") is String: errors.append(label+": effects hint must be text.")
		for field in ["cost_gold","cost_mana"]:
			if not numeric(item.get(field,0),0,100000): errors.append(label+": invalid cost.")
		if not numeric(item.get("ai_score",0),-100000,100000): errors.append(label+": invalid AI preference.")
		errors.append_array(condition_errors(item.get("requires",[]),label))
		var outcomes = item.get("outcomes",[])
		if not outcomes is Array or outcomes.is_empty() or outcomes.size() > 32: errors.append(label+": use 1–32 outcomes."); continue
		for result in outcomes:
			if not result is Dictionary: errors.append(label+": invalid outcome."); continue
			if not numeric(result.get("weight",100),1,10000): errors.append(label+": outcome weights must be positive, up to 10000.")
			if not result.get("text","") is String: errors.append(label+": outcome message must be text.")
			errors.append_array(condition_errors(result.get("requires",[]),label+" outcome"))
			var effects = result.get("effects",[])
			if not effects is Array or effects.size() > 32: errors.append(label+": use at most 32 effects."); continue
			var landmarks := 0
			for j in range(effects.size()):
				var effect = effects[j]
				if not effect is Dictionary or not ACTIONS.has(effect.get("kind","")): errors.append(label+": unknown effect."); continue
				var kind: String = effect.kind
				if kind in TERMINAL and j != effects.size()-1: errors.append(label+": death, disbanding and territory changes must be the last effect.")
				if kind in ["landmark","building"]: landmarks += 1
				for field in effect:
					if field in ["kind","effect","building"]: continue
					if field in ["ready","adaptive","steel","enabled","use_reveal_roll","development_discount","soldier_discount","scout_discount","defense_aura"]:
						if not effect[field] is bool: errors.append(label+": "+field+" must be a checkbox.")
					elif not numeric(effect[field],-100000,100000): errors.append(label+": invalid numeric effect field "+field)
				for prefix in ["","income_","mana_"]:
					if numeric(effect.get(prefix+"min",0),-100000,100000) and numeric(effect.get(prefix+"max",0),-100000,100000) and effect.get(prefix+"min",0) > effect.get(prefix+"max",0): errors.append(label+": minimum exceeds maximum.")
				if kind == "promote" and not numeric(effect.get("steps",1),1,2): errors.append(label+": promotion must be 1–2 ranks.")
				if kind == "recruit" and not numeric(effect.get("tier",1),1,3): errors.append(label+": army rank must be 1–3.")
				if kind in ["neutralize","revolt"] and not numeric(effect.get("radius",1),0,4): errors.append(label+": territory radius must be 0–4.")
				if kind == "temporary_effect" and effect.get("effect","") not in TEMPORARY: errors.append(label+": invalid temporary effect.")
				if kind == "building" and effect.get("building","") not in ["city","tower"]: errors.append(label+": ordinary building must be a castle or tower.")
				if kind == "disband" and not numeric(effect.get("refund_percent",100),0,100): errors.append(label+": refund must be 0–100 percent.")
				if kind == "gold_percent" and not numeric(effect.get("percent",-100),-100,1000): errors.append(label+": treasury percent must be -100 to 1000.")
			if landmarks > 1: errors.append(label+": use one structure effect per outcome.")
	return errors

static func load_pack(path := PACK_PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return {"events":[],"error":""}
	if FileAccess.get_file_as_bytes(path).size() > MAX_PACK_BYTES: return {"events":[],"error":"Event pack exceeds 5 MB."}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("version") != VERSION or not parsed.get("events") is Array: return {"events":[],"error":"Expected a version 1 event pack."}
	var seen := {}
	for event in parsed.events:
		var errors := validate(event)
		if not errors.is_empty(): return {"events":[],"error":"\n".join(errors)}
		if seen.has(event.id): return {"events":[],"error":"Duplicate event ID: "+event.id}
		seen[event.id] = true
	var normalized := []
	for entry in parsed.events: normalized.append(with_defaults(normalize(entry)))
	return {"events":normalized,"error":""}

static func save_pack(path: String, events: Array) -> String:
	var seen := {}
	for event in events:
		var errors := validate(event)
		if not errors.is_empty(): return "\n".join(errors)
		if seen.has(event.id): return "Duplicate event ID: "+event.id
		seen[event.id] = true
	var serialized := JSON.stringify({"version":VERSION,"events":events},"\t").to_utf8_buffer()
	if serialized.size() > MAX_PACK_BYTES: return "Event pack exceeds 5 MB. Shorten the text or remove events before saving."
	var absolute := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK: return "Cannot create event folder: "+error_string(directory_error)
	var file := FileAccess.open(absolute+".tmp",FileAccess.WRITE)
	if file == null: return "Cannot write event pack: "+error_string(FileAccess.get_open_error())
	file.store_buffer(serialized)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return "Cannot write event pack: "+error_string(write_error)
	if FileAccess.file_exists(absolute):
		var backup_error := DirAccess.copy_absolute(absolute,absolute+".bak")
		if backup_error != OK: return "Cannot back up event pack: "+error_string(backup_error)
	var rename_error := DirAccess.rename_absolute(absolute+".tmp",absolute)
	return "" if rename_error == OK else "Cannot replace event pack: "+error_string(rename_error)

static func normalize(value):
	# JSON numbers arrive as floats; event parameters are strictly integral.
	if value is float: return int(value)
	if value is Array:
		var result := []
		for item in value: result.append(normalize(item))
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = normalize(value[key])
		return result
	return value

static func with_defaults(data: Dictionary) -> Dictionary:
	var result := fresh(str(data.id))
	result.merge(data,true)
	var stories: Array = [result]+result.get("variants",[])
	for entry in stories:
		if not entry.has("requires"): entry["requires"] = []
		for rule in entry.requires:
			if not rule.has("value"): rule["value"] = 1
			if not rule.has("not"): rule["not"] = false
		for i in range(entry.choices.size()):
			var selected := choice()
			selected.merge(entry.choices[i],true)
			entry.choices[i] = selected
			for j in range(selected.outcomes.size()):
				var outcome_data := outcome()
				outcome_data.merge(selected.outcomes[j],true)
				selected.outcomes[j] = outcome_data
				for k in range(outcome_data.effects.size()):
					var action_data := action(str(outcome_data.effects[k].kind))
					action_data.merge(outcome_data.effects[k],true)
					outcome_data.effects[k] = action_data
	return result

extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const OldAI = preload("res://artifacts/ai-followup-baseline/kingdom_ai.gd")
const NewAI = preload("res://src/game/kingdom_ai.gd")
var results := []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for seed_value in [42,71]:
		for seat in range(4):
			var model = Rules.new()
			model.rule_mode = "modern"
			model.ai_difficulty = "hard"
			model.generate(seed_value,"small",4)
			var timing := {"old":0.0,"new":0.0}
			var preparation_deaths := {"old":0,"new":0}
			var played := 0
			for turn in range(12):
				for faction in range(4):
					var label := "new" if faction == seat else "old"
					var started := Time.get_ticks_usec()
					var ai = NewAI.new(model) if faction == seat else OldAI.new(model)
					var records: Array = ai.ai_turn(faction)
					timing[label] += (Time.get_ticks_usec()-started)/1000.0
					for record in records: preparation_deaths[label] += int(record.get("kind","") == "death")
				played += 1
				var alive := 0
				for faction in range(4): alive += int(model.territory(faction) > 1 or model.has_units(faction))
				if alive <= 1: break
				model.spread_trees()
				await process_frame
			var land := []
			for faction in range(4): land.append(model.territory(faction))
			# Preparation diffs can hide a death followed by a replacement purchase
			# on the same tile. These records are not exact starvation telemetry.
			var result := {"seed":seed_value,"new_seat":seat,"rounds":played,"land":land,"preparation_death_records":preparation_deaths,"timing_ms":timing}
			results.append(result)
			print(JSON.stringify(result))
			FileAccess.open("res://artifacts/ai-followup-matches.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	quit()

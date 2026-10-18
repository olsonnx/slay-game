extends RefCounted
const Level = preload("res://src/editor/level_document.gd")
const Actions = preload("res://src/tutorial_editor/tutorial_actions.gd")
const Conditions = preload("res://src/tutorial_editor/tutorial_conditions.gd")

static func run(document, before := -1) -> Dictionary:
	var error: String = document.validate(document.data)
	if error != "": return {"error":error,"rules":null,"round":1}
	var level := Level.new()
	level.read_data(document.data.map)
	var rules = level.build_rules()
	var round_number := 1
	var steps: Array = document.runtime_steps()
	var count := steps.size() if before < 0 else before
	for index in range(count):
		var step: Dictionary = steps[index]
		var prefix := "Step %d (%s): " % [index+1,step.title]
		if step.kind == "end_turn":
			for faction in range(1,rules.faction_count):
				if document.data.get("opponent_mode","scripted") == "ai": rules.ai_turn(faction)
				else: rules.begin_turn(faction)
				if document.data.get("opponent_mode","scripted") == "scripted":
					for order in step.get("opponent",[]):
						if int(order.get("faction",1)) != faction: continue
						if not Actions.apply(rules,order,faction).ok: return {"error":prefix + "Illegal opponent order: " + str(order),"rules":rules,"round":round_number}
			round_number += 1
			rules.begin_turn(0)
		else:
			var order: Dictionary = step.get("details",{}).duplicate(true)
			order["kind"] = step.kind
			order["target"] = step.target
			var required: String = {"recruit":"tier","build":"building","spell":"spell","move":"source"}.get(step.kind,"")
			if required != "" and not step.get("details",{}).has(required):
				return {"error":prefix + "This action allows multiple choices; use a manual playtest.","rules":rules,"round":round_number}
			if (step.kind in ["recruit","move","build","spell","develop","entrench"] and step.target == rules.NONE) or (step.kind == "move" and order.get("source",rules.NONE) == rules.NONE):
				return {"error":prefix + "Any-tile actions need a manual playtest; preview stopped here.","rules":rules,"round":round_number}
			if not Actions.apply(rules,order,0).ok: return {"error":prefix + "Player action is illegal or unaffordable.","rules":rules,"round":round_number}
		if not Conditions.matches(rules,round_number,step.get("conditions",[]),step.get("condition_mode","all")):
			return {"error":prefix + "Board conditions are not satisfied by this scripted path. Try a manual playtest.","rules":rules,"round":round_number}
	if before < 0 and document.data.get("require_victory",true) and not Conditions.victory(rules): error = "The script ends with an opponent still alive."
	return {"error":error,"rules":rules,"round":round_number}

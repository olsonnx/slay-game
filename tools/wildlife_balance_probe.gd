extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Sizes = preload("res://src/game/map_sizes.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var report := {}
	for size in Sizes.IDS:
		var counts := []
		for seed_value in range(12):
			var rules = Rules.new()
			rules.rule_mode = "modern"
			rules.generate(seed_value,size,6)
			var count := 0
			for cell in rules.cells.values(): count += int(cell.get("lair", "") != "")
			counts.append(count)
		var total := 0
		for count in counts: total += count
		report[size] = {"name":Sizes.spec(size).name,"min":counts.min(),"max":counts.max(),"average":total/12.0,"counts":counts}
	print(JSON.stringify(report))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			var file := FileAccess.open(argument.trim_prefix("--output="),FileAccess.WRITE)
			file.store_string(JSON.stringify(report,"\t")+"\n")
	quit()

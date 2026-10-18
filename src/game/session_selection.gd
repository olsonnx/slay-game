extends RefCounted
## Transient interaction state, deliberately absent from authoritative snapshots.
const NONE := Vector2i(999, 999)
var selected := NONE
var inspected_unit := NONE
var hovered := NONE
var active_hex := NONE
var inspected_hex := NONE
var action_mode := ""
var recruit_tier := 0
var chosen_spell := ""
var valid_targets: Dictionary = {}
var preview_path: Array = []

func reset() -> void:
	selected = NONE
	inspected_unit = NONE
	hovered = NONE
	active_hex = NONE
	inspected_hex = NONE
	action_mode = ""
	recruit_tier = 0
	chosen_spell = ""
	valid_targets.clear()
	preview_path.clear()

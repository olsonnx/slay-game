extends RefCounted
## Terminal phases take precedence over in-flight work. Work is drained before
## scene disposal even if the match completes or cancellation begins mid-command.
enum Phase { READY, PLAYER_PLAYBACK, OPPONENT_TURN, COMPLETED, INSPECTING_RESULTS, CLOSING }
const Catalog = preload("res://src/game/game_catalog.gd")
var rules = preload("res://src/game/kingdom_rules.gd").new()
var names: Array = Catalog.FACTIONS.duplicate()
var colors: Array = Catalog.UI_COLORS.duplicate()
var flags: Dictionary = {}
var online := false
var round_number := 1
var player_faction := 0
var active_faction := 0
var level_number := 1
var tutorial
var initial_level_data: Dictionary = {}
var phase := Phase.READY
var work_active := false
var outcome_reached := false
var departure_active := false
var selection = preload("res://src/game/session_selection.gd").new()

func reset() -> void:
	assert(not work_active, "Drain the current operation before resetting a session")
	phase = Phase.READY
	outcome_reached = false
	departure_active = false
	selection.reset()

func begin_work(player_playback := false) -> void:
	if phase in [Phase.CLOSING, Phase.COMPLETED, Phase.INSPECTING_RESULTS]: return
	work_active = true
	phase = Phase.PLAYER_PLAYBACK if player_playback else Phase.OPPONENT_TURN

func finish_work() -> void:
	work_active = false
	if phase in [Phase.PLAYER_PLAYBACK, Phase.OPPONENT_TURN]:
		phase = Phase.COMPLETED if outcome_reached else Phase.READY

func complete(value := true) -> void:
	outcome_reached = value
	if phase == Phase.CLOSING: return
	if value: phase = Phase.COMPLETED
	elif phase in [Phase.COMPLETED, Phase.INSPECTING_RESULTS]:
		phase = Phase.OPPONENT_TURN if work_active else Phase.READY

func close() -> void:
	phase = Phase.CLOSING

func is_closing() -> bool:
	return phase == Phase.CLOSING

func inspect_results(value: bool) -> void:
	if phase == Phase.CLOSING: return
	if value:
		assert(outcome_reached, "Results inspection requires a completed match")
		phase = Phase.INSPECTING_RESULTS
	elif phase == Phase.INSPECTING_RESULTS:
		phase = Phase.COMPLETED

func interaction_blocked(paused: bool, transitioning: bool, modal_open: bool) -> bool:
	return phase in [Phase.CLOSING, Phase.INSPECTING_RESULTS] or departure_active or paused or transitioning or modal_open

func input_suspended(paused: bool, modal_open: bool) -> bool:
	# Global releases must still be observed during camera/level transitions.
	return phase == Phase.CLOSING or paused or modal_open

func can_navigate(paused: bool, transitioning: bool, modal_open: bool) -> bool:
	# Completed-map inspection allows the camera, while commands stay locked.
	return not input_suspended(paused, modal_open) and not departure_active and not transitioning

func commands_locked(paused: bool, transitioning: bool, modal_open: bool) -> bool:
	return phase != Phase.READY or work_active or outcome_reached or interaction_blocked(paused, transitioning, modal_open)

func is_hotseat() -> bool:
	return rules.human_factions.size() > 1

func active_kingdom(economy = null) -> Dictionary:
	var model = rules if economy == null else economy
	if model.cells.has(selection.active_hex) and model.cells[selection.active_hex]["owner"] == player_faction:
		return model.kingdom_at(selection.active_hex)
	return {}

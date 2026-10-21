extends RefCounted
const Loc = preload("res://src/localization/text.gd")
## Opponent phases, playback and round settlement. State remains in the session.
## Per-call state avoids retaining controllers across cancellation or restart.

static func run(game) -> void:
	if game.is_hotseat():
		await run_hotseat(game)
		return
	if game.commands_locked():
		return
	game.session.begin_work()
	game.camera_follow_suspended = false
	game.session.selection.action_mode = ""
	game.session.selection.selected = game.NONE
	game.session.selection.inspected_unit = game.NONE
	game.session.selection.inspected_animal = game.NONE
	game.hud.shop_panel.close()
	game.close_province()
	game.hud.world_tip.hide()
	game.refresh_ui()
	game.view.unit_presentation.set_turn(-1)
	game.rules.record_replay("turn_end", game.player_faction)
	game.sync_event_factions()
	for faction in game.turn_order.duplicate():
		if faction == game.player_faction: continue
		if game.rules.territory(faction) == 0 and not game.rules.has_units(faction):
			continue
		await play_ai(game, faction)
		if game.closing:
			game.session.finish_work()
			return
		game.check_winner()
		if game.game_over:
			break
	var settlement = game.rules.KingdomAI.new(game.rules)
	settlement.threaded_simulation = game.ai_simulation_workers
	if not game.game_over:
		game.round_number += 1
		await play_world(game, settlement)
		if game.closing:
			game.session.finish_work()
			return
		game.check_winner()
	await finish_player_turn_handoff(game, settlement)

static func finish_player_turn_handoff(game, settlement = null) -> void:
	if settlement == null:
		settlement = game.rules.KingdomAI.new(game.rules)
		settlement.threaded_simulation = game.ai_simulation_workers
	var execution = game.ai_execution()
	game.settling_turn = true
	var started := Time.get_ticks_usec() if game.view.profile_capture else 0
	if not game.game_over:
		var deaths: int = await settlement.begin_turn_async(execution, game.player_faction)
		if game.closing:
			game.settling_turn = false
			game.session.finish_work()
			return
		profile_stage(game, "player_settlement", started)
		if deaths > 0:
			game.announce(Loc.text("%d soldiers starved. Reconnect their land or reduce upkeep.") % deaths)
		started = Time.get_ticks_usec() if game.view.profile_capture else 0
		game.view.unit_batches.budgeted_sync = true
		game.view.dirty_tiles.merge(game.view.unit_presentation.stage_turn(game.player_faction, game.cells))
		game.view.render_cells(settlement.preparation_cells(), settlement.presentation_patch_ready)
		profile_stage(game, "player_render", started)
		# Publish sprite state, then drain instance uploads over subsequent frames.
		await execution.next_frame()
		await game.view.unit_batches.wait_for_sync(execution)
		game.view.unit_batches.budgeted_sync = false
		if game.closing:
			game.settling_turn = false
			game.session.finish_work()
			return
	game.settling_turn = false
	game.session.finish_work()
	game.active_faction = game.player_faction
	game.playback_kingdoms.clear()
	game.playback_mana.clear()
	started = Time.get_ticks_usec() if game.view.profile_capture else 0
	game.refresh_ui()
	profile_stage(game, "player_ui", started)
	started = Time.get_ticks_usec() if game.view.profile_capture else 0
	game.follow_active_faction()
	game.begin_completion_exit()
	profile_stage(game, "player_camera", started)

static func profile_stage(game, stage: String, started: int) -> void:
	if game.view.profile_capture:
		game.view.record_capture_sample({"stage":stage, "ms":(Time.get_ticks_usec() - started) / 1000.0})

static func play_ai(game, faction: int) -> void:
	game.active_faction = faction
	if not game.initial_match_config.is_empty():
		game.rules.ai_difficulty = game.initial_match_config["slots"][faction]["difficulty"] if faction < game.initial_match_config["slots"].size() else game.initial_difficulty
	game.follow_active_faction()
	game.refresh_ui()
	game.faction_started.emit(faction)
	game.playback_kingdoms = game.rules.kingdoms.duplicate(true)
	game.playback_mana = game.rules.mana_by_faction.duplicate()
	var opponent = game.rules.KingdomAI.new(game.rules)
	opponent.threaded_simulation = game.ai_simulation_workers
	var preparation: Array = await opponent.prepare_async(game.ai_execution(), faction)
	if game.closing:
		game.session.finish_work()
		return
	await game.view.play_preparation(preparation, opponent.preparation_cells(), opponent.presentation_patch_ready)
	if game.closing:
		game.session.finish_work()
		return
	game.playback_kingdoms = game.rules.kingdoms.duplicate(true)
	game.playback_mana = game.rules.mana_by_faction.duplicate()
	var movements: Array = await opponent.movements_async(game.ai_execution(), faction)
	if game.closing:
		game.session.finish_work()
		return
	while not movements.is_empty():
		await game.view.animate_moves(movements, opponent.movement_cells(movements))
		if game.closing:
			game.session.finish_work()
			return
		game.playback_kingdoms = game.rules.kingdoms.duplicate(true)
		game.playback_mana = game.rules.mana_by_faction.duplicate()
		movements = await opponent.movements_async(game.ai_execution(), faction)
		if game.closing:
			game.session.finish_work()
			return
	# A brief pause makes even a faction with no legal moves identifiable.
	var pause_between = game.view.playback.scaled_tween(game)
	pause_between.tween_interval(0.18)
	await pause_between.finished
	if game.closing:
		game.session.finish_work()
		return
	game.sync_event_factions()
	game.view.render_cells(game.cells)
	game.view.unit_presentation.set_turn(-1)
	game.faction_finished.emit(faction)
	game.rules.record_replay("turn_end", faction)

static func run_hotseat(game) -> void:
	if game.commands_locked():
		return
	game.rules.record_replay("turn_end", game.active_faction)
	game.view.unit_presentation.set_turn(-1)
	game.faction_finished.emit(game.active_faction)
	game.session.begin_work()
	game.camera_follow_suspended = false
	game.close_menus()
	game.session.selection.selected = game.NONE
	game.session.selection.action_mode = ""
	game.session.selection.inspected_unit = game.NONE
	game.session.selection.inspected_animal = game.NONE
	game.check_winner()
	while not game.game_over and not game.closing:
		var index: int = (game.turn_order.find(game.active_faction) + 1) % game.turn_order.size()
		var faction: int = game.turn_order[index]
		if index == 0:
			game.round_number += 1
			await play_world(game)
			if game.closing: break
			game.check_winner()
			if game.game_over: break
		game.active_faction = faction
		# A stranded army still receives settlement so it can starve normally.
		if game.rules.territory(faction) == 0 and not game.rules.has_units(faction):
			continue
		if faction in game.rules.human_factions:
			game.player_faction = faction
			var settlement = game.rules.KingdomAI.new(game.rules)
			settlement.threaded_simulation = game.ai_simulation_workers
			game.settling_turn = true
			var execution = game.ai_execution()
			var deaths: int = await settlement.begin_turn_async(execution, faction)
			if game.closing:
				game.settling_turn = false
				break
			game.view.unit_batches.budgeted_sync = true
			game.view.dirty_tiles.merge(game.view.unit_presentation.stage_turn(faction, game.cells))
			game.view.render_cells(settlement.preparation_cells(), settlement.presentation_patch_ready)
			await execution.next_frame()
			await game.view.unit_batches.wait_for_sync(execution)
			game.view.unit_batches.budgeted_sync = false
			game.settling_turn = false
			if game.closing: break
			game.session.finish_work()
			game.playback_kingdoms.clear()
			game.playback_mana.clear()
			game.begin_local_turn()
			if deaths > 0:
				game.announce(Loc.text("%d soldiers starved in %s.") % [deaths, game.NAMES[faction]])
			game.faction_started.emit(faction)
			return
		await play_ai(game, faction)
		if game.closing:
			game.session.finish_work()
			return
		game.check_winner()
	game.session.finish_work()
	game.refresh_ui()
	game.begin_completion_exit()

static func play_world(game, settlement = null) -> void:
	if settlement == null:
		settlement = game.rules.KingdomAI.new(game.rules)
		settlement.threaded_simulation = game.ai_simulation_workers
	var started := Time.get_ticks_usec() if game.view.profile_capture else 0
	game.playback_kingdoms = game.rules.kingdoms.duplicate(true)
	game.playback_mana = game.rules.mana_by_faction.duplicate()
	game.hud.round_label.text = Loc.text("World") + " / " + Loc.text("Turn %d") % game.round_number
	var actions: Array = await settlement.world_async(game.ai_execution())
	if game.closing: return
	profile_stage(game, "world_rules", started)
	started = Time.get_ticks_usec() if game.view.profile_capture else 0
	game.settling_turn = true
	await game.view.wildlife.play_world(actions,settlement.preparation_cells(),settlement.presentation_patch_ready)
	game.settling_turn = false
	profile_stage(game, "world_presentation", started)
	if game.closing: return
	game.playback_kingdoms = game.rules.kingdoms.duplicate(true)
	game.playback_mana = game.rules.mana_by_faction.duplicate()

extends RefCounted
const Loc = preload("res://src/localization/text.gd")
## Player command execution and cancellable movement playback.
## State and scene lifetime remain owned by the supplied controller.

func click_hex(game, coord: Vector2i, hit_kind := "auto") -> void:
	if game.interaction_blocked():
		return
	if game.session.selection.action_mode == "bridge" and not game.busy and not game.game_over and not game.cells.has(coord) and game.session.selection.valid_targets.has(coord):
		if not game.tutorial_permits("build",coord,{"building":"bridge"}): return
		if game.rules.build_structure(coord, game.player_faction, "bridge", game.active_capital()):
			game.session.selection.action_mode = ""
			game.view.render_cells(game.cells)
			game.view.action_marker(coord, Color("c39a65"))
			Sound.play(&"action_place")
			game.announce(Loc.text("Wooden bridge built. All kingdoms can cross it."))
			game.refresh_ui()
			game.report_tutorial_action("build",coord,{"building":"bridge"})
		return
	if not game.cells.has(coord):
		game.cancel_action()
		return
	var unit_clicked: bool = hit_kind == "unit" or (hit_kind == "auto" and game.view.cells.get(coord, {}).get("unit", 0) > 0)
	var animal_clicked: bool = hit_kind == "wildlife" or (hit_kind == "auto" and game.view.cells.get(coord, {}).get("animal", "") != "")
	var completed_mode: String = game.session.selection.action_mode
	var completed_spell: String = game.session.selection.chosen_spell
	var completed_tier: int = game.session.selection.recruit_tier
	if game.tutorial != null and game.busy: return
	if game.session.selection.action_mode == "spell" and not game.tutorial_permits("spell",coord,{"spell":game.session.selection.chosen_spell}): return
	if game.session.selection.action_mode == "recruit" and not game.tutorial_permits("recruit",coord,{"tier":game.session.selection.recruit_tier}): return
	if game.session.selection.action_mode in ["tower","house"] and not game.tutorial_permits("build",coord,{"building":game.session.selection.action_mode}): return
	if game.session.selection.action_mode == "" and game.session.selection.selected != coord and game.session.selection.valid_targets.has(coord) and not game.tutorial_permits("move",coord,{"source":game.session.selection.selected}): return
	game.session.selection.inspected_unit = game.NONE
	game.session.selection.inspected_animal = game.NONE
	if unit_clicked or animal_clicked:
		game.close_province()
	if game.busy or game.game_over:
		if game.rules.is_modern() and not unit_clicked and not animal_clicked:
			game.inspect_province(coord)
		return
	game.hud.shop_panel.close()
	if game.session.selection.action_mode == "" and game.cells[coord]["owner"] == game.player_faction:
		game.session.selection.active_hex = coord
	elif game.session.selection.action_mode == "" and unit_clicked and game.rules.unit_faction(coord) == game.player_faction:
		game.session.selection.active_hex = game.rules.unit_kingdom(coord).get("capital", game.session.selection.active_hex)
	var changed := false
	var recruited := false
	var cast := false
	if game.session.selection.action_mode == "spell":
		var shielded: bool = game.cells[coord].get("fortified", false)
		changed = game.rules.cast_spell(game.session.selection.chosen_spell, coord, game.player_faction, game.active_capital())
		cast = changed
		if changed:
			Sound.play(&"action_place")
			game.session.selection.action_mode = ""
			if game.session.selection.chosen_spell == "summon":
				game.session.selection.selected = coord
			game.announce(Loc.text("Fortification absorbed Shatter.") if game.session.selection.chosen_spell == "shatter" and shielded else game.Spells.SPELLS[game.session.selection.chosen_spell]["message"])
		else:
			game.announce(Loc.text("Choose a highlighted target with enough faction mana."))
	elif game.session.selection.action_mode == "recruit":
		changed = game.rules.recruit(coord, game.player_faction, game.session.selection.recruit_tier, game.active_capital())
		recruited = changed
		if changed:
			Sound.play(&"action_place")
			game.session.selection.selected = coord
			game.session.selection.action_mode = ""
			game.announce(Loc.text("%s ready to move.") % Loc.text(game.UNIT_NAMES[game.cells[coord]["unit"]]))
		else:
			game.announce(Loc.text("Choose a valid hex with enough gold in its kingdom."))
	elif game.session.selection.action_mode in ["tower", "house"]:
		changed = game.rules.build_structure(coord, game.player_faction, game.session.selection.action_mode, game.active_capital())
		if changed:
			Sound.play(&"action_place")
			game.announce(Loc.text("%s built.") % game.session.selection.action_mode.capitalize())
			game.session.selection.action_mode = ""
		else:
			game.announce(Loc.text("Choose a clear empty hex with enough local gold."))
	elif game.session.selection.selected != coord and game.session.selection.valid_targets.has(coord):
		game.close_province()
		game.player_move_snapshot = preload("res://src/game/state_snapshot.gd").capture(game.rules)
		game.player_move_snapshot["active_hex"] = game.session.selection.active_hex
		game.player_move_revision += 1
		var revision: int = game.player_move_revision
		if game.rules.replay_log != null: game.rules.replay_log.begin_transaction()
		var action: Dictionary = game.rules.perform_move(game.session.selection.selected, coord)
		if action.is_empty():
			if game.rules.replay_log != null: game.rules.replay_log.cancel_transaction()
			game.player_move_snapshot.clear()
			return
		game.session.begin_work(true)
		Sound.play(&"ui_click")
		game.session.selection.active_hex = action.get("payer_capital", game.session.selection.active_hex) if game.rules.is_bridge(coord) or action["kind"] in ["blocked_attack", "knight_duel"] else coord
		game.session.selection.selected = game.NONE
		game.refresh_ui()
		await game.view.animate_moves([action], game.cells)
		if game.closing:
			game.session.finish_work()
			return
		if revision != game.player_move_revision:
			return
		if game.rules.replay_log != null: game.rules.replay_log.commit_transaction()
		game.player_move_snapshot.clear()
		game.session.finish_work()
		if game.cells[coord]["unit"] > 0 and not game.cells[coord]["moved"]:
			game.session.selection.selected = coord
		if action["kind"] == "blocked_attack":
			game.announce(Loc.text("Entrenchment absorbed the hit. The attacker has spent its move.") if action["before_target"].get("entrenched_by", -1) >= 0 else Loc.text("Fortification absorbed the hit. The attacker has spent its move."))
		elif action["kind"] == "knight_duel":
			game.announce(Loc.text("Both Knights fell. Territory remains unchanged."))
		elif action.get("lair_reward", "") != "":
			game.announce(Loc.text("Lair destroyed: %s") % Loc.text(game.rules.Wildlife.DEFINITIONS[action.lair_reward].reward))
		elif action["before_target"].get("treasure", 0) > 0 and action["capture"]:
			game.announce(Loc.text("Treasure collected · +%d G to your kingdom.") % action["before_target"]["treasure"])
		game.show_next_event()
		if not game.event_shade.visible:
			game.check_winner()
		game.refresh_ui()
		game.report_tutorial_action("move",coord,action)
		return
	elif animal_clicked and game.session.selection.action_mode == "":
		Sound.play(&"ui_click")
		game.session.selection.selected = game.NONE
		game.session.selection.inspected_animal = coord
	elif game.cells[coord]["owner"] == game.player_faction or game.cells[coord]["unit"] > 0 and game.rules.unit_faction(coord) == game.player_faction:
		if unit_clicked or not game.rules.is_modern():
			Sound.play(&"ui_click")
		game.session.selection.selected = coord if unit_clicked and game.cells[coord]["unit"] > 0 else game.NONE
		if game.rules.unit_kingdom(coord).is_empty() and game.cells[coord]["kingdom"] == game.NONE:
			game.announce(Loc.text("Isolated land. Reconnect it before its soldiers starve."))
		elif unit_clicked and game.cells[coord]["unit"] > 0 and game.cells[coord]["moved"]:
			game.announce(Loc.text("This unit has already moved."))
	else:
		if unit_clicked or not game.rules.is_modern():
			Sound.play(&"ui_click")
		game.session.selection.selected = game.NONE
		if unit_clicked and game.session.selection.action_mode == "" and game.cells[coord]["unit"] > 0:
			game.session.selection.inspected_unit = coord
	if changed:
		game.view.render_cells(game.cells)
		if recruited:
			game.view.spawn_unit_effect(coord, game.cells[coord]["unit"])
		elif cast and completed_spell == "summon":
			game.view.spawn_unit_effect(coord, game.cells[coord]["unit"])
		elif cast:
			game.view.action_marker(coord, Color("bda2fa"))
	if game.rules.is_modern() and not unit_clicked and not animal_clicked and not changed and game.session.selection.action_mode == "":
		game.inspect_province(coord)
	elif not game.rules.is_modern() and not unit_clicked and not animal_clicked and not changed and game.session.selection.action_mode == "":
		game.session.selection.inspected_hex = coord if game.cells[coord].building == "tower" else game.NONE
	game.check_winner()
	game.refresh_ui()
	if changed:
		if completed_mode == "recruit": game.report_tutorial_action("recruit",coord,{"tier":completed_tier})
		elif completed_mode == "spell": game.report_tutorial_action("spell",coord,{"spell":completed_spell})
		else: game.report_tutorial_action("build",coord,{"building":completed_mode})
	elif unit_clicked and game.session.selection.selected == coord:
		game.report_tutorial_action("select",coord)


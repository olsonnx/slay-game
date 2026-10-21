extends SceneTree

const Document = preload("res://src/editor/level_document.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func run() -> void:
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.get_node("Sound").set_muted(true, false)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.open_editor()
	for mode in ["modern", "classic"]:
		for enemy in [0, 1]:
			for victory in [false, true]:
				var doc = app.editor.document
				doc.generate("small", mode, true)
				expect(doc.playable_error() != "", "An entirely blank draft requires land before playtesting")
				for q in [0, 1, 4, 5]: doc.paint(Vector2i(q, 0), "Land", 11 if q < 2 else enemy, 1)
				doc.paint(Vector2i.ZERO, "Player start", 11, 1)
				doc.factions[11]["name"] = "Custom player"
				expect(doc.playable_error() == "", "Hand-painted blank map validates with a nonzero player kingdom")
				var draft: Dictionary = doc.state()
				await app.play_editor_level(draft)
				var game = app.game
				expect(game.player_faction == 11 and game.rules.human_factions == [11], "Playtest controls the kingdom selected by Player start")
				game.check_winner()
				expect(not game.game_over and not paused, "Authored player and surviving opponent keep the playtest running")
				# Stop after reproducing an early outcome so result state cannot mask it.
				if game.game_over:
					await app.return_to_main_menu()
					continue
				for cell in game.cells.values():
					if cell["owner"] == (enemy if victory else 11):
						cell["owner"] = -1
						cell["capital"] = -1
						cell["unit"] = 0
				game.check_winner()
				expect(game.game_over and paused, "Actual victory or loss ends the authored game")
				expect(app.menus.defeat_title.text == ("Victory" if victory else "Defeat"), "Results title follows the selected player's outcome")
				expect(game.message == ("Victory for Custom player!" if victory else "Your kingdom has fallen."), "Victory announcement uses the authored kingdom's name")
				var result: Dictionary = game.rules.replay_log.rows[-1]["args"]
				expect(result["winner"] == (11 if victory else -1) and result["result"] == ("victory" if victory else "defeat"), "Replay stores the actual player's outcome and winner")
				await app.return_to_main_menu()
				expect(app.editor.document.state() == draft and not app.editor.suspended, "Returning from playtest preserves the blank-map draft")
	app.queue_free()
	await process_frame
	print("Editor outcome checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

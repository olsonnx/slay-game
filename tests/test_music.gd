extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var controls = load("res://src/ui/music_controls.gd").new()
	root.add_child(controls)
	var music = controls.music
	for path in music.TRACKS:
		var stream = load(path)
		expect(stream is AudioStreamOggVorbis and stream.get_length() > 0 and not stream.loop, "Playlist tracks decode and can finish for automatic advancement")
	expect(music.player.playing and music.player.bus == &"Music", "Playlist starts through its dedicated volume bus")
	expect(music.track_title() == "New frontiers" and not controls.panel.visible, "Player starts collapsed with the first track")
	controls.toggle.button_pressed = true
	expect(controls.panel.visible, "Music icon opens the small player")
	var loading = load("res://src/ui/preparation_screen.gd").new()
	root.add_child(loading)
	expect(not controls.visible and not controls.panel.visible and music.player.playing, "Loading hides and closes controls while music continues")
	var overlapping = load("res://src/ui/preparation_screen.gd").new()
	root.add_child(overlapping)
	loading.free()
	expect(not controls.visible, "Controls stay hidden until every loading screen leaves")
	overlapping.free()
	expect(controls.visible, "Controls return after loading ends")
	controls.toggle.button_pressed = true
	controls.pause_button.pressed.emit()
	expect(music.paused and music.player.stream_paused, "Pause suspends playback without losing the track")
	var stopped_at: float = music.player.get_playback_position()
	await create_timer(0.1).timeout
	expect(is_equal_approx(music.player.get_playback_position(), stopped_at), "Paused playback position does not advance")
	controls.next_button.pressed.emit()
	expect(music.track_index == 1 and music.paused and music.player.stream_paused and controls.title.text == "Crossing bridges", "Skip updates the title and preserves paused playback")
	controls.pause_button.pressed.emit()
	paused = true
	expect(not music.player.stream_paused and music.can_process(), "Music and controls continue while the match is paused")
	paused = false
	for i in range(music.TRACKS.size()-2): music.next_track()
	expect(music.track_title() == "Hall of the hexian king", "All eight supplied songs appear in the playlist")
	music.player.finished.emit()
	expect(music.track_index == 0 and music.player.playing, "Track completion advances and wraps the playlist")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	controls._input(escape)
	expect(not controls.panel.visible and not controls.toggle.button_pressed, "Escape closes and synchronizes the player button")
	controls.queue_free()
	await process_frame
	# Let the audio mixer release the old compressed streams before shutdown.
	await create_timer(1.2).timeout
	print("Music checks: %d passed, %d failed" % [checks-failures, failures])
	quit(1 if failures else 0)

extends SceneTree
## Read-only benchmark against recordings in the selected user-data directory.
const Replay = preload("res://src/game/replay_log.gd")
const Timeline = preload("res://src/game/replay_timeline.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var directory := DirAccess.open(Replay.DIRECTORY)
	var samples: Array = []
	if directory != null:
		for filename in directory.get_files():
			if filename.get_extension() != "jsonl": continue
			var started := Time.get_ticks_usec()
			var data := Replay.read_replay(Replay.DIRECTORY.path_join(filename), true)
			var read_ms := (Time.get_ticks_usec() - started) / 1000.0
			var timeline := Timeline.new()
			started = Time.get_ticks_usec()
			var error := timeline.open(data)
			var open_ms := (Time.get_ticks_usec() - started) / 1000.0
			started = Time.get_ticks_usec()
			for index in range(20): timeline.seek(timeline.steps.size() - 1 if index % 2 == 0 else timeline.steps.size() / 2)
			var sample := {"file":filename,"error":error,"commands":timeline.commands.size(),"read_ms":read_ms,"open_ms":open_ms,"seek_average_ms":(Time.get_ticks_usec()-started)/20000.0}
			samples.append(sample)
			print(JSON.stringify(sample))
	var file := FileAccess.open("res://artifacts/replay-loading-probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(samples, "\t"))
	quit()

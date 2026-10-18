extends Node
## Central, bounded, non-spatial one-shot playback. Game code refers only to cue IDs.
signal sound_started(id: StringName, voice: int)
signal settings_changed
signal settings_save_failed(error: Error)

const DEFAULT_BANK = preload("res://resources/audio/sounds.tres")
const SETTINGS_PATH := "user://audio_settings.cfg"
const VOICE_COUNT := 12
const BUSES := [&"Master", &"UI", &"SFX", &"Music", &"Ambience"]

var bank: Resource = DEFAULT_BANK
var load_saved_settings := true
var settings_path := SETTINGS_PATH
var voices: Array[AudioStreamPlayer] = []
var last_played: Dictionary = {}
var sequence := 0
var rng := RandomNumberGenerator.new()
var save_timer: Timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	save_timer = Timer.new()
	save_timer.one_shot = true
	save_timer.wait_time = 0.25
	save_timer.timeout.connect(flush_settings)
	add_child(save_timer)
	for index in range(VOICE_COUNT):
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % index
		voice.set_meta("cue", &"")
		voice.set_meta("priority", -1)
		voice.set_meta("sequence", 0)
		add_child(voice)
		voices.append(voice)
	if load_saved_settings:
		load_settings(settings_path)

func play(id: StringName) -> bool:
	if not bank.cues.has(id):
		push_warning("Unknown sound cue: %s" % id)
		return false
	var cue: Resource = bank.cues[id]
	if cue.streams.is_empty() or AudioServer.get_bus_index(cue.bus) < 0:
		return false
	if is_muted() or get_volume(&"Master") < 0.0001 or get_volume(cue.bus) < 0.0001 or AudioServer.is_bus_mute(AudioServer.get_bus_index(cue.bus)):
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_played.get(id, -100.0) < cue.cooldown_seconds:
		return false
	var matching: Array[AudioStreamPlayer] = []
	var idle: AudioStreamPlayer
	var candidate: AudioStreamPlayer
	for voice in voices:
		if not voice.playing:
			if idle == null:
				idle = voice
			continue
		if voice.get_meta("cue") == id:
			matching.append(voice)
		if candidate == null or voice.get_meta("priority") < candidate.get_meta("priority") or (voice.get_meta("priority") == candidate.get_meta("priority") and voice.get_meta("sequence") < candidate.get_meta("sequence")):
			candidate = voice
	var chosen := idle
	if matching.size() >= cue.max_voices:
		if not cue.replace_oldest:
			return false
		chosen = matching[0]
		for voice in matching:
			if voice.get_meta("sequence") < chosen.get_meta("sequence"):
				chosen = voice
	elif chosen == null:
		if candidate == null or candidate.get_meta("priority") > cue.priority:
			return false
		chosen = candidate
	chosen.stop()
	chosen.stream = cue.streams[rng.randi_range(0, cue.streams.size() - 1)]
	chosen.bus = cue.bus
	chosen.volume_db = cue.volume_db
	chosen.pitch_scale = rng.randf_range(minf(cue.pitch_min, cue.pitch_max), maxf(cue.pitch_min, cue.pitch_max))
	chosen.set_meta("cue", id)
	chosen.set_meta("priority", cue.priority)
	sequence += 1
	chosen.set_meta("sequence", sequence)
	last_played[id] = now
	chosen.play()
	sound_started.emit(id, voices.find(chosen))
	return true

func stop_all() -> void:
	for voice in voices:
		voice.stop()
		voice.stream = null
	last_played.clear()

func _exit_tree() -> void:
	if is_instance_valid(save_timer) and not save_timer.is_stopped():
		flush_settings()
	for voice in voices:
		voice.stop()
		voice.stream = null
	voices.clear()

func bind_button(button: BaseButton, activate: Callable = Callable()) -> void:
	if button.has_meta("audio_bound"):
		return
	button.set_meta("audio_bound", true)
	button.mouse_entered.connect(func():
		if not button.disabled:
			play(&"ui_hover"))
	button.pressed.connect(func():
		if button.disabled:
			return
		var id: StringName = activate.call() if activate.is_valid() else &"ui_click"
		if id != &"":
			play(id))

func get_volume(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return 0.0
	var decibels := AudioServer.get_bus_volume_db(index)
	return 0.0 if decibels <= -79.9 else db_to_linear(decibels)

func set_volume(bus: StringName, value: float, persist := true) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	var volume := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(volume) if volume > 0 else -80.0)
	if persist:
		save_timer.start()
	settings_changed.emit()

func set_muted(muted: bool, persist := true) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), muted)
	if muted:
		stop_all()
	if persist:
		save_timer.start()
	settings_changed.emit()

func is_muted() -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master"))

func flush_settings() -> Error:
	save_timer.stop()
	var error := save_settings(settings_path)
	if error != OK:
		settings_save_failed.emit(error)
	return error

func save_settings(path := SETTINGS_PATH) -> Error:
	var config := ConfigFile.new()
	for bus in BUSES:
		config.set_value("volume", bus, get_volume(bus))
	config.set_value("audio", "muted", is_muted())
	return config.save(path)

func load_settings(path := SETTINGS_PATH) -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return error
	for bus in BUSES:
		if config.has_section_key("volume", bus):
			var value = config.get_value("volume", bus)
			if value is float or value is int:
				set_volume(bus, float(value), false)
	var muted = config.get_value("audio", "muted", false)
	if muted is bool:
		set_muted(muted, false)
	return OK

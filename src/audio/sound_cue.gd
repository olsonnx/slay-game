extends Resource
## One reusable cue; variants and mixing rules are editable in the Inspector.
@export var streams: Array[AudioStream] = []
@export var bus: StringName = &"SFX"
@export_range(-60, 6) var volume_db := -6.0
@export_range(0.5, 2.0) var pitch_min := 1.0
@export_range(0.5, 2.0) var pitch_max := 1.0
@export_range(0, 2) var cooldown_seconds := 0.04
@export_range(1, 16) var max_voices := 3
@export var replace_oldest := true
@export_range(0, 100) var priority := 20

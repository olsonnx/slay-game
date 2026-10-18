extends RefCounted
## Monotonic wall time: independent of animation speed and Engine.time_scale.
var accumulated_usec := 0
var running_since := -1

func reset(running := true) -> void:
	accumulated_usec = 0
	running_since = Time.get_ticks_usec() if running else -1

func resume() -> void:
	if running_since < 0: running_since = Time.get_ticks_usec()

func pause() -> void:
	if running_since < 0: return
	accumulated_usec += Time.get_ticks_usec() - running_since
	running_since = -1

func seconds() -> int:
	return int((accumulated_usec + (Time.get_ticks_usec() - running_since if running_since >= 0 else 0)) / 1000000)

static func display(seconds_value: int) -> String:
	return "%02d:%02d:%02d" % [seconds_value / 3600, seconds_value / 60 % 60, seconds_value % 60]

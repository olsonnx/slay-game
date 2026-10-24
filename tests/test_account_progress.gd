extends SceneTree
const Progress = preload("res://src/settings/account_progress.gd")
const Store = preload("res://src/settings/player_profile.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	expect(Progress.progress(0) == {"level":1,"current":0,"needed":250,"total":0}, "Accounts begin at level one")
	for level in range(2, 100):
		var boundary: int = Progress.threshold(level)
		expect(Progress.progress(boundary - 1).level == level - 1 and Progress.progress(boundary).level == level and Progress.progress(boundary).current == 0, "Level boundaries use exact cumulative XP")
	expect(Progress.progress(600).needed == 450, "Later levels require progressively more XP")
	var base := {"difficulty":"normal", "size":"small", "opponents":1}
	var normal: int = Progress.reward("victory", base)
	expect(normal == 150 and Progress.reward("defeat", base) == 75 and Progress.reward("draw", base) == 100, "Completed matches earn outcome-dependent XP")
	for variant in [{"difficulty":"hard"}, {"size":"huge"}, {"opponents":5}]:
		var settings: Dictionary = base.merged(variant, true)
		expect(Progress.reward("victory", settings) > normal, "Greater match challenges earn more XP")
	expect(Progress.reward("victory", base.merged({"difficulty":"easy"}, true)) < normal, "Easy AI earns less than normal AI")
	var mixed := base.merged({"owner":1, "slots":[{"controller":"ai","difficulty":"hard"}, {"controller":"human","difficulty":"easy"}, {"controller":"human","difficulty":"easy"}]}, true)
	expect(Progress.reward("victory", mixed) == 180, "Mixed lobbies average actual opponent settings and use normal weight for human opponents")
	expect(Progress.reward("abandoned", base) == 0, "Unfinished outcomes have no XP reward")
	var store := Store.new()
	store.settings_path = "res://artifacts/test-account-progress.cfg"
	var identity := Store.default_identity()
	identity.name = "Progress test"
	expect(store.save_identity(identity) == OK, "Progress fixture saves to isolated storage")
	expect(store.record_match("first", "victory", 120, 4, base) == OK and store.statistics.xp == 150, "XP saves with the completed match")
	store.record_match("first", "victory", 120, 4, base)
	expect(store.statistics.xp == 150, "Repeated completion cannot award XP twice")
	var reloaded := Store.new()
	expect(reloaded.load_settings(store.settings_path) == OK and reloaded.statistics.xp == 150, "XP survives profile reload")
	var previous := store.statistics.duplicate(true)
	store.settings_path = "res://artifacts/nonexistent-xp-folder/profile.cfg"
	expect(store.record_match("failed", "victory", 120, 4, base) != OK and store.statistics == previous and "failed" not in store.recorded_matches, "Failed saves roll back XP and leave the completion retryable")
	var old_profile := ConfigFile.new()
	old_profile.set_value("profile", "identity", reloaded.data)
	old_profile.set_value("profile", "statistics", {"matches":5,"wins":3})
	old_profile.save("res://artifacts/test-pre-xp-profile.cfg")
	expect(reloaded.load_settings("res://artifacts/test-pre-xp-profile.cfg") == OK and reloaded.statistics.matches == 5 and reloaded.statistics.xp == 0, "Existing profiles preserve their record and start at level one")
	store.free()
	reloaded.free()
	print("Account progress checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

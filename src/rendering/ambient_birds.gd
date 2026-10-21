extends Node3D
## Three independent decorative birds, isolated from gameplay state and RNG.
const SHEET = preload("res://assets/neutrals/MiniBird.png")
const PALETTE := [Color("ad8860"), Color("8195a4"), Color("d7cfb2"), Color("b8785c")]
const MAX_BIRDS := 3
const LAND_SECONDS := 0.85
const HEAD_WAIT_ROUNDS := 3
# Helmet anchors relative to each cropped sprite centre, in source pixels.
const HEAD_ANCHORS := [[],
	[Vector2(-1, 4), Vector2(-1, 3), Vector2(-1, 3), Vector2(-1, 4)],
	[Vector2(0, 4), Vector2(0, 3), Vector2(0, 3), Vector2(0, 4)],
	[Vector2(0, 2), Vector2(0, 2), Vector2(0, 2), Vector2(0, 2), Vector2(0, 2), Vector2(0, 2), Vector2(0, 2), Vector2(0, 2)]]
static var shared_textures: Array[Texture2D] = []
const OFFSETS := [Vector3(-0.43, 0.34, 0.35), Vector3(0.02, 0.34, 0.57), Vector3(0.45, 0.34, 0.28)]
var board
var rng := RandomNumberGenerator.new()
var flocks: Array[Dictionary] = []
var textures: Array[Texture2D] = []
var round_number := 1
var stationary_units: Dictionary = {}
var loading := false
var tracking_required := true

func _init(view) -> void:
	board = view
	name = "AmbientBirds"
	rng.seed = 45437

func _ready() -> void:
	hide()
	process_priority = 10 # Follow the unit presentation clock in the same frame.
	if not shared_textures.is_empty():
		textures = shared_textures
		return
	# Preserve the dark outline and golden beak while recolouring the feathers.
	var source := SHEET.get_image()
	for color in PALETTE:
		var image := source.duplicate() as Image
		image.convert(Image.FORMAT_RGBA8)
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var pixel := image.get_pixel(x, y)
				if pixel.a < 0.1 or pixel.get_luminance() < 0.17: continue
				if pixel.r > 0.85 and pixel.g > 0.60: continue
				var shade := (pixel.get_luminance() - 0.4) * 1.4
				var feather: Color = color.lightened(shade) if shade > 0.0 else color.darkened(-shade)
				feather.a = pixel.a
				image.set_pixel(x, y, feather)
		textures.append(ImageTexture.create_from_image(image))
	shared_textures = textures

func set_loading(value: bool) -> void:
	loading = value
	update_visibility()

func update_visibility() -> void:
	visible = board.active and not board.level_transitioning and not loading

func clear() -> void:
	tracking_required = true
	hide()
	for flock in flocks:
		var root: Node3D = flock["root"]
		remove_child(root)
		root.queue_free()
	flocks.clear()
	stationary_units.clear()
	round_number = 1
	rng.seed = 45437

func eligible(coord: Vector2i) -> bool:
	return ground_eligible(coord) or head_eligible(coord)

func ground_eligible(coord: Vector2i) -> bool:
	var cell: Dictionary = board.cells.get(coord, {})
	if cell.is_empty(): return false
	return cell.get("unit", 0) == 0 and cell.get("capital", -1) < 0 and cell.get("building", "") == "" \
		and not cell.get("mountain", false) and not cell.get("grave", false) and not cell.get("mana_source", false) \
		and not cell.get("fortified", false) and cell.get("entrenched_by", -1) < 0 and cell.get("barrier_by", -1) < 0 \
		and cell.get("event", "") == "" and cell.get("treasure", 0) == 0 and cell.get("animal", "") == "" and cell.get("lair", "") == ""

func track_units() -> void:
	var scope: Dictionary = {} if tracking_required else board.visible_change_coords
	tracking_required = false
	if scope.is_empty():
		for coord in stationary_units.keys():
			if not board.unit_actors.has(coord): stationary_units.erase(coord)
	for coord in board.unit_actors if scope.is_empty() else scope:
		var actor: Node3D = board.unit_actors.get(coord)
		var cell: Dictionary = board.cells.get(coord, {})
		if not is_instance_valid(actor) or cell.get("unit", 0) == 0 or board.active_motions.has(coord):
			stationary_units.erase(coord)
			continue
		var identity := [actor.get_instance_id(), cell["unit"], cell.get("unit_owner", -1) if cell.get("building", "") == "bridge" else cell.get("owner", -1)]
		if stationary_units.get(coord, {}).get("identity", []) != identity:
			stationary_units[coord] = {"identity":identity, "since":round_number}

func head_eligible(coord: Vector2i) -> bool:
	if not stationary_units.has(coord) or board.active_motions.has(coord): return false
	var actor: Node3D = board.unit_actors.get(coord)
	return (is_instance_valid(actor)
		and not actor.get_meta("sprite_action_active", false)
		and board.cells.get(coord, {}).get("unit", 0) > 0
		and round_number - int(stationary_units[coord]["since"]) >= HEAD_WAIT_ROUNDS)

func unit_departing(coord: Vector2i) -> void:
	stationary_units.erase(coord)
	scatter(coord)

func perch_valid(resident: Dictionary) -> bool:
	var coord: Vector2i = resident["coord"]
	if resident.get("head_actor", 0) == 0: return ground_eligible(coord)
	var actor: Node3D = board.unit_actors.get(coord)
	return head_eligible(coord) and is_instance_valid(actor) and actor.get_instance_id() == resident["head_actor"]

func perch_offset(resident: Dictionary) -> Vector3:
	if resident.get("head_actor", 0) == 0: return resident["offset"]
	var coord: Vector2i = resident["coord"]
	var actor: Node3D = board.unit_actors.get(coord)
	if not is_instance_valid(actor): return resident["offset"]
	var animator = actor.get_node("UnitAnimation")
	var sprite: Sprite3D = animator.sprite
	var anchors: Array = HEAD_ANCHORS[animator.tier]
	var anchor: Vector2 = anchors[posmod(animator.frame_index, anchors.size())]
	var right: Vector3 = board.camera.global_basis.x * anchor.x * sprite.pixel_size * (-1.0 if sprite.flip_h else 1.0)
	var up: Vector3 = board.camera.global_basis.y * (anchor.y * sprite.pixel_size + 0.30)
	return sprite.global_position - board.coord_position(coord) + right + up + board.camera.global_basis.z * 0.015

func assign_perch(resident: Dictionary) -> void:
	var coord: Vector2i = resident["coord"]
	resident["head_actor"] = board.unit_actors[coord].get_instance_id() if head_eligible(coord) else 0

func choose_perch(choices: Array) -> Vector2i:
	var heads := choices.filter(func(coord): return head_eligible(coord))
	# Returning birds notice a quiet helmet without all crowding the same unit.
	if not heads.is_empty() and rng.randf() < 0.5:
		return heads[rng.randi_range(0, heads.size() - 1)]
	return choices[rng.randi_range(0, choices.size() - 1)]

func candidates() -> Array[Vector2i]:
	var occupied := {}
	for resident in flocks:
		if resident.get("head_actor", 0) != 0 and resident["state"] in ["grounded", "landing"]: occupied[resident["coord"]] = true
	# An actor may cross an empty friendly tile before the final cells change.
	for motion in board.active_motions.values():
		for coord in motion["action"]["path"]: occupied[coord] = true
	var result: Array[Vector2i] = []
	for coord in board.cells:
		if not occupied.has(coord) and eligible(coord): result.append(coord)
	return result

func sync() -> void:
	update_visibility()
	track_units()
	for flock in flocks:
		if flock["state"] in ["grounded", "landing"] and not perch_valid(flock): scatter(flock["coord"])
	var desired := MAX_BIRDS if not board.cells.is_empty() else 0
	if flocks.size() < desired:
		var available := candidates()
		while flocks.size() < desired and not available.is_empty():
			var coord := choose_perch(available)
			create_flock(coord)
			if head_eligible(coord): available.erase(coord)
	land_waiting()

func create_flock(coord: Vector2i) -> void:
	var root := Node3D.new()
	root.name = "Flock"
	add_child(root)
	root.position = board.coord_position(coord)
	var birds: Array[Sprite3D] = []
	var slot := flocks.size() % OFFSETS.size()
	for index in range(1):
		var bird := Sprite3D.new()
		bird.texture = textures[rng.randi_range(0, textures.size() - 1)]
		bird.hframes = 4
		bird.vframes = 3
		bird.pixel_size = 0.055
		bird.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bird.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		bird.shaded = false
		# Share normal depth sorting with other sprites. The opaque prepass
		# lets solid feather pixels occlude them without losing flight fades.
		bird.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		bird.no_depth_test = false
		bird.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bird.position = OFFSETS[slot]
		bird.flip_h = rng.randf() < 0.5
		root.add_child(bird)
		birds.append(bird)
	flocks.append({"coord":coord, "previous":coord, "root":root, "birds":birds, "state":"grounded", "time":rng.randf() * 4.0, "return_round":0, "direction":Vector3.ZERO, "offset":OFFSETS[slot], "phase":rng.randf() * TAU, "flight_origin":OFFSETS[slot], "duration":1.4, "delay":0.0, "speed":3.0, "lift":2.0, "curve":0.0, "flap_rate":14.0})

	assign_perch(flocks[-1])

func scatter(coord: Vector2i, approach := Vector3.INF) -> void:
	for flock in flocks:
		if flock["coord"] != coord or not flock["state"] in ["grounded", "landing"]: continue
		flock["state"] = "flying"
		flock["time"] = 0.0
		flock["previous"] = coord
		flock["return_round"] = round_number + rng.randi_range(1, 2)
		var direction := Vector3.ZERO
		if approach.is_finite():
			direction = board.coord_position(coord) - approach
			direction.y = 0.0
		if direction.is_zero_approx():
			var angle := rng.randf_range(-PI, PI)
			direction = Vector3(cos(angle), 0, sin(angle))
		flock["direction"] = direction.normalized().rotated(Vector3.UP, rng.randf_range(-1.0, 1.0))
		flock["flight_origin"] = flock["birds"][0].position
		flock["duration"] = rng.randf_range(1.1, 1.65)
		flock["delay"] = rng.randf_range(0.0, 0.1)
		flock["speed"] = rng.randf_range(2.4, 4.2)
		flock["lift"] = rng.randf_range(1.4, 2.6)
		flock["curve"] = rng.randf_range(-1.1, 1.1)
		flock["flap_rate"] = rng.randf_range(12.0, 18.0)

func set_round(value: int) -> void:
	if value < round_number:
		clear()
		round_number = value
		sync()
		return
	if value == round_number: return
	round_number = value
	track_units()
	land_waiting()

func land_waiting() -> void:
	var available: Array[Vector2i] = []
	var scanned := false
	for flock in flocks:
		if flock["state"] != "away" or round_number < int(flock["return_round"]): continue
		if not scanned:
			available = candidates()
			scanned = true
		var choices := available.filter(func(coord): return coord != flock["previous"])
		if choices.is_empty(): continue
		var coord: Vector2i = choose_perch(choices)
		flock["coord"] = coord
		assign_perch(flock)
		if flock["head_actor"] != 0: available.erase(coord)
		flock["root"].position = board.coord_position(coord)
		flock["root"].show()
		flock["state"] = "landing"
		flock["time"] = 0.0

func _process(delta: float) -> void:
	update_visibility()
	if not visible: return
	var elapsed: float = delta * board.playback.speed_scale
	for flock in flocks:
		flock["time"] += elapsed
		var time: float = flock["time"]
		var state: String = flock["state"]
		if state in ["grounded", "landing"] and flock.get("head_actor", 0) != 0 and not perch_valid(flock):
			scatter(flock["coord"])
			state = flock["state"]
			time = 0.0
		if state == "away": continue
		if state == "flying" and time >= float(flock["duration"]) + float(flock["delay"]):
			flock["root"].hide()
			flock["state"] = "away"
			land_waiting()
			continue
		if state == "landing" and time >= LAND_SECONDS:
			flock["state"] = "grounded"
			state = "grounded"
		for index in range(flock["birds"].size()):
			var bird: Sprite3D = flock["birds"][index]
			var offset: Vector3 = perch_offset(flock)
			var alpha := 1.0
			var frame := 0
			if state == "flying":
				var t := maxf(0.0, time - float(flock["delay"]))
				var direction: Vector3 = flock["direction"]
				var side := direction.cross(Vector3.UP)
				offset = flock["flight_origin"] + direction * float(flock["speed"]) * (t + t * t * 0.45)
				offset += side * float(flock["curve"]) * t * t
				offset.y += float(flock["lift"]) * (1.0 - exp(-t * 4.5)) + t * 0.8
				alpha = 1.0 - smoothstep(float(flock["duration"]) * 0.3, float(flock["duration"]), t)
				frame = 4 + posmod(int(t * float(flock["flap_rate"]) + float(flock["phase"])), 4)
				bird.flip_h = direction.dot(board.camera.global_basis.x) < 0.0

			elif state == "landing":
				var amount := 1.0 - smoothstep(0.0, LAND_SECONDS, time)
				offset += -flock["direction"] * amount * 1.7 + Vector3.UP * amount * 2.2
				alpha = smoothstep(0.0, 0.3, time)
				frame = 4 + posmod(int(time * 12.0 + float(flock["phase"])), 4)
			else:
				# Short pecks separated by longer still poses, out of phase per bird.
				var tick := posmod(int(time * 3.0 + float(flock["phase"])), 12)
				frame = tick if tick < 4 else 0
			bird.position = offset
			bird.frame = frame
			bird.modulate.a = alpha
			if board.sprite_lighting != null: board.sprite_lighting.sync(bird)

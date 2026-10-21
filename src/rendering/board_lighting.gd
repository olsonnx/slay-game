extends Node3D
## Bounded accent lights; source discovery happens only when visible cells change.
const Style = preload("res://src/rendering/lighting_style.gd")
const MAX_ACCENTS := 3
var board
var style := "simple"
var sources: Array[Dictionary] = []
var sources_by_coord: Dictionary = {}
var accents: Array[OmniLight3D] = []
const FADE_SECONDS := 0.28
var slots: Array[Dictionary] = []
var shadow_target := 1.0
var warming := false
var warmup_passes := 0
func _init(view) -> void:
	board = view
	name = "BoardLighting"
func _ready() -> void:
	for index in range(MAX_ACCENTS):
		var light := OmniLight3D.new()
		light.shadow_enabled = false
		light.omni_range = 2.1
		light.omni_attenuation = 1.8
		light.hide()
		add_child(light)
		accents.append(light)
		slots.append({"source":{},"target":{},"strength":0.0,"goal":0.0})
	set_process(false)
func apply_style(value: String) -> void:
	style = value
	Style.apply(board.background_environment,board.sun,style)
	if board.sprite_lighting != null: board.sprite_lighting.set_enabled(style == "atmospheric")
	if board.unit_batches != null: board.unit_batches.refresh_sprite_lighting()
	board.refresh_lighting_materials(style != "simple")
	if board.static_batches != null: board.static_batches.refresh_lighting_materials(style != "simple",board.shadow_texture)
	if board.unit_batches != null and board.unit_batches.shadow_material != null:
		board.unit_batches.shadow_material.albedo_texture = Style.contact_shadow() if style != "simple" else board.shadow_texture
	refresh_sources()
func refresh_sources() -> void:
	var scope: Dictionary = board.visible_change_coords
	if scope.is_empty() or style != "atmospheric": sources_by_coord.clear()
	if style != "atmospheric":
		sources.clear()
		update_camera()
		return
	var changed := scope.is_empty()
	for coord in board.cells if scope.is_empty() else scope:
		var cell: Dictionary = board.cells.get(coord, {})
		var source := {}
		if cell.get("mana_source",false):
			source = {"position":board.coord_position(coord)+Vector3(0.48,0.65,-0.38),"mana":true}
		elif cell.get("capital",-1) >= 0 or cell.get("building","") == "house":
			source = {"position":board.coord_position(coord)+Vector3(0.1,0.6,0.4),"mana":false}
		if sources_by_coord.get(coord, {}) == source: continue
		changed = true
		if source.is_empty(): sources_by_coord.erase(coord)
		else: sources_by_coord[coord] = source
	if not changed: return
	sources.assign(sources_by_coord.values())
	update_camera()

func update_camera() -> void:
	if warming: return
	shadow_target = lerpf(0.68,1.0,1.0-smoothstep(24.0,56.0,board.zoom))
	if style != "atmospheric" or not board.active or board.level_transitioning or board.value_heatmap != null and board.value_heatmap.active:
		for index in range(accents.size()):
			accents[index].hide()
			accents[index].light_energy = 0.0
			slots[index].source = {}
			slots[index].target = {}
			slots[index].strength = 0.0
			slots[index].goal = 0.0
		set_process(board.active and not is_equal_approx(board.sun.shadow_opacity,shadow_target))
		return
	var nearby := sources.filter(func(source): return source.position.distance_squared_to(board.focus) < 144.0)
	nearby.sort_custom(func(a,b): return a.position.distance_squared_to(board.focus) < b.position.distance_squared_to(board.focus))
	nearby.resize(mini(nearby.size(),MAX_ACCENTS))
	# Keep retained lights in their slots. Replacements move only when dark.
	var remaining: Array = nearby.duplicate()
	for slot in slots:
		if not slot.source.is_empty() and nearby.has(slot.source):
			slot.target = slot.source
			remaining.erase(slot.source)
		else: slot.target = {}
	for slot in slots:
		if slot.target.is_empty() and not remaining.is_empty(): slot.target = remaining.pop_front()
	var zoom_strength := 1.0-smoothstep(20.0,28.0,board.zoom)
	for slot in slots:
		var source: Dictionary = slot.target
		slot.goal = zoom_strength*(1.0-smoothstep(8.0,12.0,source.position.distance_to(board.focus))) if not source.is_empty() else 0.0
	set_process(true)

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if warming: return
	var moving := false
	for index in range(accents.size()):
		var slot: Dictionary = slots[index]
		var light: OmniLight3D = accents[index]
		var replacing: bool = slot.source != slot.target
		var goal: float = 0.0 if replacing else slot.goal
		slot.strength = move_toward(slot.strength,goal,maxf(delta,0.0)/FADE_SECONDS)
		if slot.strength == 0.0 and replacing:
			slot.source = slot.target
			if not slot.source.is_empty():
				light.position = slot.source.position
				light.light_color = Color("8acbf2") if slot.source.mana else Color("ffc27b")
			# Empty slots may begin fading in immediately; retained ones fade out first.
			slot.strength = minf(slot.goal,maxf(delta,0.0)/FADE_SECONDS)
		var base_energy := 0.0 if slot.source.is_empty() else 0.48 if slot.source.mana else 0.38
		light.light_energy = base_energy*smoothstep(0.0,1.0,slot.strength)
		light.visible = slot.strength > 0.0 and not slot.source.is_empty()
		moving = moving or slot.strength != slot.goal or slot.source != slot.target
	board.sun.shadow_opacity = move_toward(board.sun.shadow_opacity,shadow_target,maxf(delta,0.0)/FADE_SECONDS)
	set_process(moving or not is_equal_approx(board.sun.shadow_opacity,shadow_target))

func warmup() -> void:
	# Compatibility compiles light variants only after an actual draw. Call under
	# the existing loading cover, in the real viewport with its real materials.
	if RenderingServer.get_current_rendering_method() != "gl_compatibility": return
	if warming or style != "atmospheric" or DisplayServer.get_name() == "headless" or board.cells.is_empty(): return
	warming = true
	var old_focus: Vector3 = board.focus
	var old_zoom: float = board.zoom
	var anchor: Vector3 = sources[0].position if not sources.is_empty() else board.focus
	for coord in board.cells:
		if board.cells[coord].get("capital",-1) >= 0:
			anchor = board.coord_position(coord)
			break
	board.focus = anchor
	board.zoom = 16.0
	board.update_camera()
	for count in range(1,MAX_ACCENTS+1):
		for index in range(accents.size()):
			var light := accents[index]
			light.position = anchor+Vector3(0,1,0)
			light.omni_range = 24.0
			light.light_energy = 0.001
			light.visible = index < count
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		warmup_passes += 1
	for light in accents:
		light.hide()
		light.omni_range = 2.1
		light.light_energy = 0.0
	for slot in slots:
		slot.source = {}
		slot.target = {}
		slot.strength = 0.0
	board.focus = old_focus
	board.zoom = old_zoom
	warming = false
	board.update_camera()
	advance(1.0)
	# Let queued driver work and the restored wide view settle under the cover.
	for frame in range(8):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

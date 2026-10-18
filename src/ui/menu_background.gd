extends Control
## Isolated, capped-resolution world, rendered at the application's full frame rate.
const DecorativeMap = preload("res://src/rendering/decorative_map.gd")
var viewport: SubViewport
var map
var active := false
var rendered_frames := 0
var profile_updates := false
var last_update_usec := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Video.antialiasing
	add_child(viewport)
	map = DecorativeMap.new()
	viewport.add_child(map)
	var image := TextureRect.new()
	image.texture = viewport.get_texture()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vignette := ColorRect.new()
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://resources/shaders/menu_vignette.gdshader")
	vignette.material = material
	add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(update_resolution)
	get_viewport().size_changed.connect(update_resolution)
	Video.changed.connect(_on_video_changed)
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	update_resolution()
	set_active(false)

func update_resolution() -> void:
	var bounds: Vector2 = get_viewport().get_texture().get_size()
	if bounds.x < 1 or bounds.y < 1:
		return
	var scale_factor := minf(1.0, minf(1280.0 / bounds.x, 820.0 / bounds.y))
	viewport.size = Vector2i(maxi(1, roundi(bounds.x * scale_factor)), maxi(1, roundi(bounds.y * scale_factor)))
	map.layout_camera(float(bounds.x) / bounds.y)
	if active:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _on_video_changed() -> void:
	viewport.msaa_3d = Video.antialiasing
	map.apply_background()
	update_resolution()

func set_active(enabled: bool) -> void:
	active = enabled
	map.active = enabled
	visible = enabled
	set_process(enabled)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED

func _process(delta: float) -> void:
	var started := Time.get_ticks_usec() if profile_updates else 0
	map.advance(delta)
	if profile_updates:
		last_update_usec = Time.get_ticks_usec() - started

func _on_frame_drawn() -> void:
	if active and viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		rendered_frames += 1

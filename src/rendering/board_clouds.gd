extends Node
## Low-resolution volume surrounding a soft, irregular island clearing.
const BASE_NOISE = preload("res://resources/clouds/base_noise.tres")
const DETAIL_NOISE = preload("res://resources/clouds/detail_noise.tres")
const FADE_START := 32.0
const FADE_END := 52.0
var board
var viewport: SubViewport
var volume: ShaderMaterial
var composite: ShaderMaterial
var surface: MeshInstance3D
var elapsed := 0.0
var loading := false
var warming := false
var enabled := true
var strength := 0.0
var camera_state: Array = []
const OFFSHORE_CLEARANCE := 4.0
const CLEARING_FEATHER := 12.0
var clearing_center := Vector3.ZERO
var clearing_planes := PackedVector3Array()

func _init(owner_board) -> void:
	board = owner_board
	name = "Clouds"

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "CloudVolume"
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	volume = ShaderMaterial.new()
	volume.shader = preload("res://resources/shaders/cloud_volume.gdshader")
	volume.set_shader_parameter("cloud_noise_texture",BASE_NOISE)
	volume.set_shader_parameter("detail_noise_texture",DETAIL_NOISE)
	rect.material = volume
	viewport.add_child(rect)
	composite = ShaderMaterial.new()
	composite.shader = preload("res://resources/shaders/cloud_composite.gdshader")
	composite.render_priority = 127
	composite.set_shader_parameter("cloud_texture",viewport.get_texture())
	surface = MeshInstance3D.new()
	surface.name = "CloudComposite"
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	surface.mesh = quad
	surface.material_override = composite
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.extra_cull_margin = 16384
	surface.ignore_occlusion_culling = true
	board.camera.add_child(surface)
	surface.position.z = -1
	board.get_viewport().size_changed.connect(update_camera)
	board.visible_board_changed.connect(sync)
	sync()

func sync() -> void:
	# Recalculate only when the board changes, never in the animation loop.
	var bounds := AABB()
	var first := true
	for coord in board.cells:
		var point: Vector3 = board.coord_position(coord)
		bounds = AABB(point,Vector3.ZERO) if first else bounds.expand(point)
		first = false
	clearing_center = bounds.get_center()
	clearing_planes.clear()
	# A broad island envelope with unequal offshore margins, rather than a circle.
	# Only twelve directions are needed; cloud density softens the envelope itself.
	for i in range(12):
		var angle := TAU*i/12.0
		var normal := Vector2(cos(angle),sin(angle))
		var support := 0.0
		for coord in board.cells:
			var offset: Vector3 = board.coord_position(coord) - clearing_center
			support = maxf(support,normal.dot(Vector2(offset.x,offset.z)))
		var margin := 2.0 + OFFSHORE_CLEARANCE + (sin(angle*3.0+0.7)+1.0)*3.5 + (cos(angle*2.0+1.0)+1.0)*2.5
		clearing_planes.append(Vector3(normal.x,normal.y,support+margin))
	camera_state.clear()
	update_camera()

func prepare() -> void:
	if DisplayServer.get_name() == "headless": return
	for noise in [BASE_NOISE,DETAIL_NOISE]:
		var data = noise.get_data()
		while data == null or data.is_empty():
			await noise.changed
			data = noise.get_data()

func set_loading(value: bool) -> void:
	loading = value
	update_camera()

func _process(delta: float) -> void:
	update_camera()
	if strength > 0 and not Video.reduced_motion:
		elapsed += delta
		volume.set_shader_parameter("cloud_time",elapsed)

func update_camera() -> void:
	if surface == null or board.camera == null: return
	strength = smoothstep(FADE_START,FADE_END,board.zoom) if enabled and Video.clouds and board.active and not loading and not board.level_transitioning else 0.0
	if warming: strength = 1.0
	var output: Vector2 = board.get_viewport().get_visible_rect().size
	var state: Array = [strength,board.camera.global_transform,board.zoom,output,Video.background]
	if state == camera_state: return
	camera_state = state
	surface.visible = strength > 0.001
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if surface.visible else SubViewport.UPDATE_DISABLED
	if not surface.visible: return
	var scale := minf(0.5,minf(640.0/maxf(1,output.x),360.0/maxf(1,output.y)))
	var resolution := Vector2i(maxi(1,roundi(output.x*scale)),maxi(1,roundi(output.y*scale)))
	if viewport.size != resolution: viewport.size = resolution
	var span := Vector2(board.zoom*output.x/maxf(1,output.y),board.zoom)
	var camera: Camera3D = board.camera
	volume.set_shader_parameter("ray_origin",camera.global_position)
	volume.set_shader_parameter("ray_right",camera.global_basis.x)
	volume.set_shader_parameter("ray_up",camera.global_basis.y)
	volume.set_shader_parameter("ray_direction",-camera.global_basis.z)
	volume.set_shader_parameter("view_span",span)
	composite.set_shader_parameter("visibility",strength)
	composite.set_shader_parameter("water_background",Video.background == "water")
	# Keep the island envelope parallel to the tile plane through camera motion.
	var corner := ground_at(Vector2.ZERO)
	var right := ground_at(Vector2(output.x,0)) - corner
	var down := ground_at(Vector2(0,output.y)) - corner
	volume.set_shader_parameter("ground_origin",Vector2(corner.x,corner.z))
	volume.set_shader_parameter("ground_right",Vector2(right.x,right.z))
	volume.set_shader_parameter("ground_down",Vector2(down.x,down.z))
	volume.set_shader_parameter("clearing_center",Vector2(clearing_center.x,clearing_center.z))
	volume.set_shader_parameter("clearing_planes",clearing_planes)
	volume.set_shader_parameter("clearing_feather",CLEARING_FEATHER)

func ground_at(screen: Vector2) -> Vector3:
	var origin: Vector3 = board.camera.project_ray_origin(screen)
	var direction: Vector3 = board.camera.project_ray_normal(screen)
	return origin - direction * origin.y / direction.y

func _exit_tree() -> void:
	if is_instance_valid(surface): surface.queue_free()

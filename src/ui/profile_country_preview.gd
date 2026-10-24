extends TextureRect
## A private production-rendered miniature; it cannot affect a live match.
var viewport: SubViewport
var board
var cells: Dictionary = {}
var last_color := Color.TRANSPARENT
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	viewport = SubViewport.new()
	viewport.size = Vector2i(752, 664)
	viewport.own_world_3d = true
	viewport.msaa_3d = Video.antialiasing
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	texture = viewport.get_texture()
	board = preload("res://src/rendering/board_view.gd").new()
	# Picker colors are disposable; keep them out of application warmup caches.
	board.unit_sprites = preload("res://src/rendering/unit_sprite_library.gd").new()
	board.outline_cache = {}
	viewport.add_child(board)
	board.set_process(false)
	board.navigation.set_process(false)
	board.controls_enabled = false
	board.land_ambience.set_process(false)
	board.birds.set_loading(true)
	board.birds.hide()
	board.wildlife.set_process(false)
	var rules = preload("res://src/game/kingdom_rules.gd").new()
	for q in range(-2, 3):
		for r in range(-2, 3):
			if absi(q + r) > 2 or Vector2i(q, r) in [Vector2i(-2, 0), Vector2i(2, -2)]: continue
			var coord := Vector2i(q, r)
			rules.cells[coord] = rules.make_cell(0)
			rules.cells[coord].tree = false
	rules.cells[Vector2i.ZERO].capital = 0
	rules.cells[Vector2i(1,0)].unit = 2
	rules.cells[Vector2i(-1,1)].tree = true
	rules.cells[Vector2i(0,-2)].tree = true
	rules.cells[Vector2i(-1,-1)].tree = true
	rules.rebuild_kingdoms()
	cells = rules.cells
	board.zoom = 9.5
	board.pitch = 0.92
	board.yaw = 0.18
	board.update_camera()
	# The preview should show the material clearly, without miniature defocus.
	board.camera.set_meta("dof_settings", {"enabled":false})
	board.update_camera()
	visibility_changed.connect(refresh)
	Video.changed.connect(refresh)

func set_color(value: Color) -> void:
	if board == null: return
	if value == last_color and not board.cells.is_empty(): return
	last_color = value
	board.COLORS[0] = value.darkened(0.06)
	# Tint changes are presentation-only; rebuild the preview island.
	board.render_cells({})
	board.sprite_cache.clear()
	board.image_cache.clear()
	board.outline_cache.clear()
	board.unit_sprites.sheets.clear()
	board.unit_sprites.frames.clear()
	board.unit_sprites.portraits.clear()
	board.unit_batches.sprite_meshes.clear()
	board.unit_batches.sprite_materials.clear()
	board.unit_batches.lit_sprite_materials.clear()
	board.sprite_lighting.materials.clear()
	board.render_cells(cells)
	board.zoom = 9.5
	board.update_camera()
	board.lighting.advance(1.0)
	refresh()

func refresh() -> void:
	if viewport == null: return
	viewport.msaa_3d = Video.antialiasing
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED

extends Node3D
## Temporary instancing for individually moving tiles. Original nodes retain
## their transforms and semantics while opaque scenery shares draw calls.
var board
var sources: Array = []
var tile_slots: Dictionary = {}
var previous_transforms: Dictionary = {}
var groups: Dictionary = {}
var source_count := 0
var transform_updates := 0

func _init(view) -> void:
	board = view
	name = "TransitionBatches"

func _ready() -> void:
	RenderingServer.frame_pre_draw.connect(update_transforms)

func capture() -> void:
	for tile in board.tile_nodes.values():
		collect(tile, tile)
	for group in groups.values():
		var render := MultiMeshInstance3D.new()
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_colors = true
		instances.mesh = group["mesh"]
		instances.instance_count = group["entries"].size()
		render.multimesh = instances
		render.material_override = group["material"]
		render.cast_shadow = group["shadow"]
		render.layers = group["layers"]
		add_child(render)
		for index in range(group["entries"].size()):
			var entry: Array = group["entries"][index]
			var tile: Node3D = entry[0]
			if not tile_slots.has(tile): tile_slots[tile] = []
			tile_slots[tile].append([instances, index, entry[1]])
			instances.set_instance_color(index, entry[2])
	update_transforms()

func collect(node: Node, tile: Node3D) -> void:
	if node != tile and node is Node3D and node.has_meta("unit_role"): return
	if node is MeshInstance3D and node.layers != 0 and board.static_batches.eligible(node):
		var feature: String = board.static_batches.material_key(node.material_override)
		var key := str(node.mesh.get_rid()) + ":" + feature + ":" + str(node.layers) + ":" + str(node.cast_shadow)
		if not groups.has(key):
			var material: StandardMaterial3D = node.material_override.duplicate()
			material.albedo_color = Color.WHITE
			material.vertex_color_use_as_albedo = true
			material.vertex_color_is_srgb = true
			groups[key] = {"mesh":node.mesh, "material":material, "layers":node.layers, "shadow":node.cast_shadow, "entries":[]}
		groups[key]["entries"].append([tile, tile.global_transform.affine_inverse() * node.global_transform, node.material_override.albedo_color])
		sources.append([weakref(node), node.layers])
		preload("res://src/rendering/batch_source_lifetime.gd").set_layers(node, 0)
		source_count += 1
	for child in node.get_children(): collect(child, tile)

func update_transforms() -> void:
	# This runs after tweens, so scenery and soldiers share the same tile pose.
	for tile in tile_slots:
		if not is_instance_valid(tile): continue
		var transform: Transform3D = tile.transform
		if previous_transforms.get(tile) == transform: continue
		previous_transforms[tile] = transform
		for slot in tile_slots[tile]:
			var instances: MultiMesh = slot[0]
			instances.set_instance_transform(slot[1], transform * slot[2])
			transform_updates += 1

func release() -> void:
	if RenderingServer.frame_pre_draw.is_connected(update_transforms):
		RenderingServer.frame_pre_draw.disconnect(update_transforms)
	for saved in sources:
		var node = saved[0].get_ref()
		if is_instance_valid(node) and not node.is_queued_for_deletion(): preload("res://src/rendering/batch_source_lifetime.gd").set_layers(node, saved[1])
	sources.clear()
	tile_slots.clear()
	previous_transforms.clear()
	hide()

func _exit_tree() -> void:
	release()

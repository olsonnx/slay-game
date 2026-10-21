extends Node3D
## Small neutral actor set, rendered from the visible board, never the live rules.
const SHEETS := {"bear":preload("res://assets/neutrals/MiniBear.png"),"wolf":preload("res://assets/neutrals/MiniWolf.png"),"boar":preload("res://assets/neutrals/MiniBoar.png")}
const UnitSprites = preload("res://src/rendering/unit_sprite_library.gd")
const PIXEL_SIZE := UnitSprites.PIXEL_SIZE
const CAVE_SCALE := 0.72
const CAVE_OFFSET := Vector3(0,0,-0.30)
const CLIPS := {
	"bear":{"idle":[0,4,6.0,12],"run":[1,6,10.0,12],"attack":[3,6,12.0,12],"alert":[5,10,10.0,8],"death":[7,4,10.0,12]},
	"wolf":{"idle":[0,4,6.0,12],"run":[1,6,10.0,12],"attack":[3,5,12.0,12],"alert":[5,7,10.0,12],"death":[7,4,10.0,12]},
	"boar":{"idle":[0,4,6.0,12],"run":[1,4,10.0,12],"attack":[3,5,12.0,12],"alert":[0,4,8.0,12],"death":[5,4,10.0,12]}}
signal world_action_started(action: Dictionary)
var board
var actors: Dictionary = {}
var frames: Dictionary = {}
var dying: Array[Node3D] = []
var elapsed := 0.0
var idle_elapsed := 0.0
var generation := 0
var is_playing := false
var sync_required := false
var world_tween: Tween
var hovered := Vector2i(999,999)

func _init(view) -> void:
	board = view
	name = "Wildlife"

static func add_lair(assets, parent: Node3D, kind: String) -> void:
	var root := Node3D.new()
	root.name = "WildlifeLair"
	parent.add_child(root)
	var color := Color("85867b") if kind == "bear" else Color("7b8588") if kind == "wolf" else Color("8a806b")
	var size := 1.0 if kind == "bear" else 0.90 if kind == "wolf" else 0.82
	root.scale = Vector3.ONE*size*CAVE_SCALE
	root.position = CAVE_OFFSET
	# A continuous rocky mound surrounds a real opening and recessed tunnel.
	# Shared single-surface meshes remain eligible for the scenery batches.
	assets.piece(root,cave_mesh(assets,"rock"),Vector3.ZERO,color)
	assets.piece(root,cave_mesh(assets,"throat"),Vector3.ZERO,Color("45483e"))
	var dark = assets.piece(root,cave_mesh(assets,"dark"),Vector3.ZERO,Color("171c18"))
	dark.material_override = assets.material(Color("171c18"),true,true)
	var path = assets.cylinder(root,Vector3(0,0.018,0.42),0.28,0.28,0.025,Color("82785c"),7)
	path.scale = Vector3(1.05,1,1.55)
	for detail in [[Vector3(-0.61,0.12,0.29),Vector3(0.34,0.26,0.35)], [Vector3(0.60,0.10,0.35),Vector3(0.27,0.21,0.30)], [Vector3(-0.45,0.05,0.65),Vector3(0.16,0.10,0.15)]]:
		var stone = assets.piece(root,cave_mesh(assets,"pebble"),detail[0],color.darkened(0.10))
		stone.scale = detail[1]

static func cave_mesh(assets, part: String) -> ArrayMesh:
	var key := "wildlife_cave:"+part
	if assets.mesh_cache.has(key): return assets.mesh_cache[key]
	var outer := PackedVector2Array([Vector2(-0.74,0),Vector2(-0.68,0.43),Vector2(-0.46,0.78),Vector2(-0.12,0.96),Vector2(0.24,0.89),Vector2(0.57,0.65),Vector2(0.72,0.29),Vector2(0.73,0)])
	var inner := PackedVector2Array([Vector2(-0.39,0),Vector2(-0.40,0.28),Vector2(-0.29,0.51),Vector2(-0.10,0.62),Vector2(0.16,0.59),Vector2(0.34,0.40),Vector2(0.39,0.19),Vector2(0.40,0)])
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_smooth_group(-1)
	if part == "pebble":
		var stone := SphereMesh.new()
		stone.radius = 0.5
		stone.height = 1.0
		stone.radial_segments = 5
		stone.rings = 2
		builder.append_from(stone,0,Transform3D.IDENTITY)
	else:
		for index in range(outer.size()-1):
			var a := Vector3(outer[index].x,outer[index].y,0.10)
			var b := Vector3(outer[index+1].x,outer[index+1].y,0.10)
			var c := Vector3(inner[index].x,inner[index].y,0.43)
			var d := Vector3(inner[index+1].x,inner[index+1].y,0.43)
			var back_a := Vector3(a.x*0.85,a.y*0.67,-0.48)
			var back_b := Vector3(b.x*0.85,b.y*0.67,-0.48)
			var deep_c := Vector3(c.x*0.72,c.y*0.72+0.02,-0.20)
			var deep_d := Vector3(d.x*0.72,d.y*0.72+0.02,-0.20)
			var vertices: Array
			match part:
				"rock": vertices = [a,b,d,a,d,c,a,back_a,back_b,a,back_b,b,back_a,Vector3(0,0.25,-0.62),back_b]
				"throat": vertices = [c,d,deep_d,c,deep_d,deep_c]
				# A near-black occlusion surface keeps the mouth readable from the
				# high game camera, where the tunnel roof hides its deepest end.
				_: vertices = [Vector3(0,0.20,0.415),Vector3(d.x,d.y,0.415),Vector3(c.x,c.y,0.415)]
			for vertex in vertices: builder.add_vertex(vertex)
		builder.generate_normals()
	var mesh := builder.commit()
	assets.mesh_cache[key] = mesh
	return mesh

static func animation_clip(kind: String, pose: String) -> Array:
	return CLIPS[kind].get(pose,CLIPS[kind].idle)

func frame(kind: String, pose: String, index: int) -> Dictionary:
	var clip := animation_clip(kind,pose)
	index %= int(clip[1])
	var key := "%s:%s:%d" % [kind,pose,index]
	if not frames.has(key):
		# The bear's standing pose needs four extra rows above normal infantry
		# framing. Both crops retain the same bottom edge and foot anchor.
		var crop := Rect2i(index*32,int(clip[0])*32+int(clip[3]),32,32-int(clip[3]))
		var image: Image = SHEETS[kind].get_image().get_region(crop)
		var texture := AtlasTexture.new()
		texture.atlas = SHEETS[kind]
		texture.region = Rect2(crop)
		frames[key] = {"texture":texture,"image":image,"top":image.get_used_rect().position.y}
	return frames[key]

func sprite_for(root: Node3D) -> Sprite3D:
	return root.get_node("Animal")

func new_actor(coord: Vector2i, kind: String, home: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.set_meta("hex",coord)
	root.set_meta("kind",kind)
	root.set_meta("home",home)
	root.set_meta("pose","idle")
	root.set_meta("pose_time",elapsed)
	var sprite := Sprite3D.new()
	sprite.name = "Animal"
	sprite.pixel_size = PIXEL_SIZE
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.set_meta("wildlife",true)
	root.add_child(sprite)
	var outline := Sprite3D.new()
	outline.name = "HoverOutline"
	outline.pixel_size = PIXEL_SIZE
	outline.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	outline.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outline.modulate.a = 0.0
	outline.visible = false
	sprite.add_child(outline)
	var indicator := Sprite3D.new()
	indicator.name = "Aggro"
	indicator.texture = preload("res://assets/ui/exclamation.png")
	indicator.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	indicator.pixel_size = PIXEL_SIZE
	indicator.shaded = false
	indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	indicator.render_priority = 100
	indicator.position = Vector3(0,1.85,0)
	indicator.visible = false
	root.add_child(indicator)
	add_child(root)
	root.position = board.coord_position(coord)
	set_frame(root)
	return root

func show_aggro(actor: Node3D, target: Vector2i) -> void:
	actor.set_meta("aggro_target",target)
	actor.get_node("Aggro").visible = target != board.NONE

func set_frame(actor: Node3D) -> void:
	var pose: String = actor.get_meta("pose","idle")
	var age: float = elapsed-float(actor.get_meta("pose_time",0.0))
	if pose == "idle": age = idle_elapsed
	var clip := animation_clip(actor.get_meta("kind"),pose)
	var index := int(age*float(clip[2]))
	if pose in ["death","alert"]: index = mini(index,int(clip[1])-1)
	var data := frame(actor.get_meta("kind"),pose,index)
	var sprite := sprite_for(actor)
	sprite.position = Vector3(0,(data.image.get_height()*0.5-1.5)*PIXEL_SIZE+0.06,0)
	sprite.texture = data.texture
	sprite.set_meta("image",data.image)
	var outline: Sprite3D = sprite.get_node("HoverOutline")
	if outline.visible:
		if not data.has("outline"):
			data["outline"] = preload("res://src/rendering/board_assets.gd").pixel_hover_outline(data.image)
		outline.texture = data.outline
		outline.flip_h = sprite.flip_h
	if board.sprite_lighting != null: board.sprite_lighting.sync(sprite)
	var indicator: Sprite3D = actor.get_node("Aggro")
	var warning_clearance := indicator.texture.get_height()*0.5*indicator.pixel_size+0.10
	indicator.position = sprite.position+actor.global_basis.inverse()*board.camera.global_basis.y*((data.image.get_height()*0.5-int(data.top))*PIXEL_SIZE+warning_clearance)

func sync() -> void:
	if board.bulk_rebuilding: return
	var seen := {}
	var scope: Dictionary = {} if sync_required else board.visible_change_coords
	sync_required = false
	var affected := {}
	for home in actors:
		if scope.is_empty() or scope.has(actors[home].get_meta("hex")): affected[home] = true
	for coord in board.cells if scope.is_empty() else scope:
		var cell: Dictionary = board.cells.get(coord, {})
		if cell.get("animal", "") == "": continue
		var home: Vector2i = cell.animal_home
		seen[home] = true
		if not actors.has(home): actors[home] = new_actor(coord,cell.animal,home)
		var actor: Node3D = actors[home]
		actor.set_meta("hex",coord)
		actor.position = board.coord_position(coord)
		show_aggro(actor,cell.get("animal_target",board.NONE))
	for home in affected:
		if not seen.has(home):
			actors[home].queue_free()
			actors.erase(home)

func set_hover(coord: Vector2i) -> void:
	hovered = coord

func clear_hover() -> void:
	hovered = board.NONE
	for actor in actors.values():
		var sprite := sprite_for(actor)
		sprite.modulate = Color.WHITE
		var outline: Sprite3D = sprite.get_node("HoverOutline")
		outline.modulate.a = 0.0
		outline.hide()

func clear() -> void:
	board.playback.clear_tree_growth()
	clear_hover()
	sync_required = true
	stop_world_tween()
	generation += 1
	is_playing = false
	for actor in actors.values(): actor.queue_free()
	for actor in dying:
		if is_instance_valid(actor): actor.queue_free()
	actors.clear()
	dying.clear()

func defeat(coord: Vector2i) -> void:
	if hovered == coord: clear_hover()
	for home in actors.keys():
		var actor: Node3D = actors[home]
		if actor.get_meta("hex") != coord: continue
		actors.erase(home)
		sync_required = true
		actor.set_meta("pose","death")
		show_aggro(actor,board.NONE)
		actor.set_meta("pose_time",elapsed)
		dying.append(actor)
		break

func cancel_effects() -> void:
	board.playback.clear_tree_growth()
	clear_hover()
	sync_required = true
	stop_world_tween()
	generation += 1
	is_playing = false
	for actor in dying:
		if is_instance_valid(actor): actor.queue_free()
	dying.clear()
	for actor in actors.values(): actor.set_meta("pose","idle")

func _process(delta: float) -> void:
	elapsed += delta*board.playback.speed_scale
	idle_elapsed += delta
	visible = board.active and not board.level_transitioning
	for actor in actors.values():
		var sprite := sprite_for(actor)
		var outline: Sprite3D = sprite.get_node("HoverOutline")
		var highlighted: bool = actor.get_meta("hex") == hovered
		outline.modulate.a = move_toward(outline.modulate.a, 0.8 if highlighted else 0.0, delta*0.8/0.12)
		if is_zero_approx(outline.modulate.a): outline.modulate.a = 0.0
		outline.visible = outline.modulate.a > 0.0
		sprite.modulate = Color.WHITE.lerp(Color(1.18,1.14,1.06,1),outline.modulate.a/0.8)
		set_frame(actor)
	for index in range(dying.size()-1,-1,-1):
		var actor := dying[index]
		if not is_instance_valid(actor):
			dying.remove_at(index)
		elif elapsed-float(actor.get_meta("pose_time")) > 0.45:
			actor.queue_free()
			dying.remove_at(index)
		else: set_frame(actor)

func stop_world_tween() -> void:
	if world_tween != null and world_tween.is_valid(): world_tween.kill()
	world_tween = null

func start_world_tween() -> Tween:
	world_tween = board.playback.scaled_tween(self)
	return world_tween

func hit_defender(target: Vector2i) -> void:
	var defender: Node3D = board.unit_actors.get(target)
	if not is_instance_valid(defender): return
	defender.get_node("UnitAnimation").play("death",false,true)
	board.unit_batches.queue_sync()
	board.unit_batches.sync(true)

func play_world(actions: Array, final_cells: Dictionary, partial := false) -> void:
	var token := generation
	is_playing = true
	var playback = board.playback
	playback.is_animating = not actions.is_empty()
	for action in actions:
		if token != generation or not is_inside_tree(): return
		world_action_started.emit(action)
		var actor: Node3D = actors.get(action.home)
		if is_instance_valid(actor):
			if action.get("alert",false):
				show_aggro(actor,action.get("aggro_target",action.target))
				actor.set_meta("pose","alert")
				actor.set_meta("pose_time",elapsed)
				var facing: Vector3 = board.coord_position(action.get("aggro_target",action.target))-actor.position
				if not facing.is_zero_approx(): sprite_for(actor).flip_h = facing.dot(board.camera.global_basis.x) < 0
				set_frame(actor)
				var alert_clip := animation_clip(action.animal,"alert")
				var alert_tween := start_world_tween()
				alert_tween.tween_interval(float(alert_clip[1])/float(alert_clip[2]))
				while alert_tween.is_valid() and alert_tween.is_running():
					await get_tree().process_frame
					if token != generation: return
			if action.kind == "calm":
				board.render_cells(action.changes,true)
				continue
			board.birds.scatter(action.source)
			board.birds.scatter(action.target,board.coord_position(action.source))
			actor.set_meta("pose","run" if action.kind == "move" else "attack")
			actor.set_meta("pose_time",elapsed)
			var direction: Vector3 = board.coord_position(action.target)-actor.position
			if not direction.is_zero_approx(): sprite_for(actor).flip_h = direction.dot(board.camera.global_basis.x) < 0
			var tween := start_world_tween()
			if action.kind == "move": tween.tween_property(actor,"position",board.coord_position(action.target),0.24)
			else:
				tween.tween_property(actor,"position",actor.position+direction*0.40,0.12)
				if action.kind == "attack": tween.tween_callback(hit_defender.bind(action.target))
				var attack_clip := animation_clip(action.animal,"attack")
				tween.tween_interval(maxf(0.20,float(attack_clip[1])/float(attack_clip[2])-0.12))
				if action.kind == "blocked": tween.tween_property(actor,"position",board.coord_position(action.source),0.08)
				else: tween.tween_property(actor,"position",board.coord_position(action.target),0.12)
			while tween.is_valid() and tween.is_running():
				await get_tree().process_frame
				if token != generation: return
		board.render_cells(action.changes,true)
		if action.kind in ["attack","blocked"]: board.action_marker(action.target,Color("d39172") if action.kind == "attack" else Color("91e2ef"))
		if actors.has(action.home): actors[action.home].set_meta("pose","idle")
		# Emergence receives a short beat and cannot also attack this turn.
		if action.kind == "spawn":
			var tween := start_world_tween()
			tween.tween_interval(0.18)
			while tween.is_valid() and tween.is_running():
				await get_tree().process_frame
				if token != generation: return
	if token != generation: return
	playback.is_animating = false
	is_playing = false
	board.render_cells(final_cells, partial, true)

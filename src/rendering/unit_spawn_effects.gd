extends Node3D
## Short tile flashes live separately from movement snapshots, so a merge's
## arrival effect survives the final board synchronization.
var board

func _init(view) -> void:
	board = view

func clear() -> void:
	for effect in get_children(): effect.free()

func play(coord: Vector2i, rank: int) -> float:
	rank = clampi(rank, 1, 3)
	var effect := Node3D.new()
	effect.name = "UnitSpawnEffect"
	effect.set_meta("hex", coord)
	effect.set_meta("tier", rank)
	effect.position = board.coord_position(coord) + Vector3(0, 0.075, 0)
	add_child(effect)
	var duration := 0.30 + rank * 0.04
	var tween: Tween = board.playback.scaled_tween(effect).set_parallel(true)
	var flash := MeshInstance3D.new()
	flash.mesh = board.cylinder_mesh(0.91, 0.91, 0.005, 6)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := effect_material(0.08 + rank * 0.04)
	flash.material_override = glow
	effect.add_child(flash)
	tween.tween_property(glow, "albedo_color:a", 0.0, duration)
	for pulse in range(rank):
		var ring := MeshInstance3D.new()
		ring.name = "SpawnRipple"
		ring.mesh = board.outline_mesh
		ring.position.y = 0.005 + pulse * 0.002
		ring.scale = Vector3(0.82, 1, 0.82)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := effect_material(0.0)
		ring.material_override = material
		effect.add_child(ring)
		var delay := pulse * 0.07
		var radius := 1.10 + rank * 0.08
		tween.tween_property(ring, "scale", Vector3(radius, 1, radius), duration).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(material, "albedo_color:a", 0.65 + rank * 0.10, 0.045).set_delay(delay)
		tween.tween_property(material, "albedo_color:a", 0.0, duration - 0.045).set_delay(delay + 0.045)
	tween.chain().tween_callback(effect.queue_free)
	return duration + (rank - 1) * 0.07

func effect_material(alpha: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = board.playback.flash_material.duplicate()
	material.albedo_color = Color(board.PLACEMENT_COLOR, alpha)
	return material

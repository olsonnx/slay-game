extends Node3D
## Runs at application boot. Retained specimens keep shader variants alive.
const Sprites = preload("res://src/rendering/unit_sprite_library.gd")
const TileEffects = preload("res://src/rendering/board_tile_effects.gd")
const Lifetime = preload("res://src/rendering/batch_source_lifetime.gd")
const BUDGET_USEC := 4000
var completed := false
var prepared_frames := 0
var rendered_passes := 0

func prepare(board, palette_owners: Array = [], report: Callable = Callable()) -> void:
	if completed:
		if report.is_valid(): report.call(1.0)
		return
	name = "GraphicsWarmup"
	position = board.focus
	var owners := {}
	for owner in palette_owners: owners[owner] = true
	for cell in board.cells.values():
		for owner in [cell.get("owner", -1), cell.get("unit_owner", -1)]:
			if owner >= 0: owners[owner] = true
	var total := 0
	for tier in range(1, Sprites.CLIPS.size()):
		for animation in Sprites.CLIPS[tier]:
			total += int(Sprites.clip(tier, animation)[1])
		total += int(Sprites.clip(tier, "idle")[1])
	total *= owners.size()
	var done := 0
	var started := Time.get_ticks_usec()
	for owner in owners:
		for tier in range(1, Sprites.CLIPS.size()):
			# Use the live factory: gameplay must hit these exact caches later.
			board.soldier_texture(tier, owner)
			board.unit_icon_texture(tier, owner)
			for animation in Sprites.CLIPS[tier]:
				for index in range(int(Sprites.clip(tier, animation)[1])):
					board.unit_sprites.frame(tier, board.COLORS[owner], animation, index)
					prepared_frames += 1
					done += 1
					if Time.get_ticks_usec() - started >= BUDGET_USEC:
						if report.is_valid(): report.call(0.85 * done / maxf(total, 1))
						await get_tree().process_frame
						started = Time.get_ticks_usec()
			for index in range(int(Sprites.clip(tier, "idle")[1])):
				board.soldier_hover_outline(tier, owner, index)
				done += 1
				if Time.get_ticks_usec() - started >= BUDGET_USEC:
					if report.is_valid(): report.call(0.85 * done / maxf(total, 1))
					await get_tree().process_frame
					started = Time.get_ticks_usec()
	# One example per geometry/material variant; colors don't change pipelines.
	if report.is_valid(): report.call(0.85)
	if not owners.is_empty():
		for tier in range(1, Sprites.CLIPS.size()):
			add_sprite(board, tier, owners.keys()[0])
	board.add_house(self, Vector3.ZERO)
	board.add_tower(self, Vector3.ZERO, Color.WHITE)
	board.add_bridge(self)
	board.add_grave(self, Vector3.ZERO)
	board.add_tree(self, Vector3.ZERO)
	board.add_mountain(self, Vector2i.ZERO)
	board.add_monument(self, Color.WHITE)
	TileEffects.add_barrier(board, self, "WarmupEntrenchment", true)
	TileEffects.add_fortification(board, self)
	# Reuse the real effect templates and cursor previews, including OpenGL where
	# layers=0 alone cannot compile a shader. Restore their masks before reveal.
	board.overlays.prepare_building_previews()
	var storage: Node3D = board.overlays.building_storage
	var storage_position := storage.position
	storage.position = board.focus
	var surfaces := []
	for container in [board.playback, board.overlays.building_storage]:
		for surface in container.find_children("*", "GeometryInstance3D", true, false):
			surfaces.append([surface, surface.layers, surface.position])
			Lifetime.set_layers(surface, 1)
			if surface.get_parent() == board.playback: surface.position = board.focus
	# These are real draws in the game's viewport, concealed by the loading UI.
	for frame in range(3):
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			rendered_passes += 1
		if report.is_valid(): report.call(0.9 + 0.03 * (frame + 1))
	for saved in surfaces:
		Lifetime.set_layers(saved[0], saved[1])
		saved[0].position = saved[2]
	storage.position = storage_position
	hide()
	completed = true
	if report.is_valid(): report.call(1.0)

func add_sprite(board, tier: int, owner: int) -> void:
	var sprite := Sprite3D.new()
	sprite.texture = board.soldier_texture(tier, owner)
	sprite.pixel_size = Sprites.pixel_size(tier)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)
	board.sprite_lighting.sync(sprite)
	var fading := sprite.duplicate() as Sprite3D
	fading.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	fading.modulate.a = 0.5
	add_child(fading)
	board.sprite_lighting.sync(fading)
	var outline := Sprite3D.new()
	outline.texture = board.soldier_hover_outline(tier, owner)
	outline.pixel_size = sprite.pixel_size
	outline.billboard = sprite.billboard
	outline.texture_filter = sprite.texture_filter
	outline.modulate.a = 0.5
	outline.cast_shadow = sprite.cast_shadow
	add_child(outline)

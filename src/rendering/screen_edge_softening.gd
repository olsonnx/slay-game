extends CanvasLayer
## Read the world before the HUD is drawn; only the two edge bands are shaded.
const EDGE_SHADER = preload("res://resources/shaders/screen_edge_softening.gdshader")

func _ready() -> void:
	name = "ScreenEdgeSoftening"
	layer = 0
	var shader_material := ShaderMaterial.new()
	shader_material.shader = EDGE_SHADER
	for bounds in [Vector2(0.0, 0.20), Vector2(0.76, 1.0)]:
		var strip := ColorRect.new()
		strip.name = "Top" if bounds.x == 0.0 else "Bottom"
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.material = shader_material
		add_child(strip)
		strip.anchor_right = 1.0
		strip.anchor_top = bounds.x
		strip.anchor_bottom = bounds.y

extends TextureRect
## One treatment for every event painting; source files stay untouched.
const PAINTING_SHADER = preload("res://src/ui/event_painting.gdshader")

func _init(image: Texture2D, width: float, caption := "") -> void:
	name = "EventPainting"
	texture = image
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = caption
	size = Vector2(width, width * float(image.get_height()) / float(image.get_width()))
	var treatment := ShaderMaterial.new()
	treatment.shader = PAINTING_SHADER
	treatment.set_shader_parameter("rect_size", size)
	treatment.set_shader_parameter("corner_radius", 8.0)
	material = treatment
	resized.connect(func(): treatment.set_shader_parameter("rect_size", size))

func _make_custom_tooltip(text_value: String) -> Object:
	return preload("res://src/ui/compact_tooltip.gd").create(text_value)

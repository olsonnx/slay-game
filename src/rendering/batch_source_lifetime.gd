extends RefCounted
## Godot 4.6 Forward+ skips light unpairing when geometry layers change.
## Unpair by visibility first, while the old layer mask is still installed.
static func set_layers(source: GeometryInstance3D, layers: int) -> void:
	if source.layers == layers: return
	var paired: bool = source.is_inside_tree() and source.is_visible_in_tree() and RenderingServer.get_current_rendering_method() == "forward_plus"
	if paired: RenderingServer.instance_set_visible(source.get_instance(), false)
	source.layers = layers
	if paired: RenderingServer.instance_set_visible(source.get_instance(), true)

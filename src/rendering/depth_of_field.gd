extends RefCounted
## Diorama depth blur fades with zoom; focus stays on the camera target.
const DEFAULTS := {
	"enabled": true, "amount": 0.14, "full_zoom": 9.0, "clear_zoom": 16.0,
	"sharp_band": 0.30, "transition": 0.70
}

static func update(camera: Camera3D, focus: Vector3) -> void:
	var attributes := camera.attributes as CameraAttributesPractical
	if attributes == null:
		attributes = CameraAttributesPractical.new()
		camera.attributes = attributes
	# Use view depth, not radial distance: the board uses orthographic cameras.
	var distance := (camera.position - focus).dot(camera.basis.z)
	var forward := camera.basis.z
	var ground_depth_span := camera.size * 0.5 * Vector2(forward.x, forward.z).length() / maxf(absf(forward.y), 0.1)
	# The lab can override this camera only; gameplay uses the shared defaults.
	var settings: Dictionary = camera.get_meta("dof_settings", DEFAULTS)
	var sharp_half_width := maxf(2.0, ground_depth_span * clampf(float(settings.get("sharp_band", DEFAULTS.sharp_band)), 0.1, 0.8))
	var transition := maxf(3.0, ground_depth_span * clampf(float(settings.get("transition", DEFAULTS.transition)), 0.2, 1.5))
	# Only close inspection has a diorama blur. Moderate/wide views are sharp.
	var fade_end := clampf(float(settings.get("clear_zoom", DEFAULTS.clear_zoom)), 9.0, 80.0)
	var fade_start := clampf(float(settings.get("full_zoom", DEFAULTS.full_zoom)), 8.0, fade_end - 0.5)
	var amount := clampf(float(settings.get("amount", DEFAULTS.amount)), 0.0, 0.3)
	var strength := 1.0 - smoothstep(fade_start, fade_end, camera.size) if settings.get("enabled", true) else 0.0
	attributes.dof_blur_near_enabled = strength * amount > 0.0
	attributes.dof_blur_far_enabled = strength * amount > 0.0
	attributes.dof_blur_amount = amount * strength
	attributes.dof_blur_near_distance = maxf(0.1, distance - sharp_half_width)
	attributes.dof_blur_far_distance = distance + sharp_half_width
	attributes.dof_blur_near_transition = transition
	attributes.dof_blur_far_transition = transition

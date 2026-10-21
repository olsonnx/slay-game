extends RefCounted
## Shared art direction. Simple restores the original parameters exactly.
static var grade: GradientTexture1D
static var contact_texture: Texture2D

static func apply(environment: Environment, sun: DirectionalLight3D, style: String) -> void:
	var rich := style != "simple"
	var atmosphere := style == "atmospheric"
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	sun.rotation_degrees = Vector3(-43,-38,0) if rich else Vector3(-52,-32,0)
	sun.light_color = Color("ffe6be") if atmosphere else Color("ffebcb") if rich else Color("fff0d3")
	sun.light_energy = 0.92 if atmosphere else 1.02 if rich else 0.88
	environment.ambient_light_color = Color("92aecf") if atmosphere else Color("a9bed1") if rich else Color("b8c8d1")
	environment.ambient_light_energy = 0.32 if atmosphere else 0.36 if rich else 0.42
	environment.adjustment_enabled = rich
	environment.adjustment_contrast = 1.035 if rich else 1.0
	environment.adjustment_saturation = 0.98 if atmosphere else 1.0
	environment.adjustment_color_correction = color_grade() if atmosphere else null
	environment.fog_enabled = false
	# Keep the strategy board sharp; use restrained depth shading rather than blur.
	environment.ssao_enabled = forward_plus and atmosphere and sun.shadow_enabled
	environment.ssao_radius = 0.55
	environment.ssao_intensity = 0.46
	environment.ssao_light_affect = 0.10
	sun.light_angular_distance = 0.15 if forward_plus and atmosphere else 0.0
	if forward_plus and atmosphere:
		sun.light_color = Color("fff0d8")
		sun.light_energy = 1.35
		environment.ambient_light_energy = 0.32
		environment.adjustment_saturation = 1.0

static func color_grade() -> GradientTexture1D:
	if grade == null:
		grade = GradientTexture1D.new()
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0,0.22,0.55,0.8,1.0])
		gradient.colors = PackedColorArray([Color(0,0.005,0.018),Color(0.19,0.205,0.235),Color(0.49,0.495,0.50),Color(0.735,0.73,0.71),Color(0.93,0.91,0.875)])
		grade.gradient = gradient
		grade.width = 256
	return grade

static func contact_shadow() -> Texture2D:
	if contact_texture == null:
		var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
		for x in range(32):
			for y in range(32):
				var radius := Vector2(x-15.5,y-15.5).length()/15.5
				image.set_pixel(x,y,Color(0.055,0.075,0.12,pow(maxf(0,1.0-radius),1.1)*0.62))
		contact_texture = ImageTexture.create_from_image(image)
	return contact_texture

static func apply_material(material: StandardMaterial3D, rich: bool, simple_shadow: Texture2D) -> void:
	match material.get_meta("lighting_role",""):
		"contact": material.albedo_texture = contact_shadow() if rich else simple_shadow
		"window":
			material.emission_enabled = rich
			material.emission = Color("f6bd71")
			material.emission_energy_multiplier = 0.35 if rich else 0.0

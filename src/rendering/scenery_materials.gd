extends RefCounted
## Smooth surface finishes for the map's scenery, without grain or noise.

static func apply(material: StandardMaterial3D, kind: String) -> void:
	material.roughness = {"bark": 0.96, "foliage": 0.86, "rock": 0.93, "snow": 0.72}[kind]
	material.metallic_specular = 0.38 if kind == "snow" else 0.22

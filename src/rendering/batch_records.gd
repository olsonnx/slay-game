extends RefCounted
## Shared zero-allocation record contract for static batches and terrain chunks.
## Source transforms are tile-local in source_cache and batch-local after scanning.
enum Source { NODE, ID, KEY, TRANSFORM, COLOR, LAYERS, MATERIAL_KEY, MATERIAL_ID, SHADOW }
enum Suppressed { NODE, LAYERS, TRANSFORM_NOTIFICATION }
enum Signature { ID, KEY, TRANSFORM, COLOR, GEOMETRY }

static func source(node: MeshInstance3D, key: String, transform: Transform3D, color: Color, layers: int, material_key: String, material_id: int, shadow: int) -> Array:
	return [node, node.get_instance_id(), key, transform, color, layers, material_key, material_id, shadow]

extends Node3D
class_name TerrainChunk

var chunk_id: String = ""
var generation_seed: int = 0
var mesh_instance: MeshInstance3D
var static_body: StaticBody3D

func build_from_data(chunk_data: Dictionary) -> void:
	reset_runtime()
	chunk_id = str(chunk_data.get("chunk_id", "unknown"))
	generation_seed = int(chunk_data.get("generation_seed", 0))
	name = "TerrainChunk_%s" % chunk_id.replace(":", "_")
	add_to_group("generated_terrain_chunk")

	var vertices: PackedVector3Array = chunk_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = chunk_data.get("normals", PackedVector3Array())
	var colors: PackedColorArray = chunk_data.get("colors", PackedColorArray())
	var indices: PackedInt32Array = chunk_data.get("indices", PackedInt32Array())
	var collision_faces: PackedVector3Array = chunk_data.get("collision_faces", PackedVector3Array())
	if vertices.is_empty() or indices.is_empty():
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var terrain_mesh := ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.vertex_color_use_as_albedo = true
	terrain_mesh.surface_set_material(0, material)

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = terrain_mesh
	add_child(mesh_instance)

	if not collision_faces.is_empty():
		static_body = StaticBody3D.new()
		static_body.name = "TerrainCollision"
		var collision := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(collision_faces)
		collision.shape = shape
		static_body.add_child(collision)
		add_child(static_body)

func reset_runtime() -> void:
	for child in get_children():
		child.queue_free()
	chunk_id = ""
	generation_seed = 0
	mesh_instance = null
	static_body = null
	visible = true

func prepare_for_pool() -> void:
	reset_runtime()
	visible = false
	remove_from_group("generated_terrain_chunk")

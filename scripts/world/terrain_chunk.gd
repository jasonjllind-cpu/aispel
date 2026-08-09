extends Node3D
class_name TerrainChunk

const VALIDATOR := preload("res://scripts/world/world_generation_validator.gd")

var chunk_id: String = ""
var generation_seed: int = 0
var data_signature: String = ""
var format_version: int = 0
var mesh_instance: MeshInstance3D
var static_body: StaticBody3D
var build_succeeded: bool = false
var build_error: String = ""

func build_from_data(chunk_data: Dictionary) -> bool:
	reset_runtime()
	var validation: Dictionary = VALIDATOR.validate_chunk(chunk_data)
	if validation.get("ok", false) != true:
		build_error = str(validation.get("error", "invalid_chunk_data"))
		name = "RejectedTerrainChunk"
		visible = false
		push_error("Terrain chunk rejected before build: %s" % build_error)
		return false

	chunk_id = str(chunk_data.get("chunk_id", "unknown"))
	generation_seed = int(chunk_data.get("generation_seed", 0))
	data_signature = str(chunk_data.get("data_signature", ""))
	format_version = int(chunk_data.get("format_version", 0))
	name = "TerrainChunk_%s" % chunk_id.replace(":", "_")
	add_to_group("generated_terrain_chunk")

	var vertices: PackedVector3Array = chunk_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = chunk_data.get("normals", PackedVector3Array())
	var colors: PackedColorArray = chunk_data.get("colors", PackedColorArray())
	var indices: PackedInt32Array = chunk_data.get("indices", PackedInt32Array())
	var collision_faces: PackedVector3Array = chunk_data.get("collision_faces", PackedVector3Array())

	# Rendering is presentation-only. A future dedicated server needs terrain
	# collision/state, but must not ask the dummy/headless renderer to build meshes.
	if DisplayServer.get_name() != "headless":
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
		# Steep generated slopes can expose a triangle from below when the
		# spring-arm camera hugs the ground. Keep terrain visually solid from
		# both sides; collision remains the same validated mesh.
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		terrain_mesh.surface_set_material(0, material)

		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "TerrainMesh"
		mesh_instance.mesh = terrain_mesh
		add_child(mesh_instance)

	# Collision remains available in headless mode so server-side movement and
	# authoritative gameplay can use the exact same validated terrain data.
	static_body = StaticBody3D.new()
	static_body.name = "TerrainCollision"
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	# Generated triangles can be reached from either side during chunk startup.
	# Two-sided collision prevents the player from falling through a visually
	# solid surface because of winding or a one-frame below-surface spawn.
	shape.backface_collision = true
	shape.set_faces(collision_faces)
	collision.shape = shape
	static_body.add_child(collision)
	add_child(static_body)

	build_succeeded = true
	visible = true
	return true

func reset_runtime() -> void:
	for child in get_children():
		child.free()
	remove_from_group("generated_terrain_chunk")
	chunk_id = ""
	generation_seed = 0
	data_signature = ""
	format_version = 0
	mesh_instance = null
	static_body = null
	build_succeeded = false
	build_error = ""
	visible = true

func prepare_for_pool() -> void:
	reset_runtime()
	visible = false
